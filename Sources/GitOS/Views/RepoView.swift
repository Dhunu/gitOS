import SwiftUI

struct RepoView: View {
    @Environment(AppState.self) private var app
    @State var model: RepoModel
    @State private var tab: Tab = .changes
    @State private var newBranchName = ""
    @State private var showingNewBranch = false
    @State private var watcher: RepoWatcher?

    enum Tab: String, CaseIterable {
        case changes = "Changes", history = "History", pulls = "Pull Requests", issues = "Issues"
        case stashes = "Stashes", worktrees = "Worktrees"

        var icon: String {
            switch self {
            case .changes: "square.and.pencil"
            case .history: "clock.arrow.circlepath"
            case .pulls: "arrow.triangle.pull"
            case .issues: "smallcircle.filled.circle"
            case .stashes: "tray.full"
            case .worktrees: "square.stack.3d.up"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            RepoTabBar(selection: $tab, count: count(for:))
            Divider()
            if model.isGitButlerWorkspace {
                GitButlerBanner(model: model)
                Divider()
            }
            if let operation = model.operation {
                OperationBanner(model: model, operation: operation) {
                    tab = .changes
                    model.selectedChangeID = model.status.conflicted.first?.id
                }
                Divider()
            }
            switch tab {
            case .changes: ChangesView(model: model)
            case .history: HistoryView(model: model)
            case .pulls: PullRequestsView(model: model)
            case .issues: IssuesView(model: model) { tab = .changes }
            case .stashes: StashesView(model: model)
            case .worktrees: WorktreesView(model: model)
            }
            Divider()
            RepoStatusBar(model: model)
        }
        .background(Theme.canvas)
        .navigationTitle(model.ref.name)
        .navigationSubtitle(model.status.branch ?? "detached HEAD")
        .toolbar {
            ToolbarItem { AccountMenu(model: model) }
            ToolbarItem { branchMenu }
            ToolbarItem {
                if let checks = model.headChecks, checks.state != .none {
                    Menu {
                        ForEach(Array(checks.items.enumerated()), id: \.offset) { _, item in
                            Button {
                                if let url = item.url { NSWorkspace.shared.open(url) }
                            } label: {
                                Label(item.name, systemImage: item.state == .success ? "checkmark.circle"
                                      : item.state == .failure ? "xmark.circle" : "clock")
                            }
                        }
                    } label: {
                        ChecksBadge(checks: checks)
                    }
                    .help("Checks on \(model.status.branch ?? "HEAD"): \(checks.description)")
                }
            }
            ToolbarItem { syncButton }
        }
        .task {
            await model.refresh()
            await model.loadGitHub()
            watcher = RepoWatcher(path: model.repo.url.path) { [model] in model.scheduleRefresh() }
        }
        .onDisappear {
            watcher?.stop()
            watcher = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await model.refresh() }
        }
        .background {
            Button("Refresh") { Task { await model.refresh() } }
                .keyboardShortcut("r")
                .hidden()
        }
        .alert("Git error", isPresented: Binding(
            get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .alert("Push as \(model.pushWarning?.account.title ?? "")?", isPresented: Binding(
            get: { model.pushWarning != nil }, set: { if !$0 { model.pushWarning = nil } }
        ), presenting: model.pushWarning) { _ in
            Button("Push Anyway", role: .destructive) { Task { await model.push(force: true) } }
            Button("Cancel", role: .cancel) {}
        } message: { warning in
            Text("Unpushed commits were authored as \(warning.foreignEmails.joined(separator: ", ")), which isn't an email on \(warning.account.title).")
        }
        .sheet(isPresented: $showingNewBranch) {
            NewBranchSheet(name: $newBranchName, base: model.status.branch) {
                let name = newBranchName
                newBranchName = ""
                Task { await model.createBranch(name) }
            }
        }
    }

    private func count(for tab: Tab) -> Int {
        switch tab {
        case .changes: model.status.staged.count + model.status.unstaged.count + model.status.conflicted.count
        case .stashes: model.stashes.count
        case .worktrees: max(model.worktrees.count - 1, 0)
        case .pulls: model.pullRequests.count
        case .issues: model.issues.count
        case .history: 0
        }
    }

    private var branchMenu: some View {
        Menu {
            Section("Switch to") {
                ForEach(model.branches) { branch in
                    Button {
                        Task { await model.switchBranch(branch.name) }
                    } label: {
                        if branch.isCurrent {
                            Label(branch.name, systemImage: "checkmark")
                        } else {
                            Text(branch.name)
                        }
                    }
                    .disabled(branch.isCurrent)
                }
            }
            Menu("Merge into \(model.status.branch ?? "HEAD")") {
                ForEach(model.branches.filter { !$0.isCurrent }) { branch in
                    Button(branch.name) { Task { await model.merge(branch.name) } }
                }
            }
            .disabled(model.status.hasChanges || model.status.branch == nil)
            Divider()
            Button("New Branch…") { showingNewBranch = true }
                .keyboardShortcut("n", modifiers: [.command, .shift])
        } label: {
            Label(model.status.branch ?? "detached", systemImage: "arrow.triangle.branch")
                .labelStyle(.titleAndIcon)
        }
        .help("Current branch")
    }

    private var syncButton: some View {
        Menu {
            Button("Fetch", systemImage: "arrow.clockwise") { Task { await model.fetch() } }
            Button("Pull", systemImage: "arrow.down") { Task { await model.pull() } }
            Button("Push", systemImage: "arrow.up") { Task { await model.push() } }
            Divider()
            Button("Force Push (with Lease)", systemImage: "exclamationmark.arrow.triangle.2.circlepath") {
                Task { await model.forcePush() }
            }
            .help("Overwrites the remote branch unless someone else pushed to it since your last fetch")
        } label: {
            if let activity = model.activity {
                Label(activity, systemImage: "hourglass")
            } else {
                Label(syncTitle, systemImage: syncIcon)
            }
        } primaryAction: {
            Task { await model.sync() }
        }
        .labelStyle(.titleAndIcon)
        .disabled(model.isBusy || model.remotes.isEmpty || model.isGitButlerWorkspace)
        .help(model.isGitButlerWorkspace ? "GitButler manages this branch. Sync it from GitButler"
              : model.remotes.isEmpty ? "This repository has no remote" : "Fetch, pull or push")
    }

    private var syncTitle: String {
        let status = model.status
        if status.upstream == nil { return "Publish" }
        if status.behind > 0 && status.ahead > 0 { return "↓\(status.behind) ↑\(status.ahead)" }
        if status.behind > 0 { return "Pull ↓\(status.behind)" }
        if status.ahead > 0 { return "Push ↑\(status.ahead)" }
        return "Fetch"
    }

    private var syncIcon: String {
        let status = model.status
        if status.upstream == nil || status.ahead > 0 && status.behind == 0 { return "arrow.up.circle" }
        if status.behind > 0 { return "arrow.down.circle" }
        return "arrow.clockwise"
    }
}

private struct NewBranchSheet: View {
    @Binding var name: String
    let base: String?
    let onCreate: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            TextField("Branch name", text: $name)
                .onSubmit(create)
            if let base {
                Text("Branches from \(base)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create Branch", action: create).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .navigationTitle("New Branch")
    }

    private func create() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        name = name.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "-")
        onCreate()
        dismiss()
    }
}

struct AccountMenu: View {
    @Environment(AppState.self) private var app
    let model: RepoModel

    var body: some View {
        let resolved = model.resolved
        Menu {
            Section("Account for \(model.ref.name)") {
                Button {
                    app.setOverride(nil, for: model.repoID)
                } label: {
                    let automatic = automaticDescription
                    if model.ref.accountOverride == nil {
                        Label(automatic, systemImage: "checkmark")
                    } else {
                        Text(automatic)
                    }
                }
                ForEach(app.accounts) { account in
                    Button {
                        app.setOverride(account.id, for: model.repoID)
                    } label: {
                        if model.ref.accountOverride == account.id {
                            Label(account.title, systemImage: "checkmark")
                        } else {
                            Text(account.title)
                        }
                    }
                }
            }
            if let account = resolved.account {
                Section("Commits as") {
                    Text("\(account.commitName) <\(account.commitEmail)>")
                    if let signing = account.signing, !signing.key.isEmpty {
                        Text("Signed with \(signing.format.title)")
                    }
                }
            }
            Divider()
            SettingsLink { Text("Manage Accounts & Folder Rules…") }
        } label: {
            HStack(spacing: 6) {
                if let account = resolved.account {
                    AvatarView(account: account, size: 18)
                    Text(account.login)
                } else {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                    Text("No account")
                }
            }
        }
        .help(resolved.account.map { "\($0.title): \(resolved.explanation)" } ?? resolved.explanation)
    }

    /// Describes what "automatic" would resolve to without the override.
    private var automaticDescription: String {
        var ref = model.ref
        ref.accountOverride = nil
        let automatic = app.resolveAccount(for: ref)
        guard let account = automatic.account else { return "Automatic (none)" }
        return "Automatic: \(account.title) (\(automatic.explanation.lowercased()))"
    }
}

struct AvatarView: View {
    let account: Account
    var size: CGFloat = 20

    var body: some View {
        AsyncImage(url: account.avatarURL.map { URL(string: $0.absoluteString + "&s=\(Int(size * 3))") ?? $0 }) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Text(account.login.prefix(1).uppercased())
                .font(.system(size: size * 0.5, weight: .semibold))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.tint.opacity(0.25))
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

/// The repository's sections. These live under the toolbar, because in the toolbar they pushed
/// the account, branch and sync controls into its overflow menu.
private struct RepoTabBar: View {
    @Binding var selection: RepoView.Tab
    let count: (RepoView.Tab) -> Int
    @Namespace private var underline

    var body: some View {
        HStack(spacing: 2) {
            ForEach(RepoView.Tab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.snappy(duration: 0.2)) { selection = tab }
                } label: {
                    label(for: tab)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .background(Theme.panel)
    }

    private func label(for tab: RepoView.Tab) -> some View {
        let selected = tab == selection
        return HStack(spacing: 5) {
            Image(systemName: tab.icon).font(.caption)
            Text(tab.rawValue).font(.callout.weight(selected ? .semibold : .regular))
            if count(tab) > 0 {
                Text("\(count(tab))")
                    .font(.caption2.monospacedDigit().weight(.medium))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background((selected ? Theme.accent : Color.secondary).opacity(0.16), in: Capsule())
            }
        }
        .lineLimit(1)
        .foregroundStyle(selected ? Theme.accent : .secondary)
        .padding(.horizontal, 10)
        .frame(height: 34)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            if selected {
                Rectangle().fill(Theme.accent).frame(height: 2)
                    .matchedGeometryEffect(id: "underline", in: underline)
            }
        }
    }
}

/// The strip along the bottom of the window: where HEAD is and how it relates to the remote.
private struct RepoStatusBar: View {
    let model: RepoModel

    private var changes: Int {
        model.status.staged.count + model.status.unstaged.count + model.status.conflicted.count
    }

    var body: some View {
        let status = model.status
        HStack(spacing: 14) {
            HStack(spacing: 5) {
                Circle().fill(Theme.head).frame(width: 7, height: 7)
                Text(status.branch ?? "detached HEAD").foregroundStyle(.primary)
            }
            if let upstream = status.upstream {
                Text(upstream).foregroundStyle(.tertiary)
                if status.behind > 0 { Text("↓\(status.behind)").foregroundStyle(Theme.modified) }
                if status.ahead > 0 { Text("↑\(status.ahead)").foregroundStyle(Theme.accent) }
            } else {
                Text("no upstream").foregroundStyle(.tertiary)
            }
            Spacer(minLength: 8)
            if let activity = model.activity {
                Text(activity)
            } else if !status.conflicted.isEmpty {
                Text("\(status.conflicted.count) conflicted").foregroundStyle(Theme.conflict)
            } else if changes > 0 {
                Text("\(changes) changed").foregroundStyle(Theme.modified)
            } else {
                Text("clean").foregroundStyle(Theme.added)
            }
            if let oid = status.oid {
                Text(oid.prefix(7)).foregroundStyle(.tertiary)
            }
        }
        .font(.caption.monospaced())
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 12)
        .frame(height: 24)
        .background(Theme.panel)
    }
}

/// Explains that GitButler owns the checked-out branch and offers a way out.
private struct GitButlerBanner: View {
    let model: RepoModel

    private var gitButlerApp: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.gitbutler.app")
            ?? ["/Applications/GitButler.app"].map(URL.init(fileURLWithPath:))
                .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up.fill").foregroundStyle(Theme.conflict).font(.title3)
            VStack(alignment: .leading, spacing: 1) {
                Text("Managed by GitButler").font(.headline)
                Text("“\(model.status.branch ?? "")” is GitButler's workspace branch. Push and pull from GitButler, or switch to one of your branches to use GitOS.")
                    .font(.callout).foregroundStyle(.secondary)
                    // A fixed vertical size here made the window's minimum height enormous (text wrapped
                    // word-by-word at the narrowest layout), pushing all content off-screen.
                    .lineLimit(2)
                    .help("GitOS won't pull, push or publish GitButler's workspace branch.")
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            if let app = gitButlerApp {
                Button("Open GitButler") {
                    NSWorkspace.shared.open([model.repo.url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
                }
            }
            Menu("Switch Branch") {
                ForEach(model.branches.filter { !$0.isCurrent && !$0.name.hasPrefix("gitbutler/") }) { branch in
                    Button(branch.upstream.map { "\(branch.name)  →  \($0)" } ?? branch.name) {
                        Task { await model.switchBranch(branch.name) }
                    }
                }
            }
            .fixedSize()
            .disabled(model.isBusy)
            .help(model.status.hasChanges ? "Switching may fail while there are uncommitted changes" : "Leave GitButler's workspace")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Theme.conflict.opacity(0.1))
    }
}
