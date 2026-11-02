import SwiftUI

struct RepoView: View {
    @Environment(AppState.self) private var app
    @State var model: RepoModel
    @State private var tab: Tab = .changes
    @State private var newBranchName = ""
    @State private var showingNewBranch = false
    @State private var watcher: RepoWatcher?

    enum Tab: String, CaseIterable {
        case changes = "Changes", history = "History", stashes = "Stashes", worktrees = "Worktrees"
    }

    var body: some View {
        Group {
            switch tab {
            case .changes: ChangesView(model: model)
            case .history: HistoryView(model: model)
            case .stashes: StashesView(model: model)
            case .worktrees: WorktreesView(model: model)
            }
        }
        .navigationTitle(model.ref.name)
        .navigationSubtitle(model.status.branch ?? "detached HEAD")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { tab in
                        Text(title(for: tab))
                    }
                }
                .pickerStyle(.segmented)
            }
            ToolbarItem { AccountMenu(model: model) }
            ToolbarItem { branchMenu }
            ToolbarItem { syncButton }
        }
        .task {
            await model.refresh()
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

    private func title(for tab: Tab) -> String {
        let count = switch tab {
        case .changes: model.status.staged.count + model.status.unstaged.count + model.status.conflicted.count
        case .stashes: model.stashes.count
        case .worktrees: max(model.worktrees.count - 1, 0)
        case .history: 0
        }
        return count > 0 ? "\(tab.rawValue) (\(count))" : tab.rawValue
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
        .disabled(model.isBusy || model.remotes.isEmpty)
        .help(model.remotes.isEmpty ? "This repository has no remote" : "Fetch, pull or push")
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
