import Foundation
import Observation

@Observable
@MainActor
final class RepoModel {
    let repoID: RepoRef.ID
    let repo: GitRepository
    private let app: AppState

    var status = RepoStatus()
    var branches: [Branch] = []
    var remotes: [RemoteInfo] = []
    var commits: [Commit] = []

    var selectedChangeID: FileChange.ID? { didSet { if oldValue != selectedChangeID { Task { await loadDiff() } } } }
    var currentDiff: FileDiff?
    var selectedCommitID: Commit.ID? { didSet { if oldValue != selectedCommitID { Task { await loadCommitDiff() } } } }
    var commitDiffs: [FileDiff] = []

    var summary = ""
    var details = ""

    var activity: String?
    var errorMessage: String?
    var pushWarning: PushWarning?

    struct PushWarning: Identifiable {
        let id = UUID()
        let foreignEmails: [String]
        let account: Account
    }

    init(ref: RepoRef, app: AppState) {
        self.repoID = ref.id
        self.repo = GitRepository(url: ref.url)
        self.app = app
    }

    var ref: RepoRef { app.repos.first { $0.id == repoID } ?? RepoRef(id: repoID, path: repo.url.path) }
    var resolved: ResolvedAccount { app.resolveAccount(for: ref) }
    var primaryRemote: RemoteInfo? { remotes.first { $0.name == "origin" } ?? remotes.first }
    var selectedChange: FileChange? { status.change(id: selectedChangeID) }
    var isBusy: Bool { activity != nil }

    // MARK: Loading

    func refresh() async {
        do {
            status = try await repo.status()
            async let branches = repo.branches()
            async let remotes = repo.remotes()
            async let commits = status.isUnborn ? [] : repo.log()
            self.branches = try await branches
            self.remotes = (try? await remotes) ?? []
            self.commits = (try? await commits) ?? []
            if status.change(id: selectedChangeID) == nil {
                selectedChangeID = (status.conflicted + status.unstaged + status.staged).first?.id
            } else {
                await loadDiff()
            }
            if selectedCommitID == nil { selectedCommitID = self.commits.first?.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadDiff() async {
        guard let change = selectedChange else { currentDiff = nil; return }
        currentDiff = try? await repo.diff(for: change)
    }

    private func loadCommitDiff() async {
        guard let sha = selectedCommitID else { commitDiffs = []; return }
        commitDiffs = (try? await repo.show(sha)) ?? []
    }

    // MARK: Actions

    private func perform(_ label: String, _ work: () async throws -> Void) async {
        activity = label
        defer { activity = nil }
        do {
            try await work()
        } catch {
            errorMessage = error.localizedDescription
        }
        await refresh()
    }

    func toggleStage(_ change: FileChange) async {
        if change.area == .staged {
            await unstage([change])
        } else {
            await stage([change])
        }
    }

    func stage(_ changes: [FileChange]) async {
        await perform("Staging") {
            try await repo.stage(changes.map(\.path) + changes.compactMap(\.originalPath))
        }
    }

    func unstage(_ changes: [FileChange]) async {
        await perform("Unstaging") {
            try await repo.unstage(changes.map(\.path) + changes.compactMap(\.originalPath), unborn: status.isUnborn)
        }
    }

    func discard(_ change: FileChange) async {
        await perform("Discarding") { try await repo.discard(change) }
    }

    enum HunkAction { case stage, unstage, discard }

    func apply(_ action: HunkAction, hunk: DiffHunk, in diff: FileDiff) async {
        let patch = diff.patch(for: hunk)
        await perform("Applying hunk") {
            switch action {
            case .stage: try await repo.apply(patch: patch, cached: true, reverse: false)
            case .unstage: try await repo.apply(patch: patch, cached: true, reverse: true)
            case .discard: try await repo.apply(patch: patch, cached: false, reverse: true)
            }
        }
    }

    func commit() async {
        let message = details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? summary
            : summary + "\n\n" + details
        let context = app.gitContext(for: ref)
        await perform("Committing") {
            try await repo.commit(message: message, context: context)
            summary = ""
            details = ""
        }
    }

    func switchBranch(_ name: String) async {
        await perform("Switching to \(name)") { try await repo.switchBranch(name) }
    }

    func createBranch(_ name: String) async {
        await perform("Creating \(name)") { try await repo.createBranch(name) }
    }

    func fetch() async {
        let context = app.gitContext(for: ref)
        await perform("Fetching") { try await repo.fetch(context: context) }
    }

    func pull() async {
        let context = app.gitContext(for: ref)
        await perform("Pulling") { try await repo.pull(context: context) }
    }

    /// Pushes, first checking that unpushed commits were authored by the account that will push them.
    func push(force skipCheck: Bool = false) async {
        if !skipCheck, let account = resolved.account {
            let emails = (try? await repo.unpushedAuthorEmails(hasUpstream: status.upstream != nil)) ?? []
            let foreign = emails.filter { !account.owns(email: $0) }.sorted()
            if !foreign.isEmpty {
                pushWarning = PushWarning(foreignEmails: foreign, account: account)
                return
            }
        }
        let context = app.gitContext(for: ref)
        let remote = primaryRemote?.name ?? "origin"
        let needsUpstream = status.upstream == nil
        await perform("Pushing") {
            try await repo.push(remote: remote, setUpstream: needsUpstream, context: context)
        }
    }

    /// The single most useful sync action for the toolbar button.
    func sync() async {
        if status.upstream == nil || status.ahead > 0 && status.behind == 0 {
            await push()
        } else if status.behind > 0 {
            await pull()
        } else {
            await fetch()
        }
    }
}
