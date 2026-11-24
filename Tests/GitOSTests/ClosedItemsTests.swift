import Foundation
import Testing
@testable import GitOS

struct ClosedItemsTests {
    func pr(state: String, merged: String? = nil, closed: String? = nil, draft: Bool = false) throws -> GitHubRepoAPI.PullRequest {
        let json = """
        {"number": 7, "title": "T", "body": null, "draft": \(draft), "state": "\(state)",
         "merged_at": \(merged.map { "\"\($0)\"" } ?? "null"), "closed_at": \(closed.map { "\"\($0)\"" } ?? "null"),
         "user": {"login": "ada", "avatar_url": null},
         "head": {"ref": "f", "sha": "a", "repo": null}, "base": {"ref": "main", "sha": "b", "repo": null},
         "html_url": "https://github.com/o/r/pull/7",
         "created_at": "2026-10-01T10:00:00Z", "updated_at": "2026-10-02T10:00:00Z", "labels": []}
        """
        return try GitHubAPI.decoder.decode(GitHubRepoAPI.PullRequest.self, from: Data(json.utf8))
    }

    @Test func pullRequestStates() throws {
        #expect(PullRequestState(try pr(state: "open")) == .open)
        #expect(PullRequestState(try pr(state: "open", draft: true)) == .draft)
        let merged = try pr(state: "closed", merged: "2026-10-03T10:00:00Z", closed: "2026-10-03T10:00:00Z")
        #expect(PullRequestState(merged) == .merged && !merged.isOpen && merged.mergedAt != nil)
        #expect(PullRequestState(try pr(state: "closed", closed: "2026-10-03T10:00:00Z")) == .closed)
    }

    @Test func pullRequestsWithoutStateStillDecode() throws {
        // Older cached shapes and some endpoints omit state; treat them as open.
        let json = """
        {"number": 1, "title": "T", "body": null, "user": {"login": "a", "avatar_url": null},
         "head": {"ref": "f", "sha": "a", "repo": null}, "base": {"ref": "m", "sha": "b", "repo": null},
         "html_url": "https://github.com/o/r/pull/1", "created_at": "2026-10-01T10:00:00Z",
         "updated_at": "2026-10-01T10:00:00Z", "labels": []}
        """
        let decoded = try GitHubAPI.decoder.decode(GitHubRepoAPI.PullRequest.self, from: Data(json.utf8))
        #expect(decoded.isOpen && !decoded.isMerged)
    }

    @Test func decodesComments() throws {
        let json = """
        [{"id": 9, "body": "Looks good", "user": {"login": "grace", "avatar_url": null},
          "created_at": "2026-10-04T10:00:00Z", "html_url": "https://github.com/o/r/issues/7#issuecomment-9"}]
        """
        let comments = try GitHubAPI.decoder.decode([GitHubRepoAPI.Comment].self, from: Data(json.utf8))
        #expect(comments.first?.user.login == "grace" && comments.first?.body == "Looks good")
    }
}

struct ClosedIssueTests {
    func issue(_ extra: String) throws -> GitHubRepoAPI.Issue {
        let json = """
        {"number": 3, "title": "Bug", "body": "x", "user": {"login": "ada", "avatar_url": null}, "labels": [],
         "comments": 1, "html_url": "https://github.com/o/r/issues/3", "created_at": "2026-10-01T10:00:00Z"\(extra)}
        """
        return try GitHubAPI.decoder.decode(GitHubRepoAPI.Issue.self, from: Data(json.utf8))
    }

    @Test func issueStates() throws {
        #expect(IssueState(try issue("")) == .open)
        #expect(IssueState(try issue(#", "state": "open""#)) == .open)
        let done = try issue(#", "state": "closed", "state_reason": "completed", "closed_at": "2026-10-05T10:00:00Z""#)
        #expect(IssueState(done) == .completed && done.closedAt != nil)
        #expect(IssueState(try issue(#", "state": "closed", "state_reason": "not_planned""#)) == .notPlanned)
    }

    @Test func decodesAssigneesAndMilestone() throws {
        let decoded = try issue(#", "assignees": [{"login": "grace", "avatar_url": null}], "milestone": {"title": "1.0", "number": 2}"#)
        #expect(decoded.assignees?.first?.login == "grace")
        #expect(decoded.milestone?.title == "1.0")
    }
}
