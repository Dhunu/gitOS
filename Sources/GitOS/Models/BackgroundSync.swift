import Foundation
import UserNotifications

/// Periodically fetches every repository with its own account, refreshes `AppState.summaries`,
/// and notifies when a branch falls behind its upstream.
@MainActor
final class BackgroundSync {
    private unowned let app: AppState
    private var loop: Task<Void, Never>?
    private(set) var isFetching = false

    init(app: AppState) {
        self.app = app
    }

    func start() {
        guard loop == nil else { return }
        if app.preferences.notifyNewCommits { requestNotificationPermission() }
        loop = Task { [weak self] in
            await self?.refreshSummaries()
            while !Task.isCancelled {
                guard let self else { return }
                let prefs = self.app.preferences
                if prefs.backgroundFetch { await self.fetchAll() }
                try? await Task.sleep(for: .seconds(max(prefs.fetchIntervalMinutes, 1) * 60))
            }
        }
    }

    func preferencesChanged() {
        guard loop != nil else { return }
        loop?.cancel()
        loop = nil
        start()
    }

    /// Recomputes summaries from local state only (no network).
    func refreshSummaries() async {
        for repo in app.repos {
            await updateSummary(for: repo, fetched: false)
        }
    }

    /// Fetches every repo that has a remote, then refreshes summaries.
    func fetchAll() async {
        guard !isFetching else { return }
        isFetching = true
        defer { isFetching = false }
        for repo in app.repos {
            await updateSummary(for: repo, fetched: true)
        }
    }

    func updateSummary(for repo: RepoRef, fetched: Bool) async {
        let git = GitRepository(url: repo.url)
        let previous = app.summaries[repo.id]
        var summary = previous ?? RepoSummary()
        if fetched {
            do {
                if try await !git.remotes().isEmpty {
                    try await git.fetch(context: app.gitContext(for: repo))
                    summary.lastFetch = .now
                    summary.fetchError = nil
                }
            } catch {
                summary.fetchError = error.localizedDescription
            }
        }
        guard let status = try? await git.status() else { return }
        summary.branch = status.branch
        summary.ahead = status.ahead
        summary.behind = status.behind
        summary.changes = status.staged.count + status.unstaged.count + status.conflicted.count
        app.summaries[repo.id] = summary

        if fetched, app.preferences.notifyNewCommits, let previous, summary.behind > previous.behind,
           let upstream = status.upstream {
            let new = summary.behind - previous.behind
            notify(title: repo.name,
                   body: "\(new) new commit\(new == 1 ? "" : "s") on \(upstream)",
                   repoID: repo.id)
        }
    }

    // MARK: Notifications

    /// Notifications only work from a bundled .app (not a bare `swift run` binary).
    private var canNotify: Bool { Bundle.main.bundleIdentifier != nil }

    func requestNotificationPermission() {
        guard canNotify else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notify(title: String, body: String, repoID: UUID) {
        guard canNotify else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.userInfo = ["repoID": repoID.uuidString]
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
