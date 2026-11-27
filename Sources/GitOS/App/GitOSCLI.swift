import Foundation

/// Lets any git (a terminal, an editor, a coding agent) use the account GitOS picks for a folder.
/// `credential` is a git credential helper; `env` prints shell exports; `account` explains the choice.
@MainActor
enum GitOSCLI {
    static let commands: Set<String> = ["credential", "env", "account"]

    static func run(_ command: String, _ arguments: [String]) -> Int32 {
        let app = AppState.shared
        switch command {
        case "credential":
            return credential(app, operation: arguments.first ?? "")
        case "env":
            guard let resolved = resolve(app, path: arguments.first) else { return 0 }
            print(exports(app.gitContext(for: resolved.account)), terminator: "")
            return 0
        default:
            let root = repositoryRoot(arguments.first)
            let resolved = app.resolveAccount(for: repoRef(app, path: root))
            let who = resolved.account.map { "@\($0.login) <\($0.commitEmail)>" } ?? "no account"
            print("\(who)\n\(resolved.explanation)\n\(root)")
            return 0
        }
    }

    /// Answers `get` for https://github.com only; `store` and `erase` are no-ops, since GitOS owns the tokens.
    private static func credential(_ app: AppState, operation: String) -> Int32 {
        var fields: [String: String] = [:]
        while let line = readLine(), !line.isEmpty {
            guard let split = line.firstIndex(of: "=") else { continue }
            fields[String(line[..<split])] = String(line[line.index(after: split)...])
        }
        guard operation == "get", fields["protocol"] == "https", fields["host"] == "github.com",
              let resolved = resolve(app, path: nil) else { return 0 }
        // Refresh tokens are single-use: refreshing here could race the app and sign the account out.
        if let expiresAt = resolved.account.tokenExpiresAt, expiresAt < .now {
            FileHandle.standardError.write(Data("gitos: @\(resolved.account.login)'s token expired; open GitOS to renew it.\n".utf8))
            return 0
        }
        guard let token = app.gitContext(for: resolved.account).githubToken else { return 0 }
        print("username=\(resolved.account.login)\npassword=\(token)")
        return 0
    }

    private static func resolve(_ app: AppState, path: String?) -> (account: Account, source: ResolvedAccount.Source)? {
        let resolved = app.resolveAccount(for: repoRef(app, path: repositoryRoot(path)))
        guard let account = resolved.account else { return nil }
        return (account, resolved.source)
    }

    /// A known repository keeps its per-repo override; any other folder goes through the rules.
    private static func repoRef(_ app: AppState, path: String) -> RepoRef {
        app.repos.first { $0.path == path } ?? RepoRef(path: path)
    }

    /// The nearest folder holding `.git` (a directory, or a file in worktrees), else the folder itself.
    static func repositoryRoot(_ path: String?) -> String {
        let start = URL(fileURLWithPath: path ?? FileManager.default.currentDirectoryPath).standardizedFileURL
        var url = start
        while url.path != "/" {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path) { return url.path }
            url.deleteLastPathComponent()
        }
        return start.path
    }

    static func exports(_ context: GitContext) -> String {
        func quoted(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: #"'\''"#) + "'" }
        var lines: [String] = []
        if let name = context.authorName, !name.isEmpty {
            lines += ["export GIT_AUTHOR_NAME=\(quoted(name))", "export GIT_COMMITTER_NAME=\(quoted(name))"]
        }
        if let email = context.authorEmail, !email.isEmpty {
            lines += ["export GIT_AUTHOR_EMAIL=\(quoted(email))", "export GIT_COMMITTER_EMAIL=\(quoted(email))"]
        }
        if let token = context.githubToken { lines.append("export GH_TOKEN=\(quoted(token))") }
        return lines.map { $0 + "\n" }.joined()
    }
}
