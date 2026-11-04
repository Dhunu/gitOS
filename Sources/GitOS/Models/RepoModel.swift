import Foundation
import Observation

@Observable
@MainActor
final class RepoModel {
    let repoID: RepoRef.ID
    let repo: GitRepository
    let app: AppState

    var status = RepoStatus()
    var branches: [Branch] = []
    var remotes: [RemoteInfo] = []
    var commits: [Commit] = [] { didSet { graph = CommitGraph.layout(commits) } }
    private(set) var graph: [GraphRow] = []
    var stashes: [Stash] = []
    var worktrees: [Worktree] = []
    var selectedStashID: Stash.ID? { didSet { if oldValue != selectedStashID { Task { await loadStashDiff() } } } }
    var stashDiffs: [FileDiff] = []
    var operation: RepoOperation?
    var showAllBranches = false { didSet { Task { await refresh() } } }

    var selectedChangeID: FileChange.ID? { didSet { if oldValue != selectedChangeID { Task { await loadDiff() } } } }
    var currentDiff: FileDiff?
    var selectedCommitID: Commit.ID? { didSet { if oldValue != selectedCommitID { Task { await loadCommitDiff() } } } }
    var commitDiffs: [FileDiff] = []

    // GitHub (see RepoModel+GitHub.swift)
    var pullRequests: [GitHubRepoAPI.PullRequest] = []
    var issues: [GitHubRepoAPI.Issue] = []
    var headChecks: CheckSummary?
    var prChecks: [Int: CheckSummary] = [:]
    var defaultBranch: String?
    var githubError: String?
    var githubLoadedAt: Date?

    var summary = ""
    var details = ""
    var coAuthors: [Person] = []
    var generatingMessage = false
    var extraPeople: [Person] = []

    var activity: String?
    var errorMessage: String?
    var showingAddRemote = false
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

    /// Recent commit authors (plus manually added people) other than the committing account.
    var knownPeople: [Person] {
        var seen = Set<String>()
        let account = resolved.account
        return (extraPeople + commits.map { Person(name: $0.authorName, email: $0.authorEmail) })
            .filter { person in
                !(account?.owns(email: person.email) ?? false)
                    && !person.email.hasSuffix("[bot]@users.noreply.github.com")
                    && seen.insert(person.id).inserted
            }
    }

    // MARK: Loading

    private var pendingRefresh: Task<Void, Never>?

    /// Coalesces bursts of file-system events into one refresh.
    func scheduleRefresh() {
        guard !isBusy else { return }
        pendingRefresh?.cancel()
        pendingRefresh = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await refresh()
        }
    }

    func refresh() async {
        do {
            status = try await repo.status()
            var summary = app.summaries[repoID] ?? RepoSummary()
            summary.branch = status.branch
            summary.ahead = status.ahead
            summary.behind = status.behind
            summary.changes = status.staged.count + status.unstaged.count + status.conflicted.count
            app.summaries[repoID] = summary
            async let branches = repo.branches()
            async let remotes = repo.remotes()
            async let commits = status.isUnborn ? [] : repo.log(allBranches: showAllBranches)
            self.branches = try await branches
            self.remotes = (try? await remotes) ?? []
            operation = await repo.operationInProgress()
            stashes = (try? await repo.stashes()) ?? []
            worktrees = (try? await repo.worktrees()) ?? []
            if !stashes.contains(where: { $0.id == selectedStashID }) { selectedStashID = stashes.first?.id }
            // A cancelled or failed load must not blank a history that's already on screen.
            if let commits = try? await commits { self.commits = commits }
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

    private func loadStashDiff() async {
        guard let ref = selectedStashID else { stashDiffs = []; return }
        stashDiffs = (try? await repo.stashDiff(ref)) ?? []
    }

    // MARK: Actions

    func perform(_ label: String, _ work: () async throws -> Void) async {
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

    /// Applies a whole hunk, or only `lines` (indexes into the hunk) when given.
    func apply(_ action: HunkAction, hunk: DiffHunk, lines: Set<Int> = [], in diff: FileDiff) async {
        let patch = lines.isEmpty
            ? diff.patch(for: hunk)
            : diff.patch(for: hunk, selecting: lines, reverse: action != .stage)
        await perform("Applying hunk") {
            switch action {
            case .stage: try await repo.apply(patch: patch, cached: true, reverse: false)
            case .unstage: try await repo.apply(patch: patch, cached: true, reverse: true)
            case .discard: try await repo.apply(patch: patch, cached: false, reverse: true)
            }
        }
    }

    func commit() async {
        var message = details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? summary
            : summary + "\n\n" + details
        if !coAuthors.isEmpty {
            message += "\n\n" + coAuthors.map(\.trailer).joined(separator: "\n")
        }
        let context = app.gitContext(for: ref)
        await perform("Committing") {
            try await repo.commit(message: message, context: context)
            summary = ""
            details = ""
            coAuthors = []
        }
    }

    /// Fills the summary and description from the staged diff using Claude.
    func generateCommitMessage() async {
        generatingMessage = true
        defer { generatingMessage = false }
        do {
            let diff = try await repo.stagedPatch()
            let (title, body) = try await Claude.commitMessage(
                diff: diff, recentSubjects: commits.map(\.subject), model: app.preferences.aiModel)
            summary = title
            details = body
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func switchBranch(_ name: String) async {
        await perform("Switching to \(name)") { try await repo.switchBranch(name) }
    }

    func createBranch(_ name: String) async {
        await perform("Creating \(name)") { try await repo.createBranch(name) }
    }

    func stash(message: String) async {
        await perform("Stashing") { try await repo.stash(message: message) }
    }

    func applyStash(_ stash: Stash, pop: Bool) async {
        await perform(pop ? "Popping stash" : "Applying stash") { try await repo.stashApply(stash.ref, pop: pop) }
    }

    func dropStash(_ stash: Stash) async {
        await perform("Dropping stash") { try await repo.stashDrop(stash.ref) }
    }

    func addWorktree(path: String, branch: String, newBranch: Bool) async {
        await perform("Adding worktree") { try await repo.addWorktree(path: path, branch: branch, newBranch: newBranch) }
    }

    func removeWorktree(_ tree: Worktree, force: Bool) async {
        await perform("Removing worktree") { try await repo.removeWorktree(path: tree.path, force: force) }
    }

    func fetch() async {
        let context = app.gitContext(for: ref)
        await perform("Fetching") { try await repo.fetch(context: context) }
        await loadGitHub(force: true)
    }

    /// Why this remote can't be added, or nil if it can.
    func remoteProblem(name: String, url: String) -> String? {
        if !Self.isValidRemoteName(name) { return "Remote names can only use letters, numbers, dots, dashes and underscores." }
        if remotes.contains(where: { $0.name == name }) { return "There's already a remote called “\(name)”." }
        if url.isEmpty || url.hasPrefix("-") || url.contains(where: \.isWhitespace) { return "That doesn't look like a repository URL." }
        return nil
    }

    nonisolated static func isValidRemoteName(_ name: String) -> Bool {
        !name.isEmpty && !name.hasPrefix("-") && !name.hasPrefix(".") && !name.hasSuffix(".") && !name.contains("..")
            && name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) }
    }

    /// Adds the remote, then fetches it. An unreachable remote stays added, with the fetch error shown.
    func addRemote(name: String, url: String) async throws {
        try await repo.addRemote(name: name, url: url)
        await fetch()
    }

    /// GitButler keeps its virtual branches merged on `gitbutler/workspace`. Pushing, pulling or
    /// publishing that branch with plain git would break GitButler's state and leak its internal commit.
    var isGitButlerWorkspace: Bool { status.branch?.hasPrefix("gitbutler/") == true }

    private var gitButlerBlocked: Bool {
        guard isGitButlerWorkspace else { return false }
        errorMessage = "\(status.branch ?? "This branch") is managed by GitButler. Pull and push from GitButler, or switch to one of your own branches to use GitOS."
        return true
    }

    func pull() async {
        guard !gitButlerBlocked else { return }
        let context = app.gitContext(for: ref)
        guard status.upstream == nil else {
            await perform("Pulling") { try await repo.pull(context: context) }
            return
        }
        // No tracking branch: link to <remote>/<branch> if the remote has it, otherwise explain.
        guard let branch = status.branch else {
            errorMessage = "You're not on a branch (detached HEAD), so there's nothing to pull into. Switch to a branch first."
            return
        }
        let remote = primaryRemote?.name ?? "origin"
        await perform("Pulling") {
            try await repo.fetch(context: context)
            guard await repo.remoteBranchExists(remote: remote, branch: branch) else {
                throw GitFailure(command: "pull",
                                 message: "“\(branch)” isn't on \(remote) yet, so there's nothing to pull. Use Publish to push it first.",
                                 exitCode: 1)
            }
            try await repo.setUpstream(of: branch, to: "\(remote)/\(branch)")
            try await repo.pull(context: context)
        }
    }

    func forcePush() async {
        guard !gitButlerBlocked else { return }
        let context = app.gitContext(for: ref)
        let remote = primaryRemote?.name ?? "origin"
        await perform("Force pushing") {
            try await repo.push(remote: remote, setUpstream: status.upstream == nil, force: true, context: context)
        }
        await loadGitHub(force: true)
    }

    // MARK: Rebase & merge

    func interactiveRebase(steps: [RebaseStep], base: String?) async {
        let context = app.gitContext(for: ref)
        await perform("Rebasing") { try await repo.interactiveRebase(base: base, steps: steps, context: context) }
    }

    func continueOperation() async {
        guard let operation else { return }
        let context = app.gitContext(for: ref)
        await perform("Continuing \(operation.command)") { try await repo.continueOperation(operation, context: context) }
    }

    func abortOperation() async {
        guard let operation else { return }
        await perform("Aborting \(operation.command)") { try await repo.abortOperation(operation) }
    }

    func skipRebaseStep() async {
        let context = app.gitContext(for: ref)
        await perform("Skipping commit") { try await repo.skipRebaseStep(context: context) }
    }

    func merge(_ branch: String) async {
        let context = app.gitContext(for: ref)
        await perform("Merging \(branch)") { try await repo.merge(branch, context: context) }
    }

    /// Pushes, first checking that unpushed commits were authored by the account that will push them.
    func push(force skipCheck: Bool = false) async {
        guard !gitButlerBlocked else { return }
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
        await loadGitHub(force: true)
    }

    /// The single most useful sync action for the toolbar button.
    func sync() async {
        guard !gitButlerBlocked else { return }
        if status.upstream == nil || status.ahead > 0 && status.behind == 0 {
            await push()
        } else if status.behind > 0 {
            await pull()
        } else {
            await fetch()
        }
    }
}
