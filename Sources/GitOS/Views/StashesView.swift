import SwiftUI

struct StashesView: View {
    @Bindable var model: RepoModel
    @State private var showingStashPrompt = false
    @State private var stashMessage = ""
    @State private var pendingDrop: Stash?

    var body: some View {
        HSplitView {
            List(model.stashes, selection: $model.selectedStashID) { stash in
                VStack(alignment: .leading, spacing: 2) {
                    Text(stash.message).lineLimit(2)
                    HStack {
                        Text(stash.ref).monospaced()
                        Text("·")
                        Text(stash.date, format: .relative(presentation: .named))
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                .tag(stash.id)
                .contextMenu {
                    Button("Apply") { Task { await model.applyStash(stash, pop: false) } }
                    Button("Pop") { Task { await model.applyStash(stash, pop: true) } }
                    Divider()
                    Button("Drop…", role: .destructive) { pendingDrop = stash }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack {
                    Button("Stash Changes…", systemImage: "tray.and.arrow.down") { showingStashPrompt = true }
                        .disabled(!model.status.hasChanges || model.isBusy)
                    Spacer()
                }
                .padding(8)
                .background(Theme.panel)
            }
            .overlay {
                if model.stashes.isEmpty {
                    ContentUnavailableView("No Stashes", systemImage: "tray",
                                           description: Text("Stash uncommitted work to set it aside."))
                }
            }
            .canvasList()
            .frame(minWidth: 260, idealWidth: 320, maxWidth: 480)

            detail
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .alert("Stash Changes", isPresented: $showingStashPrompt) {
            TextField("Message (optional)", text: $stashMessage)
            Button("Stash") {
                let message = stashMessage
                stashMessage = ""
                Task { await model.stash(message: message) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Staged, unstaged and untracked changes are saved and the working tree is cleaned.")
        }
        .confirmationDialog("Drop \(pendingDrop?.ref ?? "")?",
                            isPresented: Binding(get: { pendingDrop != nil }, set: { if !$0 { pendingDrop = nil } }),
                            presenting: pendingDrop) { stash in
            Button("Drop Stash", role: .destructive) { Task { await model.dropStash(stash) } }
        } message: { _ in
            Text("The stashed changes are deleted.")
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let stash = model.stashes.first(where: { $0.id == model.selectedStashID }) {
            VStack(spacing: 0) {
                HStack {
                    Text(stash.message).font(.headline).lineLimit(1)
                    Spacer()
                    Button("Apply") { Task { await model.applyStash(stash, pop: false) } }
                    Button("Pop") { Task { await model.applyStash(stash, pop: true) } }
                        .buttonStyle(.borderedProminent)
                }
                .disabled(model.isBusy)
                .padding(10)
                Divider()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(model.stashDiffs) { diff in
                            Text(diff.path).font(.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(Theme.panel)
                            DiffContentView(diff: diff)
                        }
                    }
                }
            }
        } else {
            ContentUnavailableView("Select a Stash", systemImage: "tray.full")
        }
    }
}

struct WorktreesView: View {
    @Environment(AppState.self) private var app
    let model: RepoModel
    @State private var showingAdd = false
    @State private var pendingRemoval: Worktree?

    var body: some View {
        List(model.worktrees) { tree in
            HStack(spacing: 10) {
                Image(systemName: tree.isMain ? "folder.fill" : "folder")
                    .foregroundStyle(tree.isMain ? Theme.accent : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(tree.name).font(.headline)
                        if tree.isMain { badge("main") }
                        if tree.isLocked { badge("locked") }
                        if tree.isPrunable { badge("missing") }
                        if tree.path == model.repo.url.path { badge("this window") }
                    }
                    Text(tree.path.abbreviatingWithTildeInPath).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Label(tree.branch ?? "detached \(tree.head?.prefix(7) ?? "")", systemImage: "arrow.triangle.branch")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Open") { Task { await app.addRepository(at: URL(fileURLWithPath: tree.path)) } }
                    .disabled(tree.isPrunable)
            }
            .padding(.vertical, 4)
            .contextMenu {
                Button("Open in GitOS") { Task { await app.addRepository(at: URL(fileURLWithPath: tree.path)) } }
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: tree.path)]) }
                if !tree.isMain {
                    Divider()
                    Button("Remove Worktree…", role: .destructive) { pendingRemoval = tree }
                }
            }
        }
        .canvasList()
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Button("New Worktree…", systemImage: "plus.rectangle.on.folder") { showingAdd = true }
                Spacer()
                Text("Check out several branches side by side, each in its own folder.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(8)
            .background(Theme.panel)
        }
        .sheet(isPresented: $showingAdd) {
            NewWorktreeSheet(model: model)
        }
        .confirmationDialog("Remove worktree \(pendingRemoval?.name ?? "")?",
                            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
                            presenting: pendingRemoval) { tree in
            Button("Remove") { Task { await model.removeWorktree(tree, force: false) } }
            Button("Force Remove (discard its changes)", role: .destructive) { Task { await model.removeWorktree(tree, force: true) } }
        } message: { tree in
            Text("The folder \(tree.path.abbreviatingWithTildeInPath) is deleted. Its branch is kept.")
        }
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(.quaternary, in: Capsule())
    }
}

private struct NewWorktreeSheet: View {
    let model: RepoModel
    @Environment(\.dismiss) private var dismiss
    @State private var createBranch = true
    @State private var branch = ""
    @State private var path = ""

    private var availableBranches: [Branch] {
        let used = Set(model.worktrees.compactMap(\.branch))
        return model.branches.filter { !used.contains($0.name) }
    }

    var body: some View {
        Form {
            Picker("Branch", selection: $createBranch) {
                Text("New branch from HEAD").tag(true)
                Text("Existing branch").tag(false)
            }
            .pickerStyle(.radioGroup)
            if createBranch {
                TextField("Branch name", text: $branch)
            } else {
                Picker("Existing branch", selection: $branch) {
                    Text("Choose…").tag("")
                    ForEach(availableBranches) { Text($0.name).tag($0.name) }
                }
            }
            HStack {
                TextField("Folder", text: $path)
                Button("Choose…") { choose() }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .navigationTitle("New Worktree")
        .onChange(of: branch) { _, name in
            guard !name.isEmpty else { return }
            let repo = model.repo.url
            let safe = name.replacingOccurrences(of: "/", with: "-")
            path = repo.deletingLastPathComponent().appendingPathComponent("\(repo.lastPathComponent)-\(safe)").path
        }
        .onChange(of: createBranch) { branch = "" }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create") {
                    let (path, branch, create) = (path, branch.trimmingCharacters(in: .whitespaces), createBranch)
                    Task { await model.addWorktree(path: path, branch: branch, newBranch: create) }
                    dismiss()
                }
                .disabled(branch.trimmingCharacters(in: .whitespaces).isEmpty || path.isEmpty)
            }
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use Folder"
        panel.directoryURL = model.repo.url.deletingLastPathComponent()
        if panel.runModal() == .OK, let url = panel.url {
            // git creates the final folder itself, so point inside the chosen one.
            let name = branch.isEmpty ? "worktree" : branch.replacingOccurrences(of: "/", with: "-")
            path = url.appendingPathComponent(name).path
        }
    }
}
