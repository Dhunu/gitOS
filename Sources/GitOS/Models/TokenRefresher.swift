import AppKit

/// Renews expiring GitHub tokens before they run out, so accounts stay signed in.
/// GitHub OAuth apps with token expiration on issue tokens that last eight hours.
@MainActor
final class TokenRefresher {
    /// Renew this early, so a git command started now can't outlive its token.
    nonisolated private static let margin: TimeInterval = 30 * 60

    private unowned let app: AppState
    private var loop: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?
    /// Refresh tokens are single-use, so two requests at once would sign the account out.
    private var running: [UUID: Task<Bool, Never>] = [:]

    init(app: AppState) {
        self.app = app
    }

    nonisolated static func isDue(expiresAt: Date?, now: Date = .now) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt.timeIntervalSince(now) <= margin
    }

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshAll()
                try? await Task.sleep(for: .seconds(5 * 60))
            }
        }
        // The timer doesn't run during sleep, and a token can expire overnight.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { Task { await self?.refreshAll() } }
        }
    }

    func refreshAll() async {
        for account in app.accounts {
            await refresh(account, force: false)
        }
    }

    /// Returns whether the account holds a newly renewed token.
    @discardableResult
    func refresh(_ account: Account, force: Bool) async -> Bool {
        if let task = running[account.id] { return await task.value }
        guard force || Self.isDue(expiresAt: account.tokenExpiresAt),
              let refreshToken = Keychain.get(account.refreshTokenKey) else { return false }

        let task = Task { await renew(account, refreshToken: refreshToken) }
        running[account.id] = task
        let renewed = await task.value
        running[account.id] = nil
        return renewed
    }

    private func renew(_ account: Account, refreshToken: String) async -> Bool {
        do {
            let clientID = app.githubClientID.trimmingCharacters(in: .whitespaces)
            let grant = try await GitHubDeviceFlow.refresh(clientID: clientID, refreshToken: refreshToken)
            try app.store(grant, for: account)
            if let index = app.accounts.firstIndex(where: { $0.id == account.id }) {
                app.accounts[index].tokenExpiresAt = grant.expiresAt
            }
            if app.rejectedAccountIDs.remove(account.id) != nil {
                Task { await app.sync.fetchAll() }
            }
            return true
        } catch is GitHubDeviceFlow.RefreshRefused {
            app.rejectedAccountIDs.insert(account.id)
            return false
        } catch {
            // Offline or a GitHub hiccup: the refresh token is still good, so try again next round.
            return false
        }
    }
}
