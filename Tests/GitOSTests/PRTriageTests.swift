import Foundation
import Testing
@testable import GitOS

@Suite struct PRTriageTests {
    private func file(_ name: String, patch: String?, additions: Int = 1, deletions: Int = 1) -> GitHubRepoAPI.PRFile {
        .init(filename: name, additions: additions, deletions: deletions, patch: patch)
    }

    private func pr(number: Int = 1, body: String? = nil, association: String? = nil,
                    draft: Bool? = false) throws -> GitHubRepoAPI.PullRequest {
        let json = """
        {"number": \(number), "title": "t", "body": \(body.map { "\"\($0)\"" } ?? "null"),
         "user": {"login": "u", "avatar_url": null},
         "head": {"ref": "h", "sha": "a", "repo": null}, "base": {"ref": "main", "sha": "b", "repo": null},
         "draft": \(draft == true), "html_url": "https://github.com/x/y/pull/\(number)",
         "created_at": "2026-01-01T00:00:00Z", "updated_at": "2026-01-01T00:00:00Z", "labels": [],
         "author_association": \(association.map { "\"\($0)\"" } ?? "null")}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(GitHubRepoAPI.PullRequest.self, from: Data(json.utf8))
    }

    @Test func sameFixAtDifferentLineNumbersClustersTogether() {
        // Two PRs fix the same typo; hunk headers and context differ, content matches.
        let a = PRTriage.signature(of: [file("README.md", patch: "@@ -10,3 +10,3 @@\n context\n-teh app\n+the app")])
        let b = PRTriage.signature(of: [file("README.md", patch: "@@ -42,2 +42,2 @@\n-teh app\n+the app\n other context")])
        let c = PRTriage.signature(of: [file("Sources/App.swift", patch: "@@ -1 +1 @@\n-let x = 1\n+let x = 2")])
        let clusters = PRTriage.clusters(of: [(7, a), (3, b), (9, c)])
        #expect(clusters == [[3, 7]])
    }

    @Test func whitespaceOnlyDifferencesStillMatch() {
        let a = PRTriage.signature(of: [file("a.js", patch: "+const x = 1;\n-const x=1;")])
        let b = PRTriage.signature(of: [file("a.js", patch: "+  const x = 1;  \n-  const x=1;")])
        #expect(PRTriage.similarity(a, b) == 1)
    }

    @Test func fileHeadersAndContextLinesAreIgnored() {
        let sig = PRTriage.signature(of: [file("a.txt", patch: "--- a/a.txt\n+++ b/a.txt\n@@ -1 +1 @@\n unchanged\n+new line")])
        #expect(sig == ["a.txt+new line"])
    }

    @Test func emptySignaturesNeverCluster() {
        let clusters = PRTriage.clusters(of: [(1, []), (2, []), (3, ["a.txt+x"])])
        #expect(clusters.isEmpty)
    }

    @Test func issueReferenceDetection() {
        #expect(PRTriage.referencesIssue("Fixes #210"))
        #expect(PRTriage.referencesIssue("See https://github.com/Dhunu/gitOS/issues/12 for context"))
        #expect(!PRTriage.referencesIssue("improves performance"))
        #expect(!PRTriage.referencesIssue(nil))
        #expect(!PRTriage.referencesIssue(""))
    }

    @Test func maintainerWithPassingCIAndLinkedIssueOutscoresDriveBy() throws {
        let good = PRTriage.score(
            pr: try pr(body: "Fixes #210. The refresher raced with wake; this serializes it and adds a test.",
                       association: "CONTRIBUTOR"),
            checks: CheckSummary(items: [.init(name: "ci", state: .success, url: nil)]),
            files: [file("a.swift", patch: "+x", additions: 20, deletions: 5)])
        let spam = PRTriage.score(
            pr: try pr(body: "", association: "NONE"),
            checks: CheckSummary(items: [.init(name: "ci", state: .failure, url: nil)]),
            files: [file("a.swift", patch: "+x", additions: 400, deletions: 200)])
        #expect(good.total > spam.total + 30)
        #expect(!good.flagged)
        #expect(spam.flagged)
    }

    @Test func hugeDiffWithThinDescriptionIsFlagged() throws {
        let score = PRTriage.score(pr: try pr(body: "Fixes #1", association: "NONE"),
                                   checks: nil,
                                   files: [file("a.swift", patch: "+x", additions: 500, deletions: 100)])
        #expect(score.flagged)
        #expect(score.reasons.contains { $0.contains("thin description") })
    }

    @Test func scoresStayWithinBounds() throws {
        let top = PRTriage.score(
            pr: try pr(body: String(repeating: "Fixes #1 well. ", count: 20), association: "OWNER"),
            checks: CheckSummary(items: [.init(name: "ci", state: .success, url: nil)]),
            files: [file("a.swift", patch: "+x")])
        let bottom = PRTriage.score(pr: try pr(body: "", association: nil, draft: true),
                                    checks: CheckSummary(items: [.init(name: "ci", state: .failure, url: nil)]),
                                    files: [file("a.swift", patch: "+x", additions: 900, deletions: 0)])
        #expect(top.total <= 100)
        #expect(bottom.total >= 0)
    }

    @Test func closeTemplatesNameTheKeptPR() {
        #expect(PRTriage.closeTemplate(keeping: 482).contains("#482"))
        #expect(!PRTriage.closeTemplate(keeping: nil).contains("#"))
    }
}
