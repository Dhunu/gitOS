import SwiftUI

struct StashesView: View {
    @Bindable var model: RepoModel
    @State private var showingStashPrompt = false
    @State private var stashMessage = ""
    @State private var pendingDrop: Stash?
    @Environment(\.focusMode) private var focusMode

    private var selectedStash: Stash? {
        model.stashes.first { $0.id == model.selectedStashID }
    }

    /// Focus mode hides the stash list, but only while a stash is selected.
    private var listHidden: Bool { focusMode.wrappedValue && selectedStash != nil }

    var body: some View {
        HSplitView {
            if !listHidden {
                list
            }

            detail
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .sidebarInsetAsPadding()
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

    private var list: some View {
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
    }

    @ViewBuilder
    private var detail: some View {
        if let stash = selectedStash {
            VStack(spacing: 0) {
                HStack {
                    Text(stash.message).font(.headline).lineLimit(1)
                    Spacer()
                    Group {
                        Button("Apply") { Task { await model.applyStash(stash, pop: false) } }
                        Button("Pop") { Task { await model.applyStash(stash, pop: true) } }
                            .prominentButton()
                    }
                    .disabled(model.isBusy)
                    FocusModeButton()
                }
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
