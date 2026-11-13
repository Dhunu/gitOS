import Foundation

struct SigningConfig: Codable, Hashable, Sendable {
    enum Format: String, Codable, CaseIterable, Sendable {
        case ssh, openpgp
        var title: String { self == .ssh ? "SSH key" : "GPG key" }
    }

    var format: Format = .ssh
    /// Path to an SSH public key, or a GPG key ID.
    var key: String = ""
}

struct Account: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var host = "github.com"
    var githubID: Int
    var login: String
    var displayName: String
    var avatarURL: URL?
    var label: String = ""
    var commitName: String
    var commitEmail: String
    /// Verified emails on the GitHub account (incl. the noreply address); used for the push mismatch check.
    var knownEmails: [String] = []
    var signing: SigningConfig?
    /// When the GitHub token runs out. Nil for tokens that don't expire.
    var tokenExpiresAt: Date?

    var refreshTokenKey: String { "\(id.uuidString).refresh" }
    var title: String { label.isEmpty ? "@\(login)" : "\(label) · @\(login)" }
    var noreplyEmail: String { "\(githubID)+\(login)@users.noreply.github.com" }

    /// One letter that tells this account apart from the others: its label ("Work" → W), else its login.
    var badgeInitial: String {
        let source = label.trimmingCharacters(in: .whitespaces).isEmpty ? login : label
        return String(source.prefix(1)).uppercased()
    }

    /// Position used to pick a distinct badge colour; stable while the account list doesn't change.
    static func badgeIndex(of id: Account.ID, in accounts: [Account]) -> Int {
        accounts.firstIndex { $0.id == id } ?? 0
    }

    /// Names who an action that writes to GitHub runs as, e.g. "Create Pull Request as @maya".
    static func titled(_ action: String, as login: String?) -> String {
        login.map { "\(action) as @\($0)" } ?? action
    }

    func owns(email: String) -> Bool {
        let email = email.lowercased()
        return email == commitEmail.lowercased() || knownEmails.contains { $0.lowercased() == email }
    }
}

struct FolderRule: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var folder: String
    var accountID: UUID

    func matches(_ path: String) -> Bool {
        let folder = folder.hasSuffix("/") ? folder : folder + "/"
        return (path + "/").hasPrefix(folder)
    }
}

struct RepoRef: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var path: String
    var accountOverride: UUID?

    var name: String { (path as NSString).lastPathComponent }
    var url: URL { URL(fileURLWithPath: path) }
}

/// Which account applies to a repo, and why.
struct ResolvedAccount {
    enum Source: Equatable {
        case override
        case folderRule(String)
        case defaultAccount
        case none
    }

    var account: Account?
    var source: Source

    var explanation: String {
        switch source {
        case .override: "Chosen for this repository"
        case .folderRule(let folder): "Folder rule: \((folder as NSString).abbreviatingWithTildeInPath)"
        case .defaultAccount: "Default account"
        case .none: "No account. Using your global git config and credentials"
        }
    }
}
