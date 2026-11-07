import Foundation

/// Review state per repo. A review is keyed by what it looked at, so the PR panel,
/// the pre-commit panel and the commit panel never clobber each other.
struct ReviewState {
    enum Target: Hashable, Sendable {
        case pullRequest(Int)
        case commit(String)
        case workingTree
    }

    var reviews: [Target: CodeReview.Review] = [:]
    /// What each review looked at (head SHA, commit SHA, or a diff fingerprint),
    /// so the UI can say "the code moved on" instead of showing stale findings as fresh.
    var anchors: [Target: String] = [:]
    var running: Set<Target> = []
    var errors: [Target: String] = [:]
    /// Targets whose hidden nits the user expanded.
    var showNits: Set<Target> = []
}

extension RepoModel {
    /// How many changed files one review will consider. Matches the triage cap in spirit:
    /// keeps the prompt affordable even on sprawling changes.
    static let reviewFileLimit = 50

    // MARK: Running a review

    func runReview(_ target: ReviewState.Target) async {
        guard !reviewState.running.contains(target) else { return }
        reviewState.running.insert(target)
        reviewState.errors[target] = nil
        defer { reviewState.running.remove(target) }
        do {
            let (input, anchor) = try await reviewInput(for: target)
            guard input.files.contains(where: { !$0.patch.isEmpty }) else {
                throw Claude.Failure(message: "There's nothing to review — the diff is empty.")
            }
            let (prompt, skipped) = CodeReview.prompt(for: input)
            let reply = try await Claude.complete(system: CodeReview.systemPrompt, prompt: prompt,
                                                  model: app.preferences.aiModel,
                                                  provider: app.preferences.aiProvider)
            var review = CodeReview.parse(reply)
            review.skippedFiles = skipped
            review.findings.removeAll { dismissedFindingKeys.contains($0.dismissalKey) }
            reviewState.reviews[target] = review
            reviewState.anchors[target] = anchor
        } catch {
            reviewState.errors[target] = error.localizedDescription
        }
    }

    /// Nil when the review still matches what it looked at; otherwise a short explanation.
    func reviewStaleness(for target: ReviewState.Target) -> String? {
        guard let anchor = reviewState.anchors[target], reviewState.reviews[target] != nil else { return nil }
        switch target {
        case .pullRequest(let number):
            guard let pr = pullRequests.first(where: { $0.number == number }), pr.head.sha != anchor else { return nil }
            return "New commits since this review — re-review to catch up."
        case .workingTree, .commit:
            return nil
        }
    }

    /// The highest-severity finding for a file in the working-tree review, for list markers.
    func workingTreeFindingSeverity(for path: String) -> CodeReview.Severity? {
        reviewState.reviews[.workingTree]?.findings
            .filter { $0.file == path && $0.severity != .nit }
            .map(\.severity).min()
    }

    // MARK: Acting on findings

    /// Hides the finding now and in every later review of this repository.
    func dismissFinding(_ finding: CodeReview.Finding, for target: ReviewState.Target) {
        dismissedFindingKeys.insert(finding.dismissalKey)
        reviewState.reviews[target]?.findings.removeAll { $0.dismissalKey == finding.dismissalKey }
    }

    /// Posts the whole review as one PR comment. Never called automatically.
    func postReviewComment(for number: Int) async -> Bool {
        guard let github, let review = reviewState.reviews[.pullRequest(number)] else { return false }
        do {
            try await github.comment(on: number, body: CodeReview.markdown(for: review, heading: "pull request #\(number)"))
            return true
        } catch {
            reviewState.errors[.pullRequest(number)] = error.localizedDescription
            return false
        }
    }

    private var dismissedFindingsKey: String { "reviewDismissed:\(repo.url.path)" }

    private var dismissedFindingKeys: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: dismissedFindingsKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue).sorted(), forKey: dismissedFindingsKey) }
    }

    // MARK: Gathering what to review

    private func reviewInput(for target: ReviewState.Target) async throws -> (CodeReview.PromptInput, String) {
        switch target {
        case .pullRequest(let number):
            try await pullRequestInput(number)
        case .commit(let sha):
            try await commitInput(sha)
        case .workingTree:
            try await workingTreeInput()
        }
    }

    private func pullRequestInput(_ number: Int) async throws -> (CodeReview.PromptInput, String) {
        guard let github, let pr = pullRequests.first(where: { $0.number == number }) else {
            throw Claude.Failure(message: "This pull request is no longer loaded.")
        }
        let prFiles = Array(try await github.files(for: number).prefix(Self.reviewFileLimit))
        // Full contents give the model the code around each hunk; fetched best-effort.
        var contents: [String: String] = [:]
        await withTaskGroup(of: (String, String)?.self) { group in
            var pending = prFiles.filter { $0.patch != nil }.map(\.filename).makeIterator()
            func addNext(_ group: inout TaskGroup<(String, String)?>) {
                guard let path = pending.next() else { return }
                let sha = pr.head.sha
                group.addTask {
                    guard let text = try? await github.fileContent(path: path, ref: sha), !text.isEmpty else { return nil }
                    return (path, text)
                }
            }
            for _ in 0..<4 { addNext(&group) }
            while let result = await group.next() {
                if let (path, text) = result, text.count <= CodeReview.Budget.perFileContent { contents[path] = text }
                addNext(&group)
            }
        }
        let files = prFiles.map { file in
            CodeReview.File(path: file.filename,
                            patch: file.patch ?? "(binary or oversized: +\(file.additions) −\(file.deletions))",
                            content: contents[file.filename])
        }
        return (CodeReview.PromptInput(
            heading: "Pull request #\(number) into \(pr.base.ref)",
            title: pr.title,
            description: pr.body,
            issue: linkedIssueText(in: pr.body),
            rules: reviewRules(),
            files: files
        ), pr.head.sha)
    }

    private func commitInput(_ sha: String) async throws -> (CodeReview.PromptInput, String) {
        let diffs = try await repo.show(sha)
        let message = (try? await Git.run(["show", "-s", "--format=%B", sha], in: repo.url))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var files: [CodeReview.File] = []
        for diff in diffs.prefix(Self.reviewFileLimit) {
            let content = try? await Git.run(["show", "\(sha):\(diff.path)"], in: repo.url)
            files.append(CodeReview.File(path: diff.path, patch: diff.reviewPatch, content: content))
        }
        return (CodeReview.PromptInput(
            heading: "Commit \(String(sha.prefix(7)))",
            title: commits.first { $0.sha == sha }?.subject,
            description: message,
            issue: nil,
            rules: reviewRules(),
            files: files
        ), sha)
    }

    /// Reviews what a commit would contain: the staged files when anything is staged,
    /// otherwise every local change — mirroring how the Commit button behaves.
    private func workingTreeInput() async throws -> (CodeReview.PromptInput, String) {
        let changes = status.staged.isEmpty ? status.unstaged + status.conflicted : status.staged
        guard !changes.isEmpty else {
            throw Claude.Failure(message: "The working tree is clean — nothing to review.")
        }
        var files: [CodeReview.File] = []
        for change in changes.prefix(Self.reviewFileLimit) {
            guard let diff = try? await repo.diff(for: change), !diff.hunks.isEmpty || diff.isBinary else { continue }
            let content = try? String(contentsOf: repo.url.appendingPathComponent(change.path), encoding: .utf8)
            files.append(CodeReview.File(path: change.path, patch: diff.reviewPatch, content: content))
        }
        let scope = status.staged.isEmpty ? "Uncommitted changes" : "Staged changes about to be committed"
        let fingerprint = "\(files.count)-\(files.reduce(0) { $0 &+ $1.patch.count })"
        return (CodeReview.PromptInput(
            heading: scope,
            title: summary.isEmpty ? nil : summary,
            description: details.isEmpty ? nil : details,
            issue: nil,
            rules: reviewRules(),
            files: files
        ), fingerprint)
    }

    // MARK: Context

    /// The first review-rules file found in the repository root.
    private func reviewRules() -> String? {
        for name in CodeReview.rulesFileNames {
            let url = repo.url.appendingPathComponent(name)
            if let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty {
                return String(text.prefix(CodeReview.Budget.rules))
            }
        }
        return nil
    }

    /// The text of the first open issue the body references, so the review can check compliance.
    private func linkedIssueText(in body: String?) -> String? {
        guard let body, let match = body.firstMatch(of: /#(\d+)/), let number = Int(match.1) else { return nil }
        guard let issue = issues.first(where: { $0.number == number }) else {
            return "#\(number) (referenced, but not among the open issues)"
        }
        var text = "#\(issue.number) \(issue.title)"
        if let issueBody = issue.body, !issueBody.isEmpty { text += "\n\(issueBody)" }
        return String(text.prefix(CodeReview.Budget.issue))
    }
}

extension FileDiff {
    /// The whole file's diff as patch text, the way the review prompt wants it.
    var reviewPatch: String {
        if isBinary { return "(binary file)" }
        return (headerLines + hunks.flatMap { [$0.header] + $0.lines.map(\.raw) }).joined(separator: "\n")
    }
}
