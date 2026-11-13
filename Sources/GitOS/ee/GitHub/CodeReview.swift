import Foundation

/// Pure code-review logic: builds the prompt, parses the model's reply into structured
/// findings, and renders them back out as Markdown. Nothing here talks to the network,
/// so every piece is unit-testable. The review is advisory — it never gates anything.
enum CodeReview {
    // MARK: Findings

    enum Severity: String, Codable, CaseIterable, Sendable, Comparable {
        case blocker, warning, nit

        /// Blockers sort first.
        static func < (a: Severity, b: Severity) -> Bool { a.rank < b.rank }
        private var rank: Int {
            switch self {
            case .blocker: 0
            case .warning: 1
            case .nit: 2
            }
        }
    }

    enum Confidence: String, Codable, Sendable { case high, medium, low }

    struct Finding: Identifiable, Hashable, Sendable {
        var severity: Severity
        var confidence: Confidence
        var file: String
        var line: Int?
        var title: String
        var detail: String
        var suggestion: String?

        var id: String { "\(file):\(line ?? 0):\(title)" }

        /// Stable key for "don't show me this again", tolerant of line-number drift.
        var dismissalKey: String {
            "\(file)|\(severity.rawValue)|\(title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))"
        }
    }

    enum Verdict: Sendable {
        case approve, caution, block

        static func from(_ findings: [Finding]) -> Verdict {
            if findings.contains(where: { $0.severity == .blocker }) { return .block }
            if findings.contains(where: { $0.severity == .warning }) { return .caution }
            return .approve
        }
    }

    struct Review: Hashable, Sendable {
        var summary: String
        /// Whether the change does what its linked issue asks; nil when nothing was linked.
        var issueCompliance: String?
        var findings: [Finding]
        /// Files left out of the prompt because of the size budget.
        var skippedFiles: [String] = []
        var date = Date.now

        var verdict: Verdict { Verdict.from(findings) }
        func count(_ severity: Severity) -> Int { findings.count(where: { $0.severity == severity }) }
    }

    // MARK: Input

    /// One changed file as the prompt sees it: the diff, plus the whole file when it fits.
    struct File: Sendable {
        var path: String
        var patch: String
        var content: String?
    }

    /// Prompt budgets, in characters. Small enough to stay fast and well under the
    /// 600K input refusal in Claude.complete even with every budget maxed out.
    enum Budget {
        static let patches = 60_000
        static let contents = 160_000
        static let perFileContent = 24_000
        static let rules = 8_000
        static let issue = 2_000
    }

    /// Names tried in the repository root for review rules, most specific first.
    static let rulesFileNames = [".gitos/review.md", "REVIEW.md", "CLAUDE.md", "AGENTS.md"]

    // MARK: Prompt

    static let systemPrompt = """
    You review code changes for a maintainer. Find real problems: bugs, crashes, data loss, races, \
    security holes, broken edge cases, and changes that contradict how the rest of the code works. \
    Style points are "nit" severity at most, and only when they genuinely hurt the next reader. \
    Report only what you'd stake your name on — a missed nit is fine, a false blocker is not.

    Reply with ONLY a JSON object, no code fence, in exactly this shape:
    {"summary": "one or two plain sentences on the change as a whole",
     "issueCompliance": "one sentence: does the change do what the linked issue asks (null when no issue is given)",
     "findings": [{"severity": "blocker|warning|nit", "confidence": "high|medium|low",
                   "file": "path as given", "line": 123 or null,
                   "title": "short claim, under 80 characters",
                   "detail": "why it's a problem and what breaks, 1-3 sentences",
                   "suggestion": "concrete fix as code or one sentence, or null"}]}

    "blocker" means merging/committing this would ship a real defect. "warning" means it likely \
    needs a change but won't corrupt anything. An empty findings array is a perfectly good answer. \
    Line numbers refer to the NEW file. Never invent files or lines that aren't in the input.
    """

    struct PromptInput {
        /// E.g. "Pull request #14 into main" or "Uncommitted changes" or "Commit a3f91c2".
        var heading: String
        var title: String?
        var description: String?
        /// The linked issue's text, when one is referenced.
        var issue: String?
        /// Review rules found in the repository.
        var rules: String?
        var files: [File]
    }

    /// The user prompt, plus the files that didn't fit the budget.
    static func prompt(for input: PromptInput) -> (text: String, skipped: [String]) {
        var sections: [String] = ["Reviewing: \(input.heading)"]
        if let title = input.title, !title.isEmpty { sections.append("Title: \(title)") }
        if let description = input.description, !description.isEmpty {
            sections.append("Description:\n\(String(description.prefix(4_000)))")
        }
        if let issue = input.issue, !issue.isEmpty {
            sections.append("Linked issue:\n\(String(issue.prefix(Budget.issue)))")
        }
        if let rules = input.rules, !rules.isEmpty {
            sections.append("Review rules for this repository:\n\(String(rules.prefix(Budget.rules)))")
        }

        var skipped: [String] = []
        var patches = "", patchBudget = Budget.patches
        for file in input.files {
            let block = "--- \(file.path)\n\(file.patch)\n"
            if block.count > patchBudget {
                skipped.append(file.path)
                continue
            }
            patches += block
            patchBudget -= block.count
        }
        sections.append("Changed files (unified diff):\n\(patches.isEmpty ? "(none)" : patches)")
        if !skipped.isEmpty {
            sections.append("Not shown (too large): \(skipped.joined(separator: ", "))")
        }

        var contents = "", contentBudget = Budget.contents
        for file in input.files where !skipped.contains(file.path) {
            guard let content = file.content, !content.isEmpty, content.count <= Budget.perFileContent else { continue }
            let block = "=== \(file.path)\n\(content)\n"
            guard block.count <= contentBudget else { continue }
            contents += block
            contentBudget -= block.count
        }
        if !contents.isEmpty {
            sections.append("Full current contents of the changed files, for context:\n\(contents)")
        }
        return (sections.joined(separator: "\n\n"), skipped)
    }

    // MARK: Parsing

    private struct Payload: Decodable {
        struct RawFinding: Decodable {
            var severity: String?
            var confidence: String?
            var file: String?
            var line: Int?
            var title: String?
            var detail: String?
            var suggestion: String?
        }
        var summary: String?
        var issueCompliance: String?
        var findings: [RawFinding]?
    }

    /// Parses the model's reply. Fences and surrounding prose are tolerated; a reply with
    /// no JSON at all becomes a findings-free review whose summary is the reply itself.
    static func parse(_ text: String) -> Review {
        guard let data = jsonObject(in: text),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            let prose = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return Review(summary: String(prose.prefix(600)), issueCompliance: nil, findings: [])
        }
        let findings = (payload.findings ?? []).compactMap { raw -> Finding? in
            let title = raw.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let detail = raw.detail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !(title.isEmpty && detail.isEmpty) else { return nil }
            return Finding(
                severity: raw.severity.flatMap { Severity(rawValue: $0.lowercased()) } ?? .warning,
                confidence: raw.confidence.flatMap { Confidence(rawValue: $0.lowercased()) } ?? .medium,
                file: raw.file ?? "",
                line: raw.line,
                title: title.isEmpty ? String(detail.prefix(80)) : title,
                detail: detail,
                suggestion: raw.suggestion?.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        .sorted { ($0.severity, $0.file, $0.line ?? 0) < ($1.severity, $1.file, $1.line ?? 0) }
        var compliance = payload.issueCompliance?.trimmingCharacters(in: .whitespacesAndNewlines)
        if compliance?.isEmpty == true || compliance?.lowercased() == "null" { compliance = nil }
        return Review(summary: payload.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                      issueCompliance: compliance,
                      findings: findings)
    }

    /// The outermost {...} in the text, fences and prose stripped.
    private static func jsonObject(in text: String) -> Data? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else { return nil }
        return Data(text[start...end].utf8)
    }

    // MARK: Output

    static func markdown(for review: Review, heading: String) -> String {
        var out = "## AI review — \(heading)\n\n"
        if !review.summary.isEmpty { out += review.summary + "\n\n" }
        if let compliance = review.issueCompliance { out += "**Linked issue:** \(compliance)\n\n" }
        if review.findings.isEmpty {
            out += "No issues found.\n"
        }
        for finding in review.findings {
            let place = finding.line.map { "\(finding.file):\($0)" } ?? finding.file
            out += "- **\(finding.severity.rawValue.uppercased())** `\(place)` — \(finding.title)\n"
            if !finding.detail.isEmpty { out += "  \(finding.detail)\n" }
            if let fix = finding.suggestion, !fix.isEmpty {
                out += fix.contains("\n") || fix.contains("{") || fix.contains("(")
                    ? "  ```suggestion\n\(fix)\n  ```\n"
                    : "  Fix: \(fix)\n"
            }
        }
        if !review.skippedFiles.isEmpty {
            out += "\n_Not reviewed (too large): \(review.skippedFiles.joined(separator: ", "))_\n"
        }
        out += "\n_Reviewed with GitOS. Advisory only — a human makes the call._"
        return out
    }

    /// A self-contained instruction for a coding agent (Claude Code, Codex) to fix one finding.
    static func fixPrompt(for finding: Finding) -> String {
        var out = "Fix this code review finding"
        out += finding.line.map { " in \(finding.file) at line \($0)" } ?? " in \(finding.file)"
        out += ":\n\n\(finding.title)"
        if !finding.detail.isEmpty { out += "\n\n\(finding.detail)" }
        if let fix = finding.suggestion, !fix.isEmpty { out += "\n\nSuggested fix:\n\(fix)" }
        out += "\n\nMake the change, keep it minimal, and run the tests if there are any."
        return out
    }
}
