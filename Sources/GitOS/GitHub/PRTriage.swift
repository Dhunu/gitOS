import Foundation

/// Pure triage logic for a flood of pull requests: groups near-identical changes and
/// scores each PR on cheap signals, so the list can be ordered by "worth a human's time".
/// Nothing here decides anything — scores and clusters are hints the maintainer acts on.
enum PRTriage {
    // MARK: Duplicate clustering

    /// A PR's change content as a set of comparable tokens: each added or removed line,
    /// normalized, prefixed with its file. Context lines and hunk headers are ignored so
    /// the same fix at different line numbers still matches.
    static func signature(of files: [GitHubRepoAPI.PRFile]) -> Set<String> {
        var tokens: Set<String> = []
        for file in files {
            for line in (file.patch ?? "").split(separator: "\n") {
                guard let first = line.first, first == "+" || first == "-" else { continue }
                if line.hasPrefix("+++") || line.hasPrefix("---") { continue }
                let content = line.dropFirst().trimmingCharacters(in: .whitespaces)
                guard !content.isEmpty else { continue }
                tokens.insert("\(file.filename)\(first)\(content)")
            }
            if file.patch == nil {
                // Binary or huge file: fall back to the file path so identical file sets still compare.
                tokens.insert("\(file.filename)~\(file.additions)+\(file.deletions)")
            }
        }
        return tokens
    }

    static func similarity(_ a: Set<String>, _ b: Set<String>) -> Double {
        guard !a.isEmpty || !b.isEmpty else { return 1 }
        let union = a.union(b).count
        guard union > 0 else { return 0 }
        return Double(a.intersection(b).count) / Double(union)
    }

    /// Groups of PR numbers whose diffs are near-identical (Jaccard ≥ `threshold`).
    /// Greedy: each PR joins the first group it matches. Only groups of 2+ are returned,
    /// each sorted ascending so the oldest PR number leads.
    static func clusters(of signatures: [(number: Int, signature: Set<String>)], threshold: Double = 0.7) -> [[Int]] {
        var groups: [(signature: Set<String>, numbers: [Int])] = []
        for item in signatures.sorted(by: { $0.number < $1.number }) {
            guard !item.signature.isEmpty else { continue }
            if let index = groups.firstIndex(where: { similarity($0.signature, item.signature) >= threshold }) {
                groups[index].numbers.append(item.number)
            } else {
                groups.append((item.signature, [item.number]))
            }
        }
        return groups.filter { $0.numbers.count >= 2 }.map(\.numbers)
    }

    // MARK: Scoring

    struct Score: Hashable, Sendable {
        var total: Int
        /// Short, human-readable reasons, best first ("CI passing", "no linked issue").
        var reasons: [String]
        /// True when something about the PR doesn't add up (e.g. big diff, empty description).
        var flagged: Bool
    }

    /// Scores a PR 0–100 from metadata alone — no AI, no extra requests.
    static func score(pr: GitHubRepoAPI.PullRequest, checks: CheckSummary?, files: [GitHubRepoAPI.PRFile]?) -> Score {
        var total = 30
        var reasons: [String] = []
        var flagged = false

        switch checks?.state {
        case .success: total += 25; reasons.append("CI passing")
        case .failure: total -= 20; reasons.append("CI failing"); flagged = true
        case .pending: reasons.append("CI pending")
        default: break
        }

        if referencesIssue(pr.body) {
            total += 20
            reasons.append("links an issue")
        } else {
            total -= 5
            reasons.append("no linked issue")
        }

        switch pr.authorAssociation {
        case "OWNER", "MEMBER": total += 25; reasons.append("maintainer")
        case "COLLABORATOR": total += 20; reasons.append("collaborator")
        case "CONTRIBUTOR": total += 15; reasons.append("has merged PRs here")
        case "FIRST_TIME_CONTRIBUTOR", "FIRST_TIMER": total += 5; reasons.append("first PR here")
        default: break
        }

        let body = pr.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let changed = files.map { $0.reduce(0) { $0 + $1.additions + $1.deletions } }
        if body.isEmpty {
            total -= 15
            reasons.append("no description")
            flagged = true
        } else if body.count >= 120 {
            total += 10
        }
        if let changed, changed > 300, body.count < 100 {
            total -= 15
            reasons.append("\(changed)-line diff, thin description")
            flagged = true
        }
        if pr.draft == true { total -= 10; reasons.append("draft") }

        return Score(total: min(max(total, 0), 100), reasons: reasons, flagged: flagged)
    }

    /// Whether the text references an issue or PR (#12, or a github.com/…/issues/12 link).
    static func referencesIssue(_ body: String?) -> Bool {
        guard let body, !body.isEmpty else { return false }
        if body.contains(/#\d+/) { return true }
        return body.contains(/github\.com\/[^\s\/]+\/[^\s\/]+\/(issues|pull)\/\d+/)
    }

    /// The polite default reply for batch-closing duplicates or off-target PRs.
    static func closeTemplate(keeping number: Int?) -> String {
        if let number {
            return """
            Thanks for the contribution! This change was already proposed in #\(number), so I'm closing this one \
            in its favor to keep the review in one place. If your version covers something #\(number) doesn't, \
            please leave a comment there.
            """
        }
        return """
        Thanks for the contribution! I'm closing this for now because it doesn't address an open issue and the \
        description doesn't explain the motivation. If you'd like to pursue it, please open an issue first \
        describing the problem, then link it from a new pull request.
        """
    }
}
