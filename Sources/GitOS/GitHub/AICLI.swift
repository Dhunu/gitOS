import Foundation

/// Where AI text comes from: a CLI the user is already signed in to, or an Anthropic API key.
enum AIProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case claudeCode, codex, apiKey

    var id: String { rawValue }

    var name: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .apiKey: "Anthropic API key"
        }
    }

    var command: String? {
        switch self {
        case .claudeCode: "claude"
        case .codex: "codex"
        case .apiKey: nil
        }
    }

    var installURL: URL? {
        switch self {
        case .claudeCode: URL(string: "https://claude.com/product/claude-code")
        case .codex: URL(string: "https://developers.openai.com/codex/cli")
        case .apiKey: nil
        }
    }

    /// A CLI's install and sign-in are checked when it runs, so its errors can say what to do.
    var isReady: Bool { self != .apiKey || Claude.apiKey != nil }
}

/// Runs the `claude` or `codex` command headlessly, so requests use the user's existing sign-in.
enum AICLI {
    private static let pathMarker = "__GITOS_PATH__"
    private static let timeout: TimeInterval = 300

    /// Apps opened from Finder get a minimal PATH, so ask the login shell (rc files add nvm and friends).
    private static let searchPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let common = ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "\(home)/.bun/bin",
                      "\(home)/.npm-global/bin", "\(home)/.volta/bin", "/usr/bin", "/bin"]
        let inherited = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        var seen = Set<String>()
        return (loginShellPath() + common + inherited).filter { seen.insert($0).inserted }.joined(separator: ":")
    }()

    private static func loginShellPath() -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh")
        process.arguments = ["-ilc", "printf '\\n\(pathMarker)%s\\n' \"$PATH\""]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [] }

        let box = DataBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            box.data = stdout.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        guard group.wait(timeout: .now() + 10) == .success else {
            process.terminate()
            return []
        }
        return parsePath(fromShellOutput: String(decoding: box.data, as: UTF8.self))
    }

    /// Shell startup can print anything (banners, fetch tools), so only the marked line counts.
    static func parsePath(fromShellOutput output: String) -> [String] {
        guard let line = output.components(separatedBy: "\n").last(where: { $0.hasPrefix(pathMarker) }) else { return [] }
        return line.dropFirst(pathMarker.count).split(separator: ":").map(String.init)
    }

    /// Blocks while reading the shell's PATH the first time, so call it off the main actor.
    static func executable(for provider: AIProvider) -> String? {
        guard let command = provider.command else { return nil }
        return searchPath.split(separator: ":")
            .map { "\($0)/\(command)" }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func arguments(for provider: AIProvider, system: String, model: String, outputFile: String) -> [String] {
        switch provider {
        case .claudeCode:
            ["-p", "--model", model, "--effort", "low", "--tools", "", "--strict-mcp-config",
             "--no-session-persistence", "--setting-sources", "", "--system-prompt", system]
        case .codex:
            // Reads the prompt from stdin; the model comes from the user's Codex config.
            ["exec", "--skip-git-repo-check", "--ephemeral", "--sandbox", "read-only",
             "--output-last-message", outputFile, "-"]
        case .apiKey:
            []
        }
    }

    static func failureMessage(for provider: AIProvider, output: String) -> String {
        let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = text.lowercased()
        if ["not logged in", "/login", "codex login", "unauthorized", "invalid api key"].contains(where: lowered.contains) {
            return "\(provider.name) isn't signed in. Run `\(provider == .codex ? "codex login" : "claude")` in Terminal, sign in, then try again."
        }
        return text.isEmpty ? "\(provider.name) stopped without a reply." : String(text.prefix(400))
    }

    static func complete(provider: AIProvider, system: String, prompt: String, model: String) async throws -> String {
        let located = await Task.detached { executable(for: provider) }.value
        guard let located else {
            throw Claude.Failure(message: "\(provider.name) isn't installed. Install it, or pick another option in Settings › AI.")
        }
        return try await complete(provider: provider, executable: located, system: system, prompt: prompt, model: model)
    }

    static func complete(provider: AIProvider, executable: String, system: String, prompt: String,
                         model: String) async throws -> String {
        // An empty folder keeps the CLI away from the repo: the diff in the prompt is all it needs.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("GitOS-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let outputFile = directory.appendingPathComponent("reply.txt")
        let arguments = arguments(for: provider, system: system, model: model, outputFile: outputFile.path)
        let input = provider == .codex ? "\(system)\n\n\(prompt)" : prompt
        let result = try await run(executable, arguments, input: Data(input.utf8), in: directory)

        guard result.status == 0 else {
            throw Claude.Failure(message: failureMessage(for: provider, output: result.stderr.isEmpty ? result.stdout : result.stderr))
        }
        let reply = ((try? String(contentsOf: outputFile, encoding: .utf8)) ?? result.stdout)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reply.isEmpty else { throw Claude.Failure(message: failureMessage(for: provider, output: "")) }
        return reply
    }

    private static func run(_ executable: String, _ arguments: [String], input: Data,
                            in directory: URL) async throws -> (status: Int32, stdout: String, stderr: String) {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = searchPath
        // A key in the environment would take priority over the sign-in.
        environment.removeValue(forKey: "ANTHROPIC_API_KEY")
        environment.removeValue(forKey: "OPENAI_API_KEY")

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                process.currentDirectoryURL = directory
                process.environment = environment
                let stdout = Pipe(), stderr = Pipe(), stdin = Pipe()
                process.standardOutput = stdout
                process.standardError = stderr
                process.standardInput = stdin
                // The CLI can exit before reading the prompt; that must not raise SIGPIPE here.
                _ = fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }
                let timer = DispatchWorkItem { process.terminate() }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)

                let group = DispatchGroup()
                let errBox = DataBox()
                group.enter()
                DispatchQueue.global().async {
                    errBox.data = stderr.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                group.enter()
                DispatchQueue.global().async {
                    try? stdin.fileHandleForWriting.write(contentsOf: input)
                    try? stdin.fileHandleForWriting.close()
                    group.leave()
                }
                let outData = stdout.fileHandleForReading.readDataToEndOfFile()
                group.wait()
                process.waitUntilExit()
                timer.cancel()
                continuation.resume(returning: (process.terminationStatus,
                                                String(decoding: outData, as: UTF8.self),
                                                String(decoding: errBox.data, as: UTF8.self)))
            }
        }
    }
}
