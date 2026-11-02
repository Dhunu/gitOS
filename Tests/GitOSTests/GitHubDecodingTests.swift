import Foundation
import Testing
@testable import GitOS

struct GitHubDecodingTests {
    @Test func decodesPullRequestAndIssue() throws {
        let pr = """
        {"number": 42, "title": "Add thing", "body": null, "draft": false,
         "user": {"login": "ada", "avatar_url": "https://avatars.githubusercontent.com/u/1?v=4", "id": 1},
         "head": {"ref": "feature/x", "sha": "abc", "repo": {"full_name": "ada/repo"}},
         "base": {"ref": "main", "sha": "def", "repo": {"full_name": "org/repo"}},
         "html_url": "https://github.com/org/repo/pull/42",
         "created_at": "2026-10-01T10:00:00Z", "updated_at": "2026-10-02T10:00:00Z",
         "labels": [{"name": "bug", "color": "d73a4a", "id": 3}]}
        """
        let decoded = try GitHubAPI.decoder.decode(GitHubRepoAPI.PullRequest.self, from: Data(pr.utf8))
        #expect(decoded.number == 42 && decoded.head.ref == "feature/x" && decoded.labels.first?.name == "bug")
        #expect(decoded.head.repo?.fullName != decoded.base.repo?.fullName)

        let issues = """
        [{"number": 7, "title": "Bug", "body": "x", "user": {"login": "b", "avatar_url": null}, "labels": [],
          "comments": 2, "html_url": "https://github.com/org/repo/issues/7", "created_at": "2026-10-01T10:00:00Z"},
         {"number": 8, "title": "PR", "body": null, "user": {"login": "b", "avatar_url": null}, "labels": [],
          "comments": 0, "html_url": "https://github.com/org/repo/pull/8", "created_at": "2026-10-01T10:00:00Z",
          "pull_request": {"url": "https://api.github.com/x", "merged_at": null}}]
        """
        let decodedIssues = try GitHubAPI.decoder.decode([GitHubRepoAPI.Issue].self, from: Data(issues.utf8))
        #expect(decodedIssues.filter { $0.pullRequest == nil }.map(\.number) == [7])
    }

    @Test func checkSummaryState() {
        typealias Item = CheckSummary.Item
        #expect(CheckSummary(items: []).state == .none)
        #expect(CheckSummary(items: [Item(name: "a", state: .success, url: nil), Item(name: "b", state: .pending, url: nil)]).state == .pending)
        let failing = CheckSummary(items: [Item(name: "a", state: .failure, url: nil), Item(name: "b", state: .success, url: nil)])
        #expect(failing.state == .failure)
        #expect(failing.description == "1 failing, 1 passed")
    }

    @Test func splitsClaudeTitleAndBody() {
        let (title, body) = Claude.splitTitle("**Add retry to fetch**\n\nRetries transient errors.\n")
        #expect(title == "Add retry to fetch")
        #expect(body == "Retries transient errors.")
    }
}
