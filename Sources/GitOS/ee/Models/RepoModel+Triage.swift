import Foundation

/// Everything the Triage view needs, computed per repo. Clusters and scores come from
/// metadata alone; AI verdicts are produced one PR at a time, only when asked.
struct TriageState {
    var isLoading = false
    var loadedAt: Date?
    var error: String?
    var files: [Int: [GitHubRepoAPI.PRFile]] = [:]
    /// Groups of near-identical PRs, oldest number first in each group.
    var clusters: [[Int]] = []
    var scores: [Int: PRTriage.Score] = [:]
    /// AI pre-review verdicts, one short paragraph per PR.
    var verdicts: [Int: String] = [:]
    /// PR numbers whose pre-review is running.
    var reviewing: Set<Int> = []
    /// PR numbers currently being closed.
    var closing: Set<Int> = []

    /// PR numbers that belong to some duplicate group.
    var clustered: Set<Int> { Set(clusters.flatMap { $0 }) }
}

extension RepoModel {
    /// How many PRs get their file lists fetched for clustering. Keeps one triage pass
    /// within ~60 API requests even on flooded repositories.
    static let triageFileLimit = 60

    /// Fetches changed files for the open PRs, then computes duplicate clusters and scores.
    func loadTriage(force: Bool = false) async {
        guard let github else { return }
        if !force, let loaded = triage.loadedAt, Date.now.timeIntervalSince(loaded) < 300 { return }
        triage.isLoading = true
        defer { triage.isLoading = false }

        await loadGitHub()
        let prs = Array(pullRequests.prefix(Self.triageFileLimit))
        var files = triage.files
        await withTaskGroup(of: (Int, [GitHubRepoAPI.PRFile])?.self) { group in
            var pending = prs.filter { force || files[$0.number] == nil }.makeIterator()
            func addNext(_ group: inout TaskGroup<(Int, [GitHubRepoAPI.PRFile])?>) {
                guard let pr = pending.next() else { return }
                group.addTask { (try? await github.files(for: pr.number)).map { (pr.number, $0) } }
            }
            for _ in 0..<6 { addNext(&group) }
            while let result = await group.next() {
                if let (number, list) = result { files[number] = list }
                addNext(&group)
            }
        }

        triage.files = files
        triage.clusters = PRTriage.clusters(of: prs.compactMap { pr in
            files[pr.number].map { (pr.number, PRTriage.signature(of: $0)) }
        })
        var scores: [Int: PRTriage.Score] = [:]
        for pr in pullRequests {
            scores[pr.number] = PRTriage.score(pr: pr, checks: prChecks[pr.number], files: files[pr.number])
        }
        triage.scores = scores
        triage.loadedAt = .now
        triage.error = pullRequests.isEmpty ? githubError : nil
    }

    /// Open PRs ordered by triage score, best first (stable for equal scores).
    var triagedPullRequests: [GitHubRepoAPI.PullRequest] {
        pullRequests.sorted { (triage.scores[$0.number]?.total ?? 0) > (triage.scores[$1.number]?.total ?? 0) }
    }

    /// Asks the user's own AI (signed-in CLI or API key) for a three-question pre-review.
    /// A hint for the maintainer, never a decision.
    func preReview(_ pr: GitHubRepoAPI.PullRequest) async {
        guard !triage.reviewing.contains(pr.number) else { return }
        triage.reviewing.insert(pr.number)
        defer { triage.reviewing.remove(pr.number) }
        var files = triage.files[pr.number]
        if files == nil { files = try? await github?.files(for: pr.number) }
        if let files { triage.files[pr.number] = files }
        do {
            triage.verdicts[pr.number] = try await Claude.triageVerdict(
                title: pr.title, body: pr.body ?? "", files: files ?? [],
                model: app.preferences.aiModel, provider: app.preferences.aiProvider)
        } catch {
            triage.verdicts[pr.number] = "Pre-review failed: \(error.localizedDescription)"
        }
    }

    /// Closes each PR with the same comment, posted first so nobody gets a silent close.
    /// Returns the numbers that could not be closed.
    func closePullRequests(_ numbers: [Int], comment: String) async -> [Int] {
        guard let github else { return numbers }
        var failed: [Int] = []
        for number in numbers {
            triage.closing.insert(number)
            defer { triage.closing.remove(number) }
            do {
                let text = comment.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { try await github.comment(on: number, body: text) }
                try await github.closePullRequest(number)
                pullRequests.removeAll { $0.number == number }
            } catch {
                failed.append(number)
            }
        }
        triage.clusters = triage.clusters.map { $0.filter { number in pullRequests.contains { $0.number == number } } }
            .filter { $0.count >= 2 }
        return failed
    }
}

extension Claude {
    /// One short pre-review: does the diff do what the description says, does it address
    /// a linked issue, and does it contain anything unrelated?
    static func triageVerdict(title: String, body: String, files: [GitHubRepoAPI.PRFile],
                              model: String, provider: AIProvider) async throws -> String {
        let system = """
        You pre-review pull requests for a busy maintainer. Answer three questions from the diff alone: \
        does the change do what the title and description claim, does it plausibly address the linked issue \
        if one is mentioned, and does it include anything unrelated? Reply with one plain-text paragraph of \
        at most 60 words, starting with "Matches:" or "Mismatch:" or "Unclear:". Be concrete about files and \
        hunks; never recommend merging or closing — that is the maintainer's call.
        """
        var patches = ""
        for file in files {
            patches += "--- \(file.filename) (+\(file.additions) −\(file.deletions))\n\(file.patch ?? "(no patch)")\n"
            if patches.count > 60_000 { patches += "…(remaining files omitted)"; break }
        }
        let prompt = """
        Title: \(title)

        Description:
        \(body.isEmpty ? "(none)" : body)

        Changed files:
        \(patches.isEmpty ? "(none)" : patches)
        """
        return try await complete(system: system, prompt: prompt, model: model, provider: provider)
    }
}
