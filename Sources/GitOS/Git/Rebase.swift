import Foundation

struct RebaseStep: Identifiable, Hashable, Sendable {
    enum Action: String, CaseIterable, Sendable {
        case pick, reword, squash, fixup, drop

        var title: String { rawValue.capitalized }
        var help: String {
            switch self {
            case .pick: "Keep the commit"
            case .reword: "Keep the commit, change its message"
            case .squash: "Meld into the previous commit, keeping both messages"
            case .fixup: "Meld into the previous commit, discarding this message"
            case .drop: "Remove the commit"
            }
        }
    }

    var sha: String
    var subject: String
    var action: Action = .pick
    /// Full new message for `.reword`.
    var message: String = ""

    var id: String { sha }
}

/// A rebase, merge, cherry-pick or revert that stopped part-way (usually on a conflict).
enum RepoOperation: Equatable, Sendable {
    case rebase(step: Int?, total: Int?)
    case merge
    case cherryPick
    case revert

    var title: String {
        switch self {
        case .rebase(let step?, let total?): "Rebase in progress (\(step) of \(total))"
        case .rebase: "Rebase in progress"
        case .merge: "Merge in progress"
        case .cherryPick: "Cherry-pick in progress"
        case .revert: "Revert in progress"
        }
    }

    var command: String {
        switch self {
        case .rebase: "rebase"
        case .merge: "merge"
        case .cherryPick: "cherry-pick"
        case .revert: "revert"
        }
    }
}

enum RebaseTodo {
    /// Builds a `git rebase -i` todo list (oldest first). Rewords become a pick followed by an
    /// `exec git commit --amend` that reads the new message from a file in `messageDirectory`.
    static func build(_ steps: [RebaseStep], messageDirectory: URL) throws -> String {
        var lines: [String] = []
        for (index, step) in steps.enumerated() {
            switch step.action {
            case .reword:
                let file = messageDirectory.appendingPathComponent("msg-\(index).txt")
                try step.message.write(to: file, atomically: true, encoding: .utf8)
                lines.append("pick \(step.sha)")
                lines.append("exec git commit --amend --allow-empty --no-verify --cleanup=strip -F \(shellQuote(file.path))")
            default:
                lines.append("\(step.action.rawValue) \(step.sha)")
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func validate(_ steps: [RebaseStep]) -> String? {
        let kept = steps.filter { $0.action != .drop }
        if let first = kept.first, first.action == .squash || first.action == .fixup {
            return "The first remaining commit can't be squashed or fixed up. There's nothing before it to meld into."
        }
        if steps.contains(where: { $0.action == .reword && $0.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return "A reworded commit needs a message."
        }
        return nil
    }

    static func shellQuote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

extension GitRepository {
    var gitDirectory: URL {
        get async throws {
            let path = try await Git.run(["rev-parse", "--absolute-git-dir"], in: url)
            return URL(fileURLWithPath: path.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    func operationInProgress() async -> RepoOperation? {
        guard let dir = try? await gitDirectory else { return nil }
        let fm = FileManager.default
        func exists(_ name: String) -> Bool { fm.fileExists(atPath: dir.appendingPathComponent(name).path) }
        func number(_ name: String) -> Int? {
            (try? String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8))
                .flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        }
        if exists("rebase-merge") { return .rebase(step: number("rebase-merge/msgnum"), total: number("rebase-merge/end")) }
        if exists("rebase-apply") { return .rebase(step: number("rebase-apply/next"), total: number("rebase-apply/last")) }
        if exists("MERGE_HEAD") { return .merge }
        if exists("CHERRY_PICK_HEAD") { return .cherryPick }
        if exists("REVERT_HEAD") { return .revert }
        return nil
    }

    /// Runs `git rebase -i` non-interactively with the given steps. `base` is the parent of the
    /// oldest step, or nil to rebase from the root.
    func interactiveRebase(base: String?, steps: [RebaseStep], context: GitContext) async throws {
        if let problem = RebaseTodo.validate(steps) { throw GitFailure(command: "rebase", message: problem, exitCode: 1) }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gitos-rebase-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let todo = dir.appendingPathComponent("todo")
        try RebaseTodo.build(steps, messageDirectory: dir).write(to: todo, atomically: true, encoding: .utf8)
        // Messages must outlive a rebase that stops on a conflict, so the folder is left for the OS to clean up.
        let env = [
            "GIT_SEQUENCE_EDITOR": "cp \(RebaseTodo.shellQuote(todo.path))",
            "GIT_EDITOR": "true",
        ]
        try await Git.run(["rebase", "-i", "--no-autosquash"] + [base ?? "--root"], in: url, context: context, environment: env)
    }

    func continueOperation(_ operation: RepoOperation, context: GitContext) async throws {
        let env = ["GIT_EDITOR": "true"]
        switch operation {
        case .merge: try await Git.run(["commit", "--no-edit"], in: url, context: context, environment: env)
        default: try await Git.run([operation.command, "--continue"], in: url, context: context, environment: env)
        }
    }

    func abortOperation(_ operation: RepoOperation) async throws {
        try await Git.run([operation.command, "--abort"], in: url)
    }

    func skipRebaseStep(context: GitContext) async throws {
        try await Git.run(["rebase", "--skip"], in: url, context: context, environment: ["GIT_EDITOR": "true"])
    }

    func merge(_ branch: String, context: GitContext) async throws {
        try await Git.run(["merge", "--no-edit", branch], in: url, context: context, environment: ["GIT_EDITOR": "true"])
    }

    func fullMessage(of sha: String) async throws -> String {
        try await Git.run(["log", "-1", "--format=%B", sha], in: url).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
