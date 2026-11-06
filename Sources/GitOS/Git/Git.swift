import Foundation

/// Per-invocation settings derived from the account that owns a repository.
/// Everything is passed as `-c` flags / env vars, so global git config and the
/// system keychain are never modified.
struct GitContext: Sendable {
    var authorName: String?
    var authorEmail: String?
    var signing: SigningConfig?
    var githubUser: String?
    var githubToken: String?

    static let none = GitContext()

    /// Credential helper that answers with the account token passed through the environment.
    /// It drains stdin so git never sees a broken pipe.
    private static let credentialHelper =
        #"!f() { cat >/dev/null; test "$1" = get && printf 'username=%s\npassword=%s\n' "$GITOS_GH_USER" "$GITOS_GH_TOKEN"; }; f"#

    var configArgs: [String] {
        var args: [String] = []
        if let authorName, !authorName.isEmpty { args += ["-c", "user.name=\(authorName)"] }
        if let authorEmail, !authorEmail.isEmpty { args += ["-c", "user.email=\(authorEmail)"] }
        if let signing, !signing.key.isEmpty {
            args += ["-c", "gpg.format=\(signing.format.rawValue)",
                     "-c", "user.signingkey=\(signing.key)",
                     "-c", "commit.gpgsign=true",
                     "-c", "tag.gpgsign=true"]
        }
        if githubToken != nil {
            // An empty value resets the helper list for github.com URLs only,
            // so osxkeychain can't hand over another account's credentials.
            args += ["-c", "credential.https://github.com.helper=",
                     "-c", "credential.https://github.com.helper=\(Self.credentialHelper)",
                     "-c", "url.https://github.com/.insteadOf=git@github.com:",
                     "-c", "url.https://github.com/.insteadOf=ssh://git@github.com/"]
        }
        return args
    }

    var environment: [String: String] {
        guard let githubToken else { return [:] }
        return ["GITOS_GH_USER": githubUser ?? "x-access-token", "GITOS_GH_TOKEN": githubToken]
    }
}

struct GitFailure: LocalizedError, Sendable {
    let command: String
    let message: String
    let exitCode: Int32

    var errorDescription: String? {
        message.isEmpty ? "git \(command) failed with exit code \(exitCode)" : message
    }

    /// GitHub turned the account away from this repository. It answers "not found" for private
    /// repositories an app or account can't see, even when the account itself is a member.
    var isAccessDenied: Bool {
        message.contains("Repository not found") || message.contains("denied to")
            || message.contains("The requested URL returned error: 403")
    }

    /// What to try when GitHub turns `login` away from a repository owned by `owner`.
    func accountHint(login: String, owner: String?) -> String? {
        guard isAccessDenied else { return nil }
        let problem = message.contains("Repository not found")
            ? "GitHub can't find this repository for @\(login)."
            : "GitHub won't let @\(login) do this on this repository."
        let switchAccount = "switch account in the toolbar or add a folder rule in Settings."
        guard let owner, owner.caseInsensitiveCompare(login) != .orderedSame else {
            return "\(problem) If it belongs to another account, \(switchAccount)"
        }
        return "\(problem) If @\(login) has access, the “\(owner)” organization may need to approve GitOS, or you can add this account with an access token. Otherwise, \(switchAccount)"
    }

    /// GitHub refused the credentials, as opposed to a network or permissions problem.
    var isRejectedCredential: Bool {
        message.contains("Invalid username or token") || message.contains("Authentication failed for")
    }
}

enum Git {
    static let executable: String = {
        let candidates = ["/opt/homebrew/bin/git", "/usr/local/bin/git", "/usr/bin/git"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/usr/bin/git"
    }()

    private static let baseEnvironment: [String: String] = {
        var env = ProcessInfo.processInfo.environment
        let path = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + path
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["LANG"] = "en_US.UTF-8"
        env.removeValue(forKey: "GIT_DIR")
        env.removeValue(forKey: "GIT_WORK_TREE")
        return env
    }()

    @discardableResult
    static func run(
        _ args: [String],
        in directory: URL,
        context: GitContext = .none,
        input: Data? = nil,
        environment: [String: String] = [:],
        allowedExitCodes: Set<Int32> = [0]
    ) async throws -> String {
        let data = try await runData(args, in: directory, context: context, input: input,
                                     environment: environment, allowedExitCodes: allowedExitCodes)
        return String(decoding: data, as: UTF8.self)
    }

    static func runData(
        _ args: [String],
        in directory: URL,
        context: GitContext = .none,
        input: Data? = nil,
        environment: [String: String] = [:],
        allowedExitCodes: Set<Int32> = [0]
    ) async throws -> Data {
        let fullArgs = ["-c", "core.quotepath=false", "-c", "color.ui=false"] + context.configArgs + args
        let env = baseEnvironment.merging(context.environment) { $1 }.merging(environment) { $1 }
        let commandName = args.first ?? ""

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = fullArgs
                process.currentDirectoryURL = directory
                process.environment = env

                let stdout = Pipe(), stderr = Pipe(), stdin = Pipe()
                process.standardOutput = stdout
                process.standardError = stderr
                process.standardInput = stdin

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                let group = DispatchGroup()
                let errBox = DataBox()
                group.enter()
                DispatchQueue.global().async {
                    errBox.data = stderr.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                group.enter()
                DispatchQueue.global().async {
                    if let input { try? stdin.fileHandleForWriting.write(contentsOf: input) }
                    try? stdin.fileHandleForWriting.close()
                    group.leave()
                }
                let outData = stdout.fileHandleForReading.readDataToEndOfFile()
                group.wait()
                process.waitUntilExit()

                if allowedExitCodes.contains(process.terminationStatus) {
                    continuation.resume(returning: outData)
                } else {
                    // Some commands (rebase, merge) explain conflicts on stdout rather than stderr.
                    var message = String(decoding: errBox.data, as: UTF8.self)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if message.isEmpty {
                        message = String(decoding: outData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    continuation.resume(throwing: GitFailure(
                        command: commandName, message: message, exitCode: process.terminationStatus))
                }
            }
        }
    }
}

final class DataBox: @unchecked Sendable {
    var data = Data()
}
