import SwiftUI

/// A row in the branch picker: a local branch, or a remote one not checked out yet.
enum BranchChoice: Identifiable, Hashable {
    case local(Branch)
    case remote(RemoteBranch)

    var id: String {
        switch self {
        case .local(let branch): "local:\(branch.name)"
        case .remote(let branch): "remote:\(branch.ref)"
        }
    }

    var name: String {
        switch self {
        case .local(let branch): branch.name
        case .remote(let branch): branch.name
        }
    }

    var isCurrent: Bool {
        if case .local(let branch) = self { return branch.isCurrent }
        return false
    }

    /// Case-insensitive; every word in `query` must appear somewhere in the name.
    static func matches(_ name: String, query: String) -> Bool {
        query.split(whereSeparator: \.isWhitespace).allSatisfy { name.localizedCaseInsensitiveContains($0) }
    }
}

/// Toolbar button that opens the searchable branch list. Menus can't hold a search field.
struct BranchPicker: View {
    @Bindable var model: RepoModel
    let onNewBranch: () -> Void
    @State private var isOpen = false

    var body: some View {
        Button { isOpen.toggle() } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.triangle.branch")
                Text(model.status.branch ?? "detached").lineLimit(1)
                Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
            }
        }
        .help("Switch branches")
        .background {
            Button("New Branch") { onNewBranch() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            BranchPickerContent(model: model, close: { isOpen = false }, onNewBranch: {
                isOpen = false
                onNewBranch()
            })
        }
    }
}

private struct BranchPickerContent: View {
    @Bindable var model: RepoModel
    let close: () -> Void
    let onNewBranch: () -> Void

    @State private var query = ""
    @State private var highlighted: BranchChoice?
    @FocusState private var searchFocused: Bool

    private var local: [BranchChoice] {
        model.branches
            .filter { BranchChoice.matches($0.name, query: query) }
            .sorted { $0.isCurrent && !$1.isCurrent }
            .map(BranchChoice.local)
    }

    private var remote: [BranchChoice] {
        model.remoteBranches
            .filter { BranchChoice.matches($0.ref, query: query) }
            .map(BranchChoice.remote)
    }

    /// The rows the arrow keys move through.
    private var selectable: [BranchChoice] {
        (local + remote).filter { !$0.isCurrent }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            list
            Divider()
            footer
        }
        .frame(width: 340)
        .onAppear {
            searchFocused = true
            highlighted = selectable.first
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search branches", text: $query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onSubmit { if let highlighted { choose(highlighted) } }
                .onKeyPress(.downArrow) { moveHighlight(by: 1) }
                .onKeyPress(.upArrow) { moveHighlight(by: -1) }
                .onChange(of: query) { highlighted = selectable.first }
            if !query.isEmpty {
                Button("Clear", systemImage: "xmark.circle.fill") { query = "" }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    section("Local", local)
                    section("Remote", remote)
                    if local.isEmpty && remote.isEmpty {
                        Text(query.isEmpty ? "No branches yet" : "No branches match “\(query)”")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 80)
                    }
                }
                .padding(6)
            }
            .frame(height: 340)
            .onChange(of: highlighted) { _, choice in
                if let choice { proxy.scrollTo(choice.id) }
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ choices: [BranchChoice]) -> some View {
        if !choices.isEmpty {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.top, 6).padding(.bottom, 2)
            ForEach(choices) { choice in
                BranchRow(choice: choice, isHighlighted: choice == highlighted)
                    .id(choice.id)
                    .onTapGesture { if !choice.isCurrent { choose(choice) } }
                    .onHover { if $0, !choice.isCurrent { highlighted = choice } }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Menu("Merge into \(model.status.branch ?? "HEAD")") {
                ForEach(model.branches.filter { !$0.isCurrent }) { branch in
                    Button(branch.name) { merge(branch.name) }
                }
                if !model.remoteBranches.isEmpty {
                    Section("Remote") {
                        ForEach(model.remoteBranches) { branch in
                            Button(branch.ref) { merge(branch.ref) }
                        }
                    }
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(model.status.hasChanges || model.status.branch == nil)
            Spacer(minLength: 8)
            Button("New Branch…", action: onNewBranch)
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private func merge(_ ref: String) {
        close()
        Task { await model.merge(ref) }
    }

    private func moveHighlight(by offset: Int) -> KeyPress.Result {
        let rows = selectable
        guard !rows.isEmpty else { return .handled }
        let index = highlighted.flatMap(rows.firstIndex(of:)) ?? -offset
        highlighted = rows[min(max(index + offset, 0), rows.count - 1)]
        return .handled
    }

    private func choose(_ choice: BranchChoice) {
        close()
        Task {
            switch choice {
            case .local(let branch): await model.switchBranch(branch.name)
            case .remote(let branch): await model.checkOut(branch)
            }
        }
    }
}

private struct BranchRow: View {
    let choice: BranchChoice
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .opacity(choice.isCurrent ? 1 : 0)
            Text(choice.name).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            if case .remote(let branch) = choice {
                Text(branch.remote).font(.caption).foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(choice.isCurrent ? .secondary : .primary)
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(isHighlighted ? Theme.accent.opacity(0.22) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
    }
}
