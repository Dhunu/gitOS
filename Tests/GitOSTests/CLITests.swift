import Foundation
import Testing
@testable import GitOS

@Suite("gitos command line")
@MainActor
struct CLITests {
    @Test func findsTheRepositoryAboveASubfolder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("gitos-cli-\(UUID())")
        let nested = root.appendingPathComponent("src/app")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        // A worktree's .git is a file, so a plain file has to count too.
        FileManager.default.createFile(atPath: root.appendingPathComponent(".git").path, contents: Data("gitdir: x".utf8))
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(GitOSCLI.repositoryRoot(nested.path) == root.standardizedFileURL.path)
    }

    @Test func exportsQuoteValuesForTheShell() {
        let context = GitContext(authorName: "Maya O'Neil", authorEmail: "maya@x.dev", githubToken: "tok")
        let exports = GitOSCLI.exports(context)
        #expect(exports.contains(#"export GIT_AUTHOR_NAME='Maya O'\''Neil'"#))
        #expect(exports.contains("export GIT_COMMITTER_EMAIL='maya@x.dev'"))
        #expect(exports.contains("export GH_TOKEN='tok'"))
    }

    @Test func exportsNothingWithoutAnAccount() {
        #expect(GitOSCLI.exports(.none).isEmpty)
    }
}
