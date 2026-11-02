import Foundation
import Testing
@testable import GitOS

/// Runs against real git in a throwaway repository.
struct GitRepositoryTests {
    let repo: GitRepository
    let identity = GitContext(authorName: "Test", authorEmail: "test@example.com")

    init() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gitos-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try await Git.run(["init", "-q", "-b", "main"], in: dir)
        repo = GitRepository(url: dir)
    }

    private func write(_ name: String, _ text: String) throws {
        try text.write(to: repo.url.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    @Test func stageSingleHunkThenCommit() async throws {
        let lines = (1...30).map { "line \($0)" }
        try write("file.txt", lines.joined(separator: "\n") + "\n")
        var status = try await repo.status()
        #expect(status.isUnborn)
        #expect(status.unstaged.first?.kind == .untracked)

        try await repo.stage(["file.txt"])
        try await repo.commit(message: "Initial", context: identity)

        var edited = lines
        edited[1] = "line 2 changed"
        edited[27] = "line 28 changed"
        try write("file.txt", edited.joined(separator: "\n") + "\n")

        status = try await repo.status()
        let change = try #require(status.unstaged.first)
        let diff = try #require(try await repo.diff(for: change))
        #expect(diff.hunks.count == 2)

        try await repo.apply(patch: diff.patch(for: diff.hunks[0]), cached: true, reverse: false)
        status = try await repo.status()
        #expect(status.staged.map(\.path) == ["file.txt"])
        #expect(status.unstaged.map(\.path) == ["file.txt"])

        let staged = try #require(try await repo.diff(for: status.staged[0]))
        #expect(staged.hunks.count == 1)
        #expect(staged.hunks[0].lines.contains { $0.text == "line 2 changed" })

        try await repo.commit(message: "Change line 2", context: identity)
        let log = try await repo.log()
        #expect(log.map(\.subject) == ["Change line 2", "Initial"])
        #expect(log[0].authorEmail == "test@example.com")

        // Discard the remaining hunk.
        status = try await repo.status()
        let remaining = try #require(try await repo.diff(for: status.unstaged[0]))
        try await repo.apply(patch: remaining.patch(for: remaining.hunks[0]), cached: false, reverse: true)
        status = try await repo.status()
        #expect(!status.hasChanges)
    }

    @Test func branchesAndUnpushedEmails() async throws {
        try write("a.txt", "a\n")
        try await repo.stage(["a.txt"])
        try await repo.commit(message: "A", context: identity)
        try await repo.createBranch("feature")
        let branches = try await repo.branches()
        #expect(Set(branches.map(\.name)) == ["main", "feature"])
        #expect(branches.first { $0.isCurrent }?.name == "feature")
        let emails = try await repo.unpushedAuthorEmails(hasUpstream: false)
        #expect(emails == ["test@example.com"])
    }
}
