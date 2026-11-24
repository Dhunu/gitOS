import SwiftUI

struct IssuesView: View {
    @Bindable var model: RepoModel
    /// Called after an issue reference is added to the commit message, so the caller can show the commit box.
    let onReference: () -> Void
    @State private var selection: Int?
    @State private var search = ""
    @State private var showingNew = false
    @State private var scope = ItemScope.open
    @Environment(\.focusMode) private var focusMode

    private var shown: [GitHubRepoAPI.Issue] { scope == .open ? model.issues : model.closedIssues }

    private var filtered: [GitHubRepoAPI.Issue] {
        guard !search.isEmpty else { return shown }
        return shown.filter { $0.title.localizedCaseInsensitiveContains(search) || "#\($0.number)".hasPrefix(search) }
    }

    private var selectedIssue: GitHubRepoAPI.Issue? {
        shown.first { $0.number == selection }
    }

    /// Focus mode hides the issue list, but only while an issue is selected.
    private var listHidden: Bool { focusMode.wrappedValue && selectedIssue != nil }

    var body: some View {
        if let reason = model.githubUnavailableReason {
            GitHubUnavailableView(title: "Issues Unavailable", systemImage: "smallcircle.filled.circle", reason: reason, model: model)
        } else {
            HSplitView {
                if !listHidden {
                    list
                }

                detail.frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
            }
            .sidebarInsetAsPadding()
            .task { await model.loadGitHub() }
            .task(id: scope) { if scope == .closed { await model.loadClosedIssues() } }
            .sheet(isPresented: $showingNew) {
                NewIssueSheet(model: model) { selection = $0.number }
                    .flatPresentation()
            }
        }
    }

    private var list: some View {
        List(filtered, selection: $selection) { issue in
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .top) {
                    Image(systemName: IssueState(issue).systemImage).foregroundStyle(IssueState(issue).color)
                    Text(issue.title).lineLimit(2)
                }
                HStack(spacing: 4) {
                    Text("#\(issue.number)")
                    Text("·")
                    Text(issue.user.login)
                    if let closed = issue.closedAt {
                        Text("·")
                        Text("closed \(closed.formatted(.relative(presentation: .named)))")
                    }
                    if issue.comments > 0 {
                        Label("\(issue.comments)", systemImage: "bubble.left")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
                if !issue.labels.isEmpty {
                    HStack(spacing: 3) { ForEach(issue.labels.prefix(4), id: \.name) { LabelChip(label: $0) } }
                }
            }
            .padding(.vertical, 3)
            .tag(issue.number)
            .contextMenu {
                Button("Reference in Commit Message") { reference(issue, closes: false) }
                if issue.isOpen {
                    Button("Close with Next Commit") { reference(issue, closes: true) }
                }
                Button("Open on GitHub") { NSWorkspace.shared.open(issue.htmlURL) }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 8) {
                Picker("Show", selection: $scope) {
                    Text("Open").tag(ItemScope.open)
                    Text("Closed").tag(ItemScope.closed)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: scope) { selection = nil }
                HStack {
                    TextField("Filter issues", text: $search).textFieldStyle(.roundedBorder)
                    Button("New Issue…", systemImage: "plus") { showingNew = true }
                    Button("Reload", systemImage: "arrow.clockwise") {
                        Task {
                            if scope == .closed { await model.loadClosedIssues(force: true) } else { await model.loadGitHub(force: true) }
                            if let selection { await model.loadComments(for: selection, force: true) }
                        }
                    }
                    .labelStyle(.iconOnly)
                }
            }
            .padding(8)
            .background(Theme.panel)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if scope == .open && !model.allIssuesLoaded {
                ListLimitNotice(url: model.gitHubPage("issues"))
            } else if scope == .closed && !model.allClosedIssuesLoaded {
                ListLimitNotice(url: model.gitHubPage("issues?q=is%3Aissue+is%3Aclosed"))
            }
        }
        .overlay {
            if shown.isEmpty {
                ContentUnavailableView(scope == .open ? "No Open Issues" : "No Closed Issues", systemImage: "checkmark.circle",
                                       description: Text(model.githubError ?? ""))
            }
        }
        .canvasList()
        .frame(minWidth: 300, idealWidth: 380, maxWidth: 560)
    }

    @ViewBuilder
    private var detail: some View {
        if let issue = selectedIssue {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(issue.title).font(.title2.weight(.semibold)).textSelection(.enabled)
                        Text("#\(issue.number)").font(.title2).foregroundStyle(.secondary)
                        Spacer()
                        FocusModeButton()
                    }
                    IssueFacts(issue: issue)
                    HStack {
                        if issue.isOpen {
                            Button("Close with Next Commit", systemImage: "checkmark.circle") { reference(issue, closes: true) }
                                .prominentButton()
                                .help("Adds “Fixes #\(issue.number)” to the commit message")
                        }
                        Button("Reference", systemImage: "number") { reference(issue, closes: false) }
                        Button("Open on GitHub", systemImage: "safari") { NSWorkspace.shared.open(issue.htmlURL) }
                    }
                    Divider()
                    if let body = issue.body, !body.isEmpty {
                        Text(markdown(body)).textSelection(.enabled)
                    } else {
                        Text("No description provided.").foregroundStyle(.secondary).italic()
                    }
                    CommentsSection(model: model, number: issue.number)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .task(id: issue.number) { await model.loadComments(for: issue.number) }
        } else {
            ContentUnavailableView("Select an Issue", systemImage: "smallcircle.filled.circle")
        }
    }

    private func reference(_ issue: GitHubRepoAPI.Issue, closes: Bool) {
        let line = closes ? "Fixes #\(issue.number)" : "Refs #\(issue.number)"
        guard !model.details.contains(line) else { onReference(); return }
        model.details = model.details.isEmpty ? line : model.details + "\n\n" + line
        if model.summary.isEmpty && closes { model.summary = issue.title }
        onReference()
    }
}

private struct NewIssueSheet: View {
    let model: RepoModel
    let onCreated: (GitHubRepoAPI.Issue) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var bodyText = ""
    @State private var working = false
    @State private var error: String?

    var body: some View {
        Form {
            TextField("Title", text: $title)
            Section("Description (Markdown)") {
                TextEditor(text: $bodyText).font(.body.monospaced()).frame(minHeight: 160)
            }
            if let error { Text(error).foregroundStyle(Theme.removed) }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 400)
        .navigationTitle("New Issue")
        .sheetActions(cancel: { dismiss() }) {
            Button(Account.titled("Create Issue", as: model.resolved.account?.login)) {
                working = true
                Task {
                    do {
                        let issue = try await model.createIssue(title: title, body: bodyText)
                        onCreated(issue)
                        dismiss()
                    } catch {
                        self.error = error.localizedDescription
                    }
                    working = false
                }
            }
            .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || working)
            .prominentButton()
        }
    }
}

/// Says a GitHub list was cut off, rather than letting it look complete.
struct ListLimitNotice: View {
    let url: URL?

    var body: some View {
        HStack(spacing: 6) {
            Text("Showing the \(PagedList<Int>.maxItems) most recently updated.")
            if let url { Link("See all on GitHub", destination: url) }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Theme.panel)
    }
}

/// An issue's state, as GitHub shows it.
enum IssueState: Equatable {
    case open, completed, notPlanned

    init(_ issue: GitHubRepoAPI.Issue) {
        self = issue.isOpen ? .open : issue.stateReason == "not_planned" ? .notPlanned : .completed
    }

    var title: String {
        switch self {
        case .open: "Open"
        case .completed: "Closed as completed"
        case .notPlanned: "Closed as not planned"
        }
    }

    var systemImage: String {
        switch self {
        case .open: "smallcircle.filled.circle"
        case .completed: "checkmark.circle"
        case .notPlanned: "slash.circle"
        }
    }

    var color: Color {
        switch self {
        case .open: Theme.added
        case .completed: .purple
        case .notPlanned: .secondary
        }
    }
}

/// State, dates, assignees, milestone and labels under an issue's title.
private struct IssueFacts: View {
    let issue: GitHubRepoAPI.Issue

    var body: some View {
        let state = IssueState(issue)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Label(state.title, systemImage: state.systemImage)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(state.color.opacity(0.18), in: Capsule())
                    .foregroundStyle(state.color)
                Text("Opened by \(issue.user.login) \(issue.createdAt.formatted(.relative(presentation: .named)))")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if let closed = issue.closedAt {
                Text("Closed \(closed.formatted(date: .abbreviated, time: .shortened))")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if let assignees = issue.assignees, !assignees.isEmpty {
                Label("Assigned to \(assignees.map(\.login).formatted(.list(type: .and)))", systemImage: "person")
                    .font(.callout)
            }
            if let milestone = issue.milestone {
                Label("Milestone: \(milestone.title)", systemImage: "flag").font(.callout)
            }
            if !issue.labels.isEmpty {
                HStack(spacing: 3) { ForEach(issue.labels, id: \.name) { LabelChip(label: $0) } }
            }
        }
    }
}
