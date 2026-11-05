import Foundation
import Testing
@testable import GitOS

@Suite struct AICLITests {
    /// A stand-in CLI that records its arguments and stdin, then runs `body`.
    private func fakeCLI(_ body: String) throws -> (path: String, directory: URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("GitOSTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("cli").path
        let script = """
        #!/bin/sh
        printf '%s\\n' "$@" > '\(directory.path)/args'
        cat > '\(directory.path)/stdin'
        \(body)
        """
        try script.write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        return (path, directory)
    }

    private func recorded(_ name: String, in directory: URL) throws -> String {
        try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
    }

    @Test func claudeGetsTheDiffOnStdinWithToolsOff() async throws {
        let cli = try fakeCLI("echo 'Add downloads section'")
        let reply = try await AICLI.complete(provider: .claudeCode, executable: cli.path, system: "Be brief",
                                             prompt: "the diff", model: "claude-haiku-5-5")
        #expect(reply == "Add downloads section")
        #expect(try recorded("stdin", in: cli.directory) == "the diff")
        let args = try recorded("args", in: cli.directory).components(separatedBy: "\n")
        #expect(args.contains("-p"))
        #expect(args[args.firstIndex(of: "--tools")! + 1] == "")
        #expect(args[args.firstIndex(of: "--model")! + 1] == "claude-haiku-5-5")
        #expect(args[args.firstIndex(of: "--system-prompt")! + 1] == "Be brief")
    }

    @Test func codexPutsTheSystemPromptInStdinAndRepliesThroughItsOutputFile() async throws {
        let cli = try fakeCLI("""
        echo 'progress noise'
        while [ "$#" -gt 0 ]; do
          if [ "$1" = "--output-last-message" ]; then echo 'Fix login' > "$2"; fi
          shift
        done
        """)
        let reply = try await AICLI.complete(provider: .codex, executable: cli.path, system: "Be brief",
                                             prompt: "the diff", model: "ignored")
        #expect(reply == "Fix login")
        #expect(try recorded("stdin", in: cli.directory) == "Be brief\n\nthe diff")
        let args = try recorded("args", in: cli.directory).components(separatedBy: "\n")
        #expect(args[args.firstIndex(of: "--sandbox")! + 1] == "read-only")
        #expect(!args.contains("--model"))
    }

    @Test func aSignedOutCLIExplainsHowToSignIn() async throws {
        let cli = try fakeCLI("echo 'Not logged in · Please run /login'; exit 1")
        await #expect {
            try await AICLI.complete(provider: .claudeCode, executable: cli.path, system: "s", prompt: "p", model: "m")
        } throws: {
            $0.localizedDescription.contains("isn't signed in") && $0.localizedDescription.contains("`claude`")
        }
    }

    @Test func aCLIThatExitsWithoutReadingALargeDiffDoesNotCrash() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("GitOSTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("cli").path
        try "#!/bin/sh\necho 'boom' >&2\nexit 3\n".write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        await #expect {
            try await AICLI.complete(provider: .codex, executable: path, system: "s",
                                     prompt: String(repeating: "x", count: 500_000), model: "m")
        } throws: {
            $0.localizedDescription == "boom"
        }
    }

    @Test func pathIsReadPastShellStartupNoise() {
        let output = "fastfetch banner __GITOS_PATH__nope\nmore noise\n__GITOS_PATH__/a/bin:/b/bin\n"
        #expect(AICLI.parsePath(fromShellOutput: output) == ["/a/bin", "/b/bin"])
        #expect(AICLI.parsePath(fromShellOutput: "no marker here").isEmpty)
    }
}
