import Foundation

/// Pull requests, issues and checks for one repository.
struct GitHubRepoAPI: Sendable {
    let api: GitHubAPI
    let owner: String
    let repo: String

    private var base: String { "/repos/\(owner)/\(repo)" }

    struct User: Decodable, Hashable, Sendable {
        let login: String
        let avatarURL: URL?
        enum CodingKeys: String, CodingKey { case login, avatarURL = "avatar_url" }
    }

    struct Label: Decodable, Hashable, Sendable {
        let name: String
        let color: String
    }

    struct PullRequest: Decodable, Identifiable, Hashable, Sendable {
        struct Ref: Decodable, Hashable, Sendable {
            struct Repo: Decodable, Hashable, Sendable {
                let fullName: String
                enum CodingKeys: String, CodingKey { case fullName = "full_name" }
            }
            let ref: String
            let sha: String
            let repo: Repo?
        }

        let number: Int
        let title: String
        let body: String?
        let user: User
        let head: Ref
        let base: Ref
        let draft: Bool?
        let htmlURL: URL
        let createdAt: Date
        let updatedAt: Date
        let labels: [Label]
        /// OWNER, MEMBER, COLLABORATOR, CONTRIBUTOR, FIRST_TIME_CONTRIBUTOR, FIRST_TIMER or NONE.
        let authorAssociation: String?

        var id: Int { number }

        enum CodingKeys: String, CodingKey {
            case number, title, body, user, head, base, draft, labels
            case htmlURL = "html_url", createdAt = "created_at", updatedAt = "updated_at"
            case authorAssociation = "author_association"
        }
    }

    /// One changed file in a pull request, with its unified-diff patch when GitHub provides one.
    struct PRFile: Decodable, Hashable, Sendable {
        let filename: String
        let additions: Int
        let deletions: Int
        let patch: String?
    }

    struct Issue: Decodable, Identifiable, Hashable, Sendable {
        let number: Int
        let title: String
        let body: String?
        let user: User
        let labels: [Label]
        let comments: Int
        let htmlURL: URL
        let createdAt: Date
        /// Present when this "issue" is actually a pull request.
        let pullRequest: [String: String?]?

        var id: Int { number }

        enum CodingKeys: String, CodingKey {
            case number, title, body, user, labels, comments
            case htmlURL = "html_url", createdAt = "created_at", pullRequest = "pull_request"
        }
    }

    struct RepoInfo: Decodable, Sendable {
        let defaultBranch: String
        enum CodingKeys: String, CodingKey { case defaultBranch = "default_branch" }
    }

    func info() async throws -> RepoInfo { try await api.send("GET", base, body: Optional<[String: String]>.none) }

    func pullRequests() async throws -> PagedList<PullRequest> {
        try await PagedList.load { page in
            try await api.send("GET", base + "/pulls?state=open&per_page=\(PagedList<PullRequest>.pageSize)&page=\(page)&sort=updated&direction=desc",
                               body: Optional<[String: String]>.none)
        }
    }

    func createPullRequest(title: String, body: String, head: String, base baseBranch: String, draft: Bool) async throws -> PullRequest {
        struct Payload: Encodable { let title, body, head, base: String; let draft: Bool }
        return try await api.send("POST", base + "/pulls",
                                  body: Payload(title: title, body: body, head: head, base: baseBranch, draft: draft))
    }

    func issues() async throws -> PagedList<Issue> {
        let all: PagedList<Issue> = try await .load { page in
            try await api.send("GET", base + "/issues?state=open&per_page=\(PagedList<Issue>.pageSize)&page=\(page)&sort=updated",
                               body: Optional<[String: String]>.none)
        }
        // GitHub counts pull requests as issues.
        return PagedList(items: all.items.filter { $0.pullRequest == nil }, isComplete: all.isComplete)
    }

    func createIssue(title: String, body: String) async throws -> Issue {
        try await api.send("POST", base + "/issues", body: ["title": title, "body": body])
    }

    /// The first 100 changed files of a pull request (plenty for triage comparisons).
    func files(for number: Int) async throws -> [PRFile] {
        try await api.send("GET", base + "/pulls/\(number)/files?per_page=100", body: Optional<[String: String]>.none)
    }

    func closePullRequest(_ number: Int) async throws {
        struct Closed: Decodable { let state: String }
        let _: Closed = try await api.send("PATCH", base + "/pulls/\(number)", body: ["state": "closed"])
    }

    func comment(on number: Int, body: String) async throws {
        struct Posted: Decodable { let id: Int }
        let _: Posted = try await api.send("POST", base + "/issues/\(number)/comments", body: ["body": body])
    }

    // MARK: Checks

    private struct CheckRuns: Decodable {
        struct Run: Decodable {
            let name: String
            let status: String
            let conclusion: String?
            let htmlURL: URL?
            enum CodingKeys: String, CodingKey { case name, status, conclusion, htmlURL = "html_url" }
        }
        let checkRuns: [Run]
        enum CodingKeys: String, CodingKey { case checkRuns = "check_runs" }
    }

    private struct CombinedStatus: Decodable {
        struct Status: Decodable {
            let context: String
            let state: String
            let targetURL: URL?
            enum CodingKeys: String, CodingKey { case context, state, targetURL = "target_url" }
        }
        let statuses: [Status]
    }

    /// Check runs (Actions etc.) and legacy commit statuses for `ref`, merged into one summary.
    func checks(for ref: String) async throws -> CheckSummary {
        let escaped = ref.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ref
        async let runs: CheckRuns = api.send("GET", base + "/commits/\(escaped)/check-runs?per_page=100",
                                             body: Optional<[String: String]>.none)
        async let statuses: CombinedStatus = api.send("GET", base + "/commits/\(escaped)/status",
                                                      body: Optional<[String: String]>.none)
        var items: [CheckSummary.Item] = []
        for run in (try? await runs)?.checkRuns ?? [] {
            let state: CheckSummary.State = switch (run.status, run.conclusion) {
            case ("completed", "success"?), ("completed", "neutral"?), ("completed", "skipped"?): .success
            case ("completed", _): .failure
            default: .pending
            }
            items.append(.init(name: run.name, state: state, url: run.htmlURL))
        }
        for status in (try? await statuses)?.statuses ?? [] {
            let state: CheckSummary.State = switch status.state {
            case "success": .success
            case "pending": .pending
            default: .failure
            }
            items.append(.init(name: status.context, state: state, url: status.targetURL))
        }
        return CheckSummary(items: items)
    }
}

struct CheckSummary: Hashable, Sendable {
    enum State: Hashable, Sendable { case success, failure, pending, none }

    struct Item: Hashable, Sendable {
        let name: String
        let state: State
        let url: URL?
    }

    var items: [Item] = []

    var state: State {
        if items.isEmpty { return .none }
        if items.contains(where: { $0.state == .failure }) { return .failure }
        if items.contains(where: { $0.state == .pending }) { return .pending }
        return .success
    }

    var description: String {
        let passed = items.filter { $0.state == .success }.count
        let failed = items.filter { $0.state == .failure }.count
        let pending = items.filter { $0.state == .pending }.count
        return [failed > 0 ? "\(failed) failing" : nil, pending > 0 ? "\(pending) pending" : nil,
                passed > 0 ? "\(passed) passed" : nil].compactMap { $0 }.joined(separator: ", ")
    }
}

/// A GitHub list read a page at a time, up to a cap that keeps huge repositories quick.
struct PagedList<Item: Sendable>: Sendable {
    static var pageSize: Int { 100 }
    static var maxPages: Int { 5 }
    static var maxItems: Int { pageSize * maxPages }

    var items: [Item]
    var isComplete: Bool

    static func load(_ fetch: @Sendable (Int) async throws -> [Item]) async throws -> PagedList {
        var items: [Item] = []
        for page in 1...maxPages {
            let batch = try await fetch(page)
            items += batch
            if batch.count < pageSize { return PagedList(items: items, isComplete: true) }
        }
        return PagedList(items: items, isComplete: false)
    }
}
