import AppKit
import Foundation
import Observation

struct Preferences: Codable, Equatable, Sendable {
    var backgroundFetch = true
    var fetchIntervalMinutes = 10
    var notifyNewCommits = true
    var showMenuBarExtra = true
    var aiModel = Claude.defaultModel
    var aiProvider = AIProvider.claudeCode

    init() {}

    // Decode field by field so preferences saved by older builds keep working.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Preferences()
        backgroundFetch = try c.decodeIfPresent(Bool.self, forKey: .backgroundFetch) ?? d.backgroundFetch
        fetchIntervalMinutes = try c.decodeIfPresent(Int.self, forKey: .fetchIntervalMinutes) ?? d.fetchIntervalMinutes
        notifyNewCommits = try c.decodeIfPresent(Bool.self, forKey: .notifyNewCommits) ?? d.notifyNewCommits
        showMenuBarExtra = try c.decodeIfPresent(Bool.self, forKey: .showMenuBarExtra) ?? d.showMenuBarExtra
        aiModel = try c.decodeIfPresent(String.self, forKey: .aiModel) ?? d.aiModel
        aiProvider = try c.decodeIfPresent(AIProvider.self, forKey: .aiProvider) ?? d.aiProvider
    }
}

/// Last known state of a repository, kept fresh by background sync for the sidebar and menu bar.
struct RepoSummary: Sendable {
    var branch: String?
    var ahead = 0
    var behind = 0
    var changes = 0
    var lastFetch: Date?
    var fetchError: String?
}

@Observable
@MainActor
final class AppState {
    static let shared = AppState()

    var accounts: [Account] = [] { didSet { save() } }
    var rules: [FolderRule] = [] { didSet { save() } }
    var repos: [RepoRef] = [] { didSet { save() } }
    var defaultAccountID: UUID? { didSet { save() } }
    /// Accounts whose token GitHub has refused. Signing in again clears them.
    var rejectedAccountIDs: Set<UUID> = []
    /// The shared GitOS OAuth app. A Client ID is public, and Settings › GitHub can replace it.
    nonisolated static let builtInGitHubClientID = "Ov23liHw3HtFJTksW1a5"
    var githubClientID = AppState.builtInGitHubClientID { didSet { save() } }
    var selectedRepoID: RepoRef.ID? { didSet { save() } }
    var preferences = Preferences() { didSet { save(); if oldValue != preferences { sync.preferencesChanged() } } }
    var summaries: [RepoRef.ID: RepoSummary] = [:]
    var lastError: String?
    var showingClone = false
    @ObservationIgnored lazy var sync = BackgroundSync(app: self)
    @ObservationIgnored lazy var tokens = TokenRefresher(app: self)

    private var loading = false

    private struct Persisted: Codable {
        var accounts: [Account] = []
        var rules: [FolderRule] = []
        var repos: [RepoRef] = []
        var defaultAccountID: UUID?
        var githubClientID = ""
        var selectedRepoID: UUID?
        // Optional so state files written before a field existed still decode.
        var preferences: Preferences?
    }

    private static var stateURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GitOS", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("state.json")
    }

    init() {
        load()
    }

    var selectedRepo: RepoRef? { repos.first { $0.id == selectedRepoID } }

    func account(id: UUID?) -> Account? {
        guard let id else { return nil }
        return accounts.first { $0.id == id }
    }

    // MARK: Account resolution

    func resolveAccount(for repo: RepoRef) -> ResolvedAccount {
        if let account = account(id: repo.accountOverride) {
            return ResolvedAccount(account: account, source: .override)
        }
        let rule = rules
            .filter { $0.matches(repo.path) && account(id: $0.accountID) != nil }
            .max { $0.folder.count < $1.folder.count }
        if let rule {
            return ResolvedAccount(account: account(id: rule.accountID), source: .folderRule(rule.folder))
        }
        if let account = account(id: defaultAccountID) {
            return ResolvedAccount(account: account, source: .defaultAccount)
        }
        return ResolvedAccount(account: nil, source: .none)
    }

    func gitContext(for repo: RepoRef) -> GitContext {
        guard let account = resolveAccount(for: repo).account else { return .none }
        return gitContext(for: account)
    }

    func gitContext(for account: Account) -> GitContext {
        GitContext(
            authorName: account.commitName,
            authorEmail: account.commitEmail,
            signing: account.signing,
            githubUser: account.login,
            githubToken: Keychain.get(account.id.uuidString)
        )
    }

    func setOverride(_ accountID: UUID?, for repoID: RepoRef.ID) {
        guard let index = repos.firstIndex(where: { $0.id == repoID }) else { return }
        repos[index].accountOverride = accountID
    }

    // MARK: Accounts

    /// Adds or refreshes an account from a freshly issued OAuth token.
    func signIn(grant: GitHubDeviceFlow.TokenGrant) async throws -> Account {
        let api = GitHubAPI(token: grant.accessToken)
        async let userRequest = api.user()
        async let emailsRequest = api.emails()
        let user = try await userRequest
        let emails = (try? await emailsRequest) ?? []

        let verified = emails.filter(\.verified).map(\.email)
        let primary = emails.first { $0.primary && $0.verified }?.email

        var account = accounts.first { $0.githubID == user.id } ?? Account(
            githubID: user.id,
            login: user.login,
            displayName: user.name ?? user.login,
            commitName: user.name ?? user.login,
            commitEmail: ""
        )
        account.login = user.login
        account.displayName = user.name ?? user.login
        account.avatarURL = user.avatarURL
        account.knownEmails = Array(Set(verified + [account.noreplyEmail])).sorted()
        if account.commitEmail.isEmpty { account.commitEmail = primary ?? account.noreplyEmail }

        account.tokenExpiresAt = grant.expiresAt
        try store(grant, for: account)
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = account
        } else {
            accounts.append(account)
        }
        if defaultAccountID == nil { defaultAccountID = account.id }
        if rejectedAccountIDs.remove(account.id) != nil {
            Task { await sync.fetchAll() }
        }
        return account
    }

    /// Saves the tokens for `account`. The refresh token is single-use, so each grant replaces it.
    func store(_ grant: GitHubDeviceFlow.TokenGrant, for account: Account) throws {
        try Keychain.set(grant.accessToken, for: account.id.uuidString)
        if let refreshToken = grant.refreshToken {
            try Keychain.set(refreshToken, for: account.refreshTokenKey)
        } else {
            Keychain.delete(account.refreshTokenKey)
        }
    }

    nonisolated static func isRejectedSignIn(_ error: Error) -> Bool {
        (error as? GitFailure)?.isRejectedCredential == true || (error as? GitHubError)?.statusCode == 401
    }

    /// The error's text, with advice when it looks like the repo needs a different account.
    func message(for error: Error, repo: RepoRef, owner: String?) -> String {
        if let login = resolveAccount(for: repo).account?.login,
           let hint = (error as? GitFailure)?.accountHint(login: login, owner: owner) {
            return hint
        }
        return error.localizedDescription
    }

    /// GitHub's page for this app, where organization access is requested.
    var gitHubConnectionURL: URL? {
        URL(string: "https://github.com/settings/connections/applications/\(Self.clientID(saved: githubClientID))")
    }

    func hasRejectedSignIn(for repo: RepoRef) -> Bool {
        resolveAccount(for: repo).account.map { rejectedAccountIDs.contains($0.id) } ?? false
    }

    /// Records a refused token and returns true. Without a saved token the failure came from
    /// the user's own git credentials, which GitOS can't fix by reconnecting.
    @discardableResult
    func noteRejectedSignIn(_ error: Error, for repo: RepoRef) -> Bool {
        guard Self.isRejectedSignIn(error),
              let account = resolveAccount(for: repo).account,
              Keychain.get(account.id.uuidString) != nil else { return false }
        rejectedAccountIDs.insert(account.id)
        Task { await tokens.refresh(account, force: true) }
        return true
    }

    func removeAccount(_ account: Account) {
        Keychain.delete(account.id.uuidString)
        Keychain.delete(account.refreshTokenKey)
        rejectedAccountIDs.remove(account.id)
        accounts.removeAll { $0.id == account.id }
        rules.removeAll { $0.accountID == account.id }
        for index in repos.indices where repos[index].accountOverride == account.id {
            repos[index].accountOverride = nil
        }
        if defaultAccountID == account.id { defaultAccountID = accounts.first?.id }
    }

    // MARK: Repositories

    func addRepositoryViaPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add Repository"
        panel.message = "Choose one or more local git repositories"
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        Task { for url in urls { await addRepository(at: url) } }
    }

    func addRepository(at url: URL) async {
        do {
            let root = try await GitRepository.topLevel(of: url)
            if let existing = repos.first(where: { $0.path == root.path }) {
                selectedRepoID = existing.id
                return
            }
            let ref = RepoRef(path: root.path)
            repos.append(ref)
            repos.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            selectedRepoID = ref.id
        } catch {
            lastError = "\(url.lastPathComponent) isn't a git repository."
        }
    }

    /// Folder a new clone for `account` should go in: its folder rule if it has one, else ~/Developer or home.
    func suggestedCloneFolder(for account: Account?) -> URL {
        if let account, let rule = rules.first(where: { $0.accountID == account.id }) {
            return URL(fileURLWithPath: rule.folder)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let developer = home.appendingPathComponent("Developer")
        return FileManager.default.fileExists(atPath: developer.path) ? developer : home
    }

    /// Clones with `account`'s credentials, adds the repo, and pins the account if folder rules wouldn't pick it.
    func clone(_ remoteURL: String, into parent: URL, name: String, account: Account?) async throws {
        let context = account.map { gitContext(for: $0) } ?? .none
        try await Git.run(["clone", "--", remoteURL, name], in: parent, context: context)
        let path = parent.appendingPathComponent(name).path
        var ref = RepoRef(path: path)
        if let account, resolveAccount(for: ref).account?.id != account.id {
            ref.accountOverride = account.id
        }
        repos.append(ref)
        repos.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        selectedRepoID = ref.id
    }

    func removeRepository(_ id: RepoRef.ID) {
        repos.removeAll { $0.id == id }
        if selectedRepoID == id { selectedRepoID = repos.first?.id }
    }

    // MARK: Persistence

    nonisolated static func clientID(saved: String) -> String {
        saved.trimmingCharacters(in: .whitespaces).isEmpty ? builtInGitHubClientID : saved
    }

    private func load() {
        loading = true
        defer { loading = false }
        guard let data = try? Data(contentsOf: Self.stateURL),
              let state = try? JSONDecoder().decode(Persisted.self, from: data) else { return }
        accounts = state.accounts
        rules = state.rules
        repos = state.repos
        defaultAccountID = state.defaultAccountID
        githubClientID = Self.clientID(saved: state.githubClientID)
        selectedRepoID = state.selectedRepoID
        preferences = state.preferences ?? Preferences()
    }

    private func save() {
        guard !loading else { return }
        let state = Persisted(accounts: accounts, rules: rules, repos: repos, defaultAccountID: defaultAccountID,
                              githubClientID: githubClientID, selectedRepoID: selectedRepoID,
                              preferences: preferences)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(state).write(to: Self.stateURL, options: .atomic)
    }
}
