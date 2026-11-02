import Foundation
import Testing
@testable import GitOS

struct RebaseTests {
    let repo: GitRepository
    let identity = GitContext(authorName: "Test", authorEmail: "test@example.com")

    init() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gitos-rebase-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try await Git.run(["init", "-q", "-b", "main"], in: dir)
        repo = GitRepository(url: dir)
    }

    private func commit(_ file: String, _ text: String, _ message: String) async throws {
        try text.write(to: repo.url.appendingPathComponent(file), atomically: true, encoding: .utf8)
        try await repo.stage([file])
        try await repo.commit(message: message, context: identity)
    }

    @Test func rewordSquashFixupDropAndReorder() async throws {
        try await commit("base.txt", "base\n", "Base")
        try await commit("a.txt", "a\n", "Add a")
        try await commit("b.txt", "b\n", "Add b")
        try await commit("a.txt", "a2\n", "Tweak a")
        try await commit("c.txt", "c\n", "Add c")
        try await commit("d.txt", "d\n", "Add d")

        let log = try await repo.log()
        let bySubject = Dictionary(uniqueKeysWithValues: log.map { ($0.subject, $0.sha) })
        let base = try #require(bySubject["Base"])
        // Oldest first: move "Add c" first and reword it, fixup "Tweak a" into "Add a",
        // squash "Add d" into "Add b", drop nothing else.
        let steps = [
            RebaseStep(sha: bySubject["Add c"]!, subject: "Add c", action: .reword, message: "Add c, reworded\n\nWith a body."),
            RebaseStep(sha: bySubject["Add a"]!, subject: "Add a"),
            RebaseStep(sha: bySubject["Tweak a"]!, subject: "Tweak a", action: .fixup),
            RebaseStep(sha: bySubject["Add b"]!, subject: "Add b"),
            RebaseStep(sha: bySubject["Add d"]!, subject: "Add d", action: .squash),
        ]
        try await repo.interactiveRebase(base: base, steps: steps, context: identity)

        let after = try await repo.log()
        #expect(after.map(\.subject) == ["Add b", "Add a", "Add c, reworded", "Base"])
        #expect(try await repo.fullMessage(of: after[2].sha) == "Add c, reworded\n\nWith a body.")
        let squashed = try await repo.fullMessage(of: after[0].sha)
        #expect(squashed.contains("Add b") && squashed.contains("Add d"))
        let a = try String(contentsOf: repo.url.appendingPathComponent("a.txt"), encoding: .utf8)
        #expect(a == "a2\n")
        #expect(await repo.operationInProgress() == nil)
    }

    @Test func dropAndConflictStopsThenAborts() async throws {
        try await commit("f.txt", "1\n", "One")
        try await commit("f.txt", "2\n", "Two")
        try await commit("f.txt", "3\n", "Three")
        let log = try await repo.log()
        // Dropping "Two" makes "Three" conflict (it expects 2 as the base text).
        let steps = [
            RebaseStep(sha: log[1].sha, subject: "Two", action: .drop),
            RebaseStep(sha: log[0].sha, subject: "Three"),
        ]
        await #expect(throws: GitFailure.self) {
            try await repo.interactiveRebase(base: log[2].sha, steps: steps, context: identity)
        }
        guard case .rebase = await repo.operationInProgress() else {
            Issue.record("expected a rebase in progress"); return
        }
        #expect(try await repo.status().conflicted.map(\.path) == ["f.txt"])
        try await repo.abortOperation(.rebase(step: nil, total: nil))
        #expect(await repo.operationInProgress() == nil)
        #expect(try await repo.log().count == 3)
    }

    @Test func rejectsLeadingSquash() {
        let steps = [RebaseStep(sha: "a", subject: "a", action: .squash), RebaseStep(sha: "b", subject: "b")]
        #expect(RebaseTodo.validate(steps) != nil)
        #expect(RebaseTodo.validate([RebaseStep(sha: "a", subject: "a", action: .drop),
                                     RebaseStep(sha: "b", subject: "b", action: .fixup)]) != nil)
    }
}
