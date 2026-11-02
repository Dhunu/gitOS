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

    var title: String { label.isEmpty ? "@\(login)" : "\(label) · @\(login)" }
    var noreplyEmail: String { "\(githubID)+\(login)@users.noreply.github.com" }

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
