import Foundation

extension RepoModel {
    /// API client for this repo's GitHub remote, using the repo's resolved account.
    var github: GitHubRepoAPI? {
        guard let remote = primaryRemote, remote.isGitHub, let owner = remote.owner, let name = remote.repo,
              let account = resolved.account, let token = Keychain.get(account.id.uuidString) else { return nil }
        return GitHubRepoAPI(api: GitHubAPI(token: token), owner: owner, repo: name)
    }

    var githubUnavailableReason: String? {
        guard let remote = primaryRemote else { return "This repository has no remote." }
        guard remote.isGitHub else { return "The remote isn't on GitHub." }
        guard resolved.account != nil else { return "No GitHub account applies to this repository. Add one in Settings." }
        return github == nil ? "The account's token is missing. Reconnect it in Settings." : nil
    }

    /// Loads PRs, issues and checks. Throttled to once a minute unless `force`.
    func loadGitHub(force: Bool = false) async {
        guard let github else { return }
        if !force, let loaded = githubLoadedAt, Date.now.timeIntervalSince(loaded) < 60 { return }
        githubLoadedAt = .now
        do {
            async let prs = github.pullRequests()
            async let issues = github.issues()
            async let info = github.info()
            let (loadedPRs, loadedIssues) = try await (prs, issues)
            pullRequests = loadedPRs.items
            allPullRequestsLoaded = loadedPRs.isComplete
            self.issues = loadedIssues.items
            allIssuesLoaded = loadedIssues.isComplete
            self.defaultBranch = (try? await info)?.defaultBranch
            githubError = nil
        } catch {
            // A refused sign-in gets the Reconnect banner instead of "Bad credentials".
            githubError = app.noteRejectedSignIn(error, for: ref) ? nil : error.localizedDescription
        }
        await loadChecks()
    }

    func loadChecks() async {
        guard let github else { return }
        if let oid = status.oid, status.upstream != nil {
            headChecks = try? await github.checks(for: oid)
        } else {
            headChecks = nil
        }
        var results: [Int: CheckSummary] = [:]
        await withTaskGroup(of: (Int, CheckSummary?).self) { group in
            for pr in pullRequests.prefix(20) {
                group.addTask { (pr.number, try? await github.checks(for: pr.head.sha)) }
            }
            for await (number, summary) in group {
                if let summary { results[number] = summary }
            }
        }
        prChecks = results
    }

    /// A page of this repository on github.com, such as `pulls`.
    func gitHubPage(_ path: String) -> URL? {
        guard let remote = primaryRemote, remote.isGitHub, let owner = remote.owner, let name = remote.repo else { return nil }
        return URL(string: "https://github.com/\(owner)/\(name)/\(path)")
    }

    /// The open PR whose head is the current branch, if any.
    var currentPullRequest: GitHubRepoAPI.PullRequest? {
        guard let branch = status.branch else { return nil }
        return pullRequests.first { $0.head.ref == branch && !isFork($0) }
    }

    func isFork(_ pr: GitHubRepoAPI.PullRequest) -> Bool {
        pr.head.repo?.fullName != pr.base.repo?.fullName
    }

    func checkout(_ pr: GitHubRepoAPI.PullRequest) async {
        let context = app.gitContext(for: ref)
        let remote = primaryRemote?.name ?? "origin"
        await perform("Checking out #\(pr.number)") {
            try await repo.checkoutPullRequest(number: pr.number, headRef: pr.head.ref, fromFork: isFork(pr),
                                               remote: remote, context: context)
        }
    }

    /// Pushes the current branch if needed, then opens a PR from it.
    func createPullRequest(title: String, body: String, base: String, draft: Bool) async throws -> GitHubRepoAPI.PullRequest {
        guard let github, let branch = status.branch else { throw GitHubError(message: "Not on a branch.") }
        if status.upstream == nil || status.ahead > 0 {
            let context = app.gitContext(for: ref)
            let remote = primaryRemote?.name ?? "origin"
            activity = "Pushing"
            defer { activity = nil }
            try await repo.push(remote: remote, setUpstream: status.upstream == nil, context: context)
        }
        let pr = try await github.createPullRequest(title: title, body: body, head: branch, base: base, draft: draft)
        await refresh()
        await loadGitHub(force: true)
        return pr
    }

    func createIssue(title: String, body: String) async throws -> GitHubRepoAPI.Issue {
        guard let github else { throw GitHubError(message: githubUnavailableReason ?? "GitHub unavailable.") }
        let issue = try await github.createIssue(title: title, body: body)
        await loadGitHub(force: true)
        return issue
    }

    /// Commit subjects on this branch that aren't on `base` yet (for PR titles and AI descriptions).
    func commitsAhead(of base: String) async -> [String] {
        let remote = primaryRemote?.name ?? "origin"
        let output = try? await Git.run(["log", "--format=%s%n%n%b%x1e", "\(remote)/\(base)..HEAD"], in: repo.url)
        return (output ?? "").split(separator: "\u{1e}")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func diffAgainst(base: String) async -> String {
        let remote = primaryRemote?.name ?? "origin"
        return (try? await Git.run(["diff", "--no-ext-diff", "--stat", "--patch", "\(remote)/\(base)...HEAD"], in: repo.url)) ?? ""
    }
}
