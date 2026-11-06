import Foundation

enum FileChangeKind: String, Sendable {
    case added, modified, deleted, renamed, copied, typeChanged, untracked, conflicted

    init?(statusCode: Character) {
        switch statusCode {
        case "M": self = .modified
        case "A": self = .added
        case "D": self = .deleted
        case "R": self = .renamed
        case "C": self = .copied
        case "T": self = .typeChanged
        default: return nil
        }
    }

    var letter: String {
        switch self {
        case .added: "A"
        case .modified: "M"
        case .deleted: "D"
        case .renamed: "R"
        case .copied: "C"
        case .typeChanged: "T"
        case .untracked: "U"
        case .conflicted: "!"
        }
    }
}

struct FileChange: Identifiable, Hashable, Sendable {
    enum Area: String, Sendable { case staged, unstaged, conflicted }

    var path: String
    var originalPath: String?
    var kind: FileChangeKind
    var area: Area

    var id: String { "\(area.rawValue):\(path)" }
    var fileName: String { (path as NSString).lastPathComponent }
    var directory: String { (path as NSString).deletingLastPathComponent }
}

struct RepoStatus: Sendable {
    var branch: String?
    var oid: String?
    var upstream: String?
    var ahead = 0
    var behind = 0
    var staged: [FileChange] = []
    var unstaged: [FileChange] = []
    var conflicted: [FileChange] = []

    var isUnborn: Bool { oid == nil }
    var hasChanges: Bool { !(staged.isEmpty && unstaged.isEmpty && conflicted.isEmpty) }

    func change(id: FileChange.ID?) -> FileChange? {
        guard let id else { return nil }
        return (conflicted + staged + unstaged).first { $0.id == id }
    }
}

struct DiffLine: Hashable, Sendable {
    enum Kind: Sendable { case context, addition, deletion, noNewline }
    var kind: Kind
    var text: String
    var oldLine: Int?
    var newLine: Int?

    var raw: String {
        switch kind {
        case .context: " " + text
        case .addition: "+" + text
        case .deletion: "-" + text
        case .noNewline: text
        }
    }
}

struct DiffHunk: Identifiable, Hashable, Sendable {
    var id: Int
    var header: String
    var oldStart: Int
    var newStart: Int
    var lines: [DiffLine]
}

struct FileDiff: Identifiable, Hashable, Sendable {
    var path: String
    var oldPath: String?
    var headerLines: [String]
    var hunks: [DiffHunk]
    var isBinary: Bool

    var id: String { path }

    /// A standalone patch containing only `hunk`, suitable for `git apply`.
    func patch(for hunk: DiffHunk) -> String {
        (headerLines + [hunk.header] + hunk.lines.map(\.raw)).joined(separator: "\n") + "\n"
    }

    /// A patch containing only the `selected` line indexes of `hunk`.
    /// Unselected changes are neutralised relative to the side the patch is applied to:
    /// forward (staging) keeps unselected deletions as context and drops unselected additions;
    /// `reverse` (unstaging/discarding) does the opposite.
    func patch(for hunk: DiffHunk, selecting selected: Set<Int>, reverse: Bool) -> String {
        var body: [String] = []
        var oldCount = 0, newCount = 0
        var lastKept = false
        for (index, line) in hunk.lines.enumerated() {
            let keepAsChange = selected.contains(index)
            switch line.kind {
            case .context:
                body.append(line.raw); oldCount += 1; newCount += 1; lastKept = true
            case .addition where keepAsChange:
                body.append(line.raw); newCount += 1; lastKept = true
            case .deletion where keepAsChange:
                body.append(line.raw); oldCount += 1; lastKept = true
            case .addition:
                if reverse { body.append(" " + line.text); oldCount += 1; newCount += 1 }
                lastKept = reverse
            case .deletion:
                if !reverse { body.append(" " + line.text); oldCount += 1; newCount += 1 }
                lastKept = !reverse
            case .noNewline:
                if lastKept { body.append(line.raw) }
            }
        }
        let header = "@@ -\(hunk.oldStart),\(oldCount) +\(hunk.newStart),\(newCount) @@"
        return (headerLines + [header] + body).joined(separator: "\n") + "\n"
    }
}

struct Commit: Identifiable, Hashable, Sendable {
    var sha: String
    var parents: [String]
    var authorName: String
    var authorEmail: String
    var date: Date
    var refs: [String]
    var subject: String

    var id: String { sha }
    var shortSHA: String { String(sha.prefix(7)) }
}

struct Branch: Identifiable, Hashable, Sendable {
    var name: String
    var upstream: String?
    var isCurrent: Bool
    var id: String { name }
}

/// A branch on a remote that has no local branch yet.
struct RemoteBranch: Identifiable, Hashable, Sendable {
    var remote: String
    var name: String
    var ref: String { "\(remote)/\(name)" }
    var id: String { ref }
}

struct RemoteInfo: Hashable, Sendable {
    var name: String
    var url: String
    var host: String?
    var owner: String?
    var repo: String?

    var isGitHub: Bool { host == "github.com" }
    var webURL: URL? {
        guard let host, let owner, let repo else { return nil }
        return URL(string: "https://\(host)/\(owner)/\(repo)")
    }
}

struct Stash: Identifiable, Hashable, Sendable {
    var ref: String
    var message: String
    var date: Date
    var id: String { ref }
}

struct Worktree: Identifiable, Hashable, Sendable {
    var path: String
    var head: String?
    var branch: String?
    var isMain = false
    var isLocked = false
    var isPrunable = false

    var id: String { path }
    var name: String { (path as NSString).lastPathComponent }
}

struct Person: Identifiable, Hashable, Sendable, Codable {
    var name: String
    var email: String

    var id: String { email.lowercased() }
    var trailer: String { "Co-authored-by: \(name) <\(email)>" }

    /// Parses "Name <email>".
    init?(parsing text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let open = trimmed.lastIndex(of: "<"), trimmed.hasSuffix(">") else { return nil }
        let name = trimmed[..<open].trimmingCharacters(in: .whitespaces)
        let email = trimmed[trimmed.index(after: open)..<trimmed.index(before: trimmed.endIndex)]
        guard !name.isEmpty, email.contains("@") else { return nil }
        self.init(name: name, email: String(email))
    }

    init(name: String, email: String) {
        self.name = name
        self.email = email
    }
}
