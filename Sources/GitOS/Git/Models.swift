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
