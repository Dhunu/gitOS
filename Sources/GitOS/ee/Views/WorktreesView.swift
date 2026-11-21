import SwiftUI

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
                .flatPresentation()
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
                    // Git creates a local tracking branch when the name is on one remote.
                    ForEach(model.remoteBranches) { Text($0.ref).tag($0.name) }
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
        .sheetActions(cancel: { dismiss() }) {
            Button("Create") {
                let (path, branch, create) = (path, branch.trimmingCharacters(in: .whitespaces), createBranch)
                Task { await model.addWorktree(path: path, branch: branch, newBranch: create) }
                dismiss()
            }
            .disabled(branch.trimmingCharacters(in: .whitespaces).isEmpty || path.isEmpty)
            .prominentButton()
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
