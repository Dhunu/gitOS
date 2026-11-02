import Foundation
import Testing
@testable import GitOS

struct ConflictTests {
    static let diff3 = """
    keep 1
    <<<<<<< HEAD
    ours line
    ||||||| base
    base line
    =======
    theirs line
    theirs line 2
    >>>>>>> feature
    keep 2
    <<<<<<< HEAD
    =======
    added by them
    >>>>>>> feature
    tail

    """

    @Test func parsesDiff3Conflicts() {
        let doc = ConflictDocument.parse(Self.diff3)
        #expect(doc.conflicts.count == 2)
        let first = doc.conflicts[0]
        #expect(first.oursLabel == "HEAD" && first.theirsLabel == "feature")
        #expect(first.ours == "ours line\n")
        #expect(first.base == "base line\n")
        #expect(first.theirs == "theirs line\ntheirs line 2\n")
        #expect(doc.conflicts[1].ours.isEmpty)
    }

    @Test func rendersResolutionsAndKeepsUnresolvedMarkers() {
        let doc = ConflictDocument.parse(Self.diff3)
        let ids = doc.conflicts.map(\.id)
        let resolved = doc.render([ids[0]: .theirs, ids[1]: .custom("custom\n")])
        #expect(resolved == "keep 1\ntheirs line\ntheirs line 2\nkeep 2\ncustom\ntail\n")
        let partial = doc.render([ids[0]: .oursThenTheirs])
        #expect(partial.contains("ours line\ntheirs line\n"))
        #expect(partial.contains("<<<<<<< HEAD\n=======\nadded by them\n>>>>>>> feature\n"))
    }

    @Test func roundTripsCRLFAndIgnoresLookalikes() {
        let text = "a\r\n<<<<<<< ours\r\nx\r\n=======\r\ny\r\n>>>>>>> theirs\r\nb\r\n====== not a marker\r\n"
        let doc = ConflictDocument.parse(text)
        #expect(doc.conflicts.count == 1)
        #expect(doc.render([doc.conflicts[0].id: .ours]) == "a\r\nx\r\nb\r\n====== not a marker\r\n")
    }

    @Test func realMergeConflictResolvesThroughEditorPath() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gitos-conflict-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let repo = GitRepository(url: dir)
        let me = GitContext(authorName: "T", authorEmail: "t@e.com")
        try await Git.run(["init", "-q", "-b", "main"], in: dir)
        let file = dir.appendingPathComponent("x.txt")
        try "start\n".write(to: file, atomically: true, encoding: .utf8)
        try await repo.stage(["x.txt"]); try await repo.commit(message: "start", context: me)
        try await repo.createBranch("feature")
        try "feature\n".write(to: file, atomically: true, encoding: .utf8)
        try await repo.stage(["x.txt"]); try await repo.commit(message: "feature", context: me)
        try await repo.switchBranch("main")
        try "main\n".write(to: file, atomically: true, encoding: .utf8)
        try await repo.stage(["x.txt"]); try await repo.commit(message: "main", context: me)

        await #expect(throws: GitFailure.self) { try await repo.merge("feature", context: me) }
        #expect(await repo.operationInProgress() == .merge)

        let doc = ConflictDocument.parse(try String(contentsOf: file, encoding: .utf8))
        #expect(doc.conflicts.count == 1)
        try doc.render([doc.conflicts[0].id: .theirsThenOurs]).write(to: file, atomically: true, encoding: .utf8)
        try await repo.markResolved("x.txt")
        try await repo.continueOperation(.merge, context: me)

        #expect(await repo.operationInProgress() == nil)
        #expect(try String(contentsOf: file, encoding: .utf8) == "feature\nmain\n")
        #expect(try await repo.log().first?.parents.count == 2)
    }
}
