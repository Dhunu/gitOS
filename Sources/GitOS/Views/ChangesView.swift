import SwiftUI

struct ChangesView: View {
    @Bindable var model: RepoModel
    @State private var pendingDiscard: FileChange?

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                fileList
                Divider()
                CommitBox(model: model)
            }
            .frame(minWidth: 280, idealWidth: 340, maxWidth: 520)

            diffPane
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .confirmationDialog(
            "Discard changes to \(pendingDiscard?.fileName ?? "")?",
            isPresented: Binding(get: { pendingDiscard != nil }, set: { if !$0 { pendingDiscard = nil } }),
            presenting: pendingDiscard
        ) { change in
            Button("Discard Changes", role: .destructive) { Task { await model.discard(change) } }
        } message: { change in
            Text(change.kind == .untracked ? "The file will be moved to the Trash." : "This can't be undone.")
        }
    }

    private var fileList: some View {
        let status = model.status
        return List(selection: $model.selectedChangeID) {
            if !status.conflicted.isEmpty {
                Section("Conflicts") {
                    ForEach(status.conflicted) { row($0) }
                }
            }
            Section {
                ForEach(status.staged) { row($0) }
            } header: {
                sectionHeader("Staged", count: status.staged.count, action: "Unstage All") {
                    Task { await model.unstage(status.staged) }
                }
            }
            Section {
                ForEach(status.unstaged) { row($0) }
            } header: {
                sectionHeader("Changes", count: status.unstaged.count, action: "Stage All") {
                    Task { await model.stage(status.unstaged) }
                }
            }
        }
        .overlay {
            if !status.hasChanges {
                ContentUnavailableView("No Local Changes", systemImage: "checkmark.circle",
                                       description: Text("Working tree is clean."))
            }
        }
    }

    private func sectionHeader(_ title: String, count: Int, action: String, perform: @escaping () -> Void) -> some View {
        HStack {
            Text("\(title) (\(count))")
            Spacer()
            if count > 0 {
                Button(action, action: perform)
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
        }
    }

    private func row(_ change: FileChange) -> some View {
        FileChangeRow(change: change) {
            Task { await model.toggleStage(change) }
        }
        .tag(change.id)
        .contextMenu {
            if change.area == .staged {
                Button("Unstage") { Task { await model.unstage([change]) } }
            } else {
                Button(change.area == .conflicted ? "Mark Resolved" : "Stage") { Task { await model.stage([change]) } }
            }
            if change.area == .unstaged {
                Button("Discard Changes…", role: .destructive) { pendingDiscard = change }
            }
            Divider()
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([model.repo.url.appendingPathComponent(change.path)])
            }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(change.path, forType: .string)
            }
        }
    }

    @ViewBuilder
    private var diffPane: some View {
        if let change = model.selectedChange {
            VStack(spacing: 0) {
                HStack {
                    Text(change.path).font(.headline).lineLimit(1).truncationMode(.middle)
                    if let original = change.originalPath {
                        Text("← \(original)").foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Text(change.area == .staged ? "Staged" : change.area == .conflicted ? "Conflicted" : "Unstaged")
                        .font(.caption)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                Divider()
                if let diff = model.currentDiff {
                    ScrollView {
                        DiffContentView(diff: diff, hunkActions: hunkActions(for: change, diff: diff))
                            .padding(.bottom, 12)
                    }
                } else {
                    ContentUnavailableView("No Diff", systemImage: "doc.text.magnifyingglass",
                                           description: Text("Nothing to show for this file."))
                }
            }
        } else {
            ContentUnavailableView("Select a File", systemImage: "doc.text",
                                   description: Text("Pick a changed file to see its diff."))
        }
    }

    private func hunkActions(for change: FileChange, diff: FileDiff) -> [HunkActionButton] {
        switch change.area {
        case .staged:
            [HunkActionButton(title: "Unstage Hunk", icon: "minus.circle") { hunk in
                Task { await model.apply(.unstage, hunk: hunk, in: diff) }
            }]
        case .unstaged where change.kind != .untracked:
            [HunkActionButton(title: "Discard Hunk", icon: "trash", destructive: true) { hunk in
                Task { await model.apply(.discard, hunk: hunk, in: diff) }
            },
             HunkActionButton(title: "Stage Hunk", icon: "plus.circle") { hunk in
                Task { await model.apply(.stage, hunk: hunk, in: diff) }
            }]
        default:
            []
        }
    }
}

struct FileChangeRow: View {
    let change: FileChange
    let toggle: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Text(change.kind.letter)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: 16, height: 16)
                .background(change.kind.color, in: RoundedRectangle(cornerRadius: 4))
            VStack(alignment: .leading, spacing: 0) {
                Text(change.fileName).lineLimit(1)
                if !change.directory.isEmpty {
                    Text(change.directory)
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.head)
                }
            }
            Spacer(minLength: 0)
            if hovering && change.area != .conflicted {
                Button(action: toggle) {
                    Image(systemName: change.area == .staged ? "minus.circle.fill" : "plus.circle.fill")
                }
                .buttonStyle(.borderless)
                .help(change.area == .staged ? "Unstage" : "Stage")
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2, perform: toggle)
    }
}

extension FileChangeKind {
    var color: Color {
        switch self {
        case .added, .untracked: .green
        case .modified, .typeChanged: .orange
        case .deleted: .red
        case .renamed, .copied: .blue
        case .conflicted: .purple
        }
    }
}

struct CommitBox: View {
    @Bindable var model: RepoModel
    @FocusState private var summaryFocused: Bool

    var body: some View {
        let resolved = model.resolved
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if let account = resolved.account {
                    AvatarView(account: account, size: 16)
                    Text("\(account.commitName) <\(account.commitEmail)>")
                        .lineLimit(1).truncationMode(.middle)
                    if account.signing?.key.isEmpty == false {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(.green).help("Commits will be signed")
                    }
                } else {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                    Text("No account. Using global git identity")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .help(resolved.explanation)

            TextField("Summary (required)", text: $model.summary)
                .textFieldStyle(.roundedBorder)
                .focused($summaryFocused)

            TextEditor(text: $model.details)
                .font(.body)
                .frame(height: 64)
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(.background, in: RoundedRectangle(cornerRadius: 6))
                .overlay(alignment: .topLeading) {
                    if model.details.isEmpty {
                        Text("Description")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .allowsHitTesting(false)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))

            Button {
                Task { await model.commit() }
            } label: {
                Text(commitTitle).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!canCommit)
        }
        .padding(12)
    }

    private var canCommit: Bool {
        !model.summary.trimmingCharacters(in: .whitespaces).isEmpty
            && !model.status.staged.isEmpty
            && model.status.conflicted.isEmpty
            && !model.isBusy
    }

    private var commitTitle: String {
        let count = model.status.staged.count
        let files = count == 1 ? "1 file" : "\(count) files"
        return "Commit \(files) to \(model.status.branch ?? "HEAD")"
    }
}
