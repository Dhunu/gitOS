import Foundation
import Testing
@testable import GitOS

struct FilePreviewTests {
    @Test func detectsKinds() {
        #expect(PreviewKind.detect(path: "a/logo.PNG") == .image)
        #expect(PreviewKind.detect(path: "demo.mov") == .video)
        #expect(PreviewKind.detect(path: "package.json") == .json)
        #expect(PreviewKind.detect(path: "main.swift") == nil)
        #expect(PreviewKind.image.prefersPreview && !PreviewKind.json.prefersPreview)
    }

    @Test func prettyPrintsWithoutReorderingKeys() {
        let text = #"{"z":1,"a":[true,null,"x"],"e":{},"s":"a:b, {c}"}"#
        #expect(JSONFormatter.pretty(text) == """
        {
          "z": 1,
          "a": [
            true,
            null,
            "x"
          ],
          "e": {},
          "s": "a:b, {c}"
        }
        """)
    }

    @Test func classifiesTokens() {
        let kinds = JSONFormatter.tokens(#"{"k": "v", "n": -1.5e3, "b": false}"#)
            .filter { $0.1 != .whitespace && $0.1 != .punctuation }
        #expect(kinds.map(\.1) == [.key, .string, .key, .number, .key, .literal])
    }

    @Test func handlesEscapedQuotesAndComments() {
        let text = "{\n  // note\n  \"q\": \"say \\\"hi\\\"\" /* end */\n}"
        #expect(JSONFormatter.pretty(text) == "{\n  \"q\": \"say \\\"hi\\\"\"\n}")
        #expect(JSONFormatter.isValid(Data(text.utf8)))
        #expect(!JSONFormatter.isValid(Data("{oops".utf8)))
    }
}

extension GitRepositoryTests {
    @Test func loadsBothSidesOfChanges() async throws {
        try "{\"v\":1}".write(to: repo.url.appendingPathComponent("p.json"), atomically: true, encoding: .utf8)
        try await repo.stage(["p.json"])
        try await repo.commit(message: "Add", context: identity)
        try "{\"v\":2}".write(to: repo.url.appendingPathComponent("p.json"), atomically: true, encoding: .utf8)

        let unstaged = FileChange(path: "p.json", originalPath: nil, kind: .modified, area: .unstaged)
        let working = await repo.versions(for: unstaged)
        #expect(working.before == Data("{\"v\":1}".utf8) && working.after == Data("{\"v\":2}".utf8))

        try await repo.stage(["p.json"])
        let staged = await repo.versions(for: FileChange(path: "p.json", originalPath: nil, kind: .modified, area: .staged))
        #expect(staged.before == Data("{\"v\":1}".utf8) && staged.after == Data("{\"v\":2}".utf8))

        try await repo.commit(message: "Bump", context: identity)
        let sha = try await Git.run(["rev-parse", "HEAD"], in: repo.url).trimmingCharacters(in: .whitespacesAndNewlines)
        let diff = try #require(try await repo.show(sha).first)
        let inCommit = await repo.versions(commit: sha, diff: diff)
        #expect(inCommit.before == Data("{\"v\":1}".utf8) && inCommit.after == Data("{\"v\":2}".utf8))

        let added = await repo.versions(for: FileChange(path: "new.png", originalPath: nil, kind: .untracked, area: .unstaged))
        #expect(added.before == nil)
    }
}
