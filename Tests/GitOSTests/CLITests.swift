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

    @Test func refreshesOnlyAnOutdatedScriptGitOSInstalled() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gitos-script-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let ours = dir.appendingPathComponent("ours").path, theirs = dir.appendingPathComponent("theirs").path
        try "#!/bin/sh\n# Opens a git repository in GitOS. Usage: gitos [path]\nexec open .\n".write(toFile: ours, atomically: true, encoding: .utf8)
        try "#!/bin/sh\necho someone else's gitos\n".write(toFile: theirs, atomically: true, encoding: .utf8)

        #expect(CLIInstaller.refreshIfOutdated(at: ours))
        #expect(try String(contentsOfFile: ours, encoding: .utf8) == CLIInstaller.script)
        #expect(!CLIInstaller.refreshIfOutdated(at: ours))  // Already current.
        #expect(!CLIInstaller.refreshIfOutdated(at: theirs))
        #expect(try String(contentsOfFile: theirs, encoding: .utf8) == "#!/bin/sh\necho someone else's gitos\n")
    }
}
