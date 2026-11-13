import SwiftUI

struct ChangesView: View {
    @Bindable var model: RepoModel
    @State private var pendingDiscard: FileChange?
    @State private var lineSelection: Set<DiffLineID> = []
    @Environment(\.focusMode) private var focusMode

    /// Focus mode hides the file list, but only while a file is selected — otherwise
    /// there would be nothing to look at and no way to pick a file.
    private var listHidden: Bool { focusMode.wrappedValue && model.selectedChange != nil }

    var body: some View {
        HSplitView {
            if !listHidden {
                VStack(spacing: 0) {
                    fileList
                    Divider()
                    CommitBox(model: model)
                        .background(Theme.isFlat ? Theme.canvas : Theme.panel)
                }
                .frame(minWidth: 280, idealWidth: 340, maxWidth: 520)
            }

            diffPane
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaInset(edge: .bottom, spacing: 0) { reviewInset }
        }
        .sidebarInsetAsPadding()
        .onChange(of: model.currentDiff) { lineSelection = [] }
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
        .canvasList()
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

    /// Shows the inline AI review of the pending changes under the diff, once one ran.
    @ViewBuilder
    private var reviewInset: some View {
        if Licensing.shared.isPro,
           model.reviewState.reviews[.workingTree] != nil || model.reviewState.errors[.workingTree] != nil {
            ScrollView {
                ReviewPanel(model: model, target: .workingTree) { finding in
                    let all = model.status.conflicted + model.status.unstaged + model.status.staged
                    if let change = all.first(where: { $0.path == finding.file }) {
                        model.selectedChangeID = change.id
                    }
                }
                .padding(10)
            }
            .frame(maxHeight: 280)
            .fixedSize(horizontal: false, vertical: true)
            .background(Theme.panel.opacity(0.6))
        }
    }

    private func row(_ change: FileChange) -> some View {
        HStack(spacing: 4) {
            FileChangeRow(change: change) {
                Task { await model.toggleStage(change) }
            }
            if let severity = model.workingTreeFindingSeverity(for: change.path) {
                Circle()
                    .fill(severity == .blocker ? Theme.removed : Theme.modified)
                    .frame(width: 7, height: 7)
                    .help("The AI review flagged this file")
            }
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
        if let change = model.selectedChange, change.area == .conflicted {
            Group {
                if Licensing.shared.isPro {
                    ConflictEditorView(model: model, change: change)
                } else {
                    WholeFileConflictView(model: model, change: change)
                }
            }
            .id(change.id)
        } else if let change = model.selectedChange {
            VStack(spacing: 0) {
                HStack {
                    Text(change.path).font(.headline).lineLimit(1).truncationMode(.middle)
                    if let original = change.originalPath {
                        Text("← \(original)").foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Pill(text: change.area == .staged ? "staged" : change.area == .conflicted ? "conflicted" : "unstaged",
                         tint: change.area == .staged ? Theme.added : change.area == .conflicted ? Theme.conflict : Theme.modified)
                    FocusModeButton()
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Theme.isFlat ? Theme.canvas : Theme.panel)
                Divider()
                if let diff = model.currentDiff {
                    ScrollView {
                        DiffContentView(diff: diff, hunkActions: hunkActions(for: change, diff: diff), selection: $lineSelection)
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
            [HunkActionButton(title: "Unstage", icon: "minus.circle") { hunk, lines in
                Task { await model.apply(.unstage, hunk: hunk, lines: lines, in: diff) }
            }]
        case .unstaged where change.kind != .untracked:
            [HunkActionButton(title: "Discard", icon: "trash", destructive: true) { hunk, lines in
                Task { await model.apply(.discard, hunk: hunk, lines: lines, in: diff) }
            },
             HunkActionButton(title: "Stage", icon: "plus.circle") { hunk, lines in
                Task { await model.apply(.stage, hunk: hunk, lines: lines, in: diff) }
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
        if Theme.isFlat { flatBody } else { glassBody }
    }

    /// Flat style, as on the GitOS website: a stage checkbox, the full path, the kind on the right.
    private var flatBody: some View {
        HStack(spacing: 9) {
            if change.area != .conflicted {
                Button(action: toggle) {
                    let staged = change.area == .staged
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(staged ? Theme.canvas : .clear)
                        .frame(width: 15, height: 15)
                        .background(staged ? Theme.accent : .clear, in: RoundedRectangle(cornerRadius: 4))
                        .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(staged ? .clear : Theme.chipBorder) }
                }
                .buttonStyle(.plain)
                .help(change.area == .staged ? "Unstage" : "Stage")
                .accessibilityLabel(change.area == .staged ? "Unstage \(change.path)" : "Stage \(change.path)")
            }
            Text(change.path)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1).truncationMode(.head)
            Spacer(minLength: 0)
            Text(change.kind.letter)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(change.kind.color)
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(change.kind.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 4))
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: toggle)
    }

    private var glassBody: some View {
        HStack(spacing: 8) {
            Text(change.kind.letter)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(change.kind.color)
                .frame(width: 16, height: 16)
                .background(change.kind.color.opacity(0.16), in: RoundedRectangle(cornerRadius: 4))
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
        case .added, .untracked: Theme.added
        case .modified, .typeChanged: Theme.modified
        case .deleted: Theme.removed
        case .renamed, .copied: Theme.renamed
        case .conflicted: Theme.conflict
        }
    }
}

struct CommitBox: View {
    private enum Field { case summary, description }

    /// Git tooling wraps or cuts subjects past this length.
    private static let summaryLimit = 72
    private static let counterAppearsAt = 50

    @Bindable var model: RepoModel
    @FocusState private var focus: Field?
    @State private var addingCoAuthor = false
    @State private var newCoAuthor = ""

    var body: some View {
        VStack(spacing: 10) {
            VStack(spacing: 0) {
                summaryField
                Divider().padding(.horizontal, 12)
                descriptionField
                if !model.coAuthors.isEmpty {
                    CoAuthorChips(model: model).padding(.horizontal, 12).padding(.bottom, 6)
                }
            }
            .background(Theme.isFlat ? Theme.panel : Theme.field, in: RoundedRectangle(cornerRadius: Theme.isFlat ? 9 : 10))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.isFlat ? 9 : 10)
                    .strokeBorder(focus == nil ? AnyShapeStyle(.separator) : AnyShapeStyle(Theme.accent), lineWidth: 1)
            }

            Button {
                Task { await model.commit() }
            } label: {
                commitLabel.frame(maxWidth: .infinity)
            }
            .prominentButton()
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(commitBlocker != nil)
            .help(commitBlocker ?? identityHelp(model.resolved) + "\nCommit (⌘↩)")
        }
        .padding(12)
        .alert("Add Co-author", isPresented: $addingCoAuthor) {
            TextField("Name <email@example.com>", text: $newCoAuthor)
            Button("Add") {
                if let person = Person(parsing: newCoAuthor) {
                    model.extraPeople.insert(person, at: 0)
                    if !model.coAuthors.contains(person) { model.coAuthors.append(person) }
                }
                newCoAuthor = ""
            }
            Button("Cancel", role: .cancel) { newCoAuthor = "" }
        } message: {
            Text("Use their GitHub noreply email so the commit is credited to them.")
        }
    }

    private var summaryField: some View {
        HStack(spacing: 8) {
            TextField("Summary", text: $model.summary, prompt: Text("Summary").foregroundStyle(.tertiary))
                .textFieldStyle(.plain)
                .font(.body.weight(model.summary.isEmpty ? .regular : .medium))
                .focused($focus, equals: .summary)
                .onSubmit { focus = .description }
            if model.summary.count >= Self.counterAppearsAt {
                let isLong = model.summary.count > Self.summaryLimit
                Text("\(model.summary.count)/\(Self.summaryLimit)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(isLong ? AnyShapeStyle(Theme.modified) : AnyShapeStyle(.tertiary))
                    .help(isLong ? "Summaries over \(Self.summaryLimit) characters get cut off in git logs and on GitHub" : "")
            }
            aiButton
            moreMenu
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
    }

    /// Grows with its text up to a limit, then scrolls.
    private var descriptionField: some View {
        Text(model.details.isEmpty ? " " : model.details + "\n")
            .font(.body)
            .hidden()
            .padding(.horizontal, 5)
            .frame(maxWidth: .infinity, minHeight: 56, maxHeight: 180, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
            .overlay {
                TextEditor(text: $model.details)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .focused($focus, equals: .description)
            }
            .overlay(alignment: .topLeading) {
                if model.details.isEmpty {
                    Text("Add a description")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5)
                        .allowsHitTesting(false)
                }
            }
            .padding(.horizontal, 7).padding(.vertical, 8)
    }

    /// Writes the message from the staged changes. Icon only: it's a helper, not the main action.
    private var aiButton: some View {
        let provider = model.app.preferences.aiProvider
        let hasMessage = !model.summary.isEmpty || !model.details.isEmpty
        return Button {
            guard Licensing.shared.require(.ai) else { return }
            Task { await model.generateCommitMessage() }
        } label: {
            if model.generatingMessage {
                ProgressView().controlSize(.mini)
            } else {
                Image(systemName: "sparkles")
            }
        }
        .buttonStyle(.borderless)
        .disabled(model.generatingMessage || model.status.staged.isEmpty || !provider.isReady)
        .help(aiHelp(provider))
        .accessibilityLabel(hasMessage ? "Rewrite with AI" : "Write with AI")
        .keyboardShortcut("g", modifiers: [.command, .shift])
    }

    /// The less common commit tools, kept out of the way until needed.
    private var moreMenu: some View {
        let provider = model.app.preferences.aiProvider
        let reviewing = model.reviewState.running.contains(.workingTree)
        return Menu {
            Button {
                guard Licensing.shared.require(.ai) else { return }
                Task { await model.runReview(.workingTree) }
            } label: {
                Label(reviewing ? "Reviewing…" : "Review Changes", systemImage: "text.badge.checkmark")
            }
            .disabled(reviewing || !model.status.hasChanges || !provider.isReady)
            if !provider.isReady {
                Text("Add an Anthropic API key in Settings › AI to review")
            }
            Divider()
            Menu {
                CoAuthorItems(model: model) { addingCoAuthor = true }
            } label: {
                Label(model.coAuthors.isEmpty ? "Co-authors" : "Co-authors (\(model.coAuthors.count))", systemImage: "person.2")
            }
        } label: {
            if reviewing {
                ProgressView().controlSize(.mini)
            } else {
                Image(systemName: "ellipsis.circle")
            }
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Review changes, add co-authors")
        .accessibilityLabel("More commit options")
    }

    private func aiHelp(_ provider: AIProvider) -> String {
        if !provider.isReady { return "Add an Anthropic API key in Settings › AI" }
        if model.status.staged.isEmpty { return "Stage some changes first" }
        return "Write the message from the staged changes with \(provider.name) (⌘⇧G)"
    }

    /// "[avatar] Commit 3 files as @login": who commits is part of the action, not a footnote.
    /// Falls back to shorter titles when the column is narrow.
    private var commitLabel: some View {
        let account = model.resolved.account
        let titles = CommitButtonTitle.variants(
            staged: model.status.staged.count, hasChanges: model.status.hasChanges, login: account?.login
        )
        return HStack(spacing: 6) {
            if let account, !model.status.staged.isEmpty {
                AvatarView(account: account, size: 16)
            } else if account == nil, !model.status.staged.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            ViewThatFits(in: .horizontal) {
                ForEach(titles, id: \.self) { Text($0).lineLimit(1) }
            }
        }
    }

    private func identityHelp(_ resolved: ResolvedAccount) -> String {
        guard let account = resolved.account else { return resolved.explanation }
        let signing = account.signing.flatMap { $0.key.isEmpty ? nil : "\nSigned with \($0.format.title)" } ?? ""
        return "\(account.commitName) <\(account.commitEmail)>\n\(resolved.explanation)\(signing)"
    }

    /// Why the commit button is off, or nil when it's ready.
    private var commitBlocker: String? {
        if model.status.staged.isEmpty { return "Stage some changes first" }
        if !model.status.conflicted.isEmpty { return "Resolve the conflicts first" }
        if model.summary.trimmingCharacters(in: .whitespaces).isEmpty { return "Add a summary first" }
        if model.isBusy { return "Waiting for the current git action" }
        return nil
    }

}

/// Titles for the commit button, longest first; the view shows the first that fits.
enum CommitButtonTitle {
    static func variants(staged: Int, hasChanges: Bool, login: String?) -> [String] {
        guard staged > 0 else { return [hasChanges ? "Stage changes to commit" : "Nothing to commit"] }
        let files = staged == 1 ? "1 file" : "\(staged) files"
        guard let login else { return ["Commit \(files) with global git identity", "Commit \(files)", "Commit"] }
        return ["Commit \(files) as @\(login)", "Commit as @\(login)", "Commit"]
    }
}

/// Recent authors to toggle as co-authors, plus a way to add someone new.
private struct CoAuthorItems: View {
    @Bindable var model: RepoModel
    let addSomeone: () -> Void

    var body: some View {
        let people = model.knownPeople.prefix(30)
        if people.isEmpty {
            Text("No recent authors")
        }
        ForEach(Array(people)) { person in
            Toggle(isOn: Binding(
                get: { model.coAuthors.contains(person) },
                set: { on in
                    if on { model.coAuthors.append(person) } else { model.coAuthors.removeAll { $0 == person } }
                }
            )) {
                Text("\(person.name) <\(person.email)>")
            }
        }
        Divider()
        Button("Add Someone Else…", action: addSomeone)
    }
}

private struct CoAuthorChips: View {
    @Bindable var model: RepoModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(model.coAuthors) { person in
                    HStack(spacing: 3) {
                        Text(person.name).lineLimit(1)
                        Button { model.coAuthors.removeAll { $0 == person } } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.borderless)
                    }
                    .font(.caption)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                    .help(person.trailer)
                }
            }
        }
    }
}
