import SwiftUI

struct PullRequestsView: View {
    @Bindable var model: RepoModel
    @State private var selection: Int?
    @State private var showingCreate = false
    @State private var triageMode = false
    @State private var scope = ItemScope.open
    @Environment(\.focusMode) private var focusMode

    private var shown: [GitHubRepoAPI.PullRequest] {
        scope == .open ? model.pullRequests : model.closedPullRequests
    }

    private var selectedPR: GitHubRepoAPI.PullRequest? {
        shown.first { $0.number == selection }
    }

    /// Focus mode hides the PR list, but only while a pull request is selected.
    private var listHidden: Bool { focusMode.wrappedValue && selectedPR != nil }

    var body: some View {
        if let reason = model.githubUnavailableReason {
            GitHubUnavailableView(title: "Pull Requests Unavailable", systemImage: "arrow.triangle.pull", reason: reason, model: model)
        } else {
            HSplitView {
                if !listHidden {
                    list
                }

                detail.frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
            }
            .sidebarInsetAsPadding()
            .task { await model.loadGitHub() }
            .task(id: scope) { if scope == .closed { await model.loadClosedPullRequests() } }
            .sheet(isPresented: $showingCreate) {
                CreatePullRequestSheet(model: model) { selection = $0.number }
                    .flatPresentation()
            }
        }
    }

    private var list: some View {
        Group {
            if triageMode && scope == .open {
                TriageList(model: model, selection: $selection)
            } else {
                List(shown, selection: $selection) { pr in
                    PullRequestRow(pr: pr, checks: model.prChecks[pr.number], isCurrent: model.currentPullRequest == pr)
                        .tag(pr.number)
                        .contextMenu {
                            Button("Check Out") { Task { await model.checkout(pr) } }
                            Button("Open on GitHub") { NSWorkspace.shared.open(pr.htmlURL) }
                            Button("Copy Link") { copy(pr.htmlURL.absoluteString) }
                        }
                }
                .overlay {
                    if shown.isEmpty {
                        ContentUnavailableView(scope == .open ? "No Open Pull Requests" : "No Merged or Closed Pull Requests",
                                               systemImage: "arrow.triangle.pull",
                                               description: Text(model.githubError ?? ""))
                    }
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { toolbar }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if scope == .open && !model.allPullRequestsLoaded {
                ListLimitNotice(url: model.gitHubPage("pulls"))
            } else if scope == .closed && !model.allClosedPullRequestsLoaded {
                ListLimitNotice(url: model.gitHubPage("pulls?q=is%3Apr+is%3Aclosed"))
            }
        }
        .canvasList()
        .frame(minWidth: 300, idealWidth: 380, maxWidth: 560)
    }

    private var toolbar: some View {
        VStack(spacing: 8) {
            Picker("Show", selection: $scope) {
                Text("Open").tag(ItemScope.open)
                Text("Merged & Closed").tag(ItemScope.closed)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: scope) { selection = nil }
            toolbarButtons
        }
        .padding(8)
        .background(Theme.panel)
    }

    private var toolbarButtons: some View {
        HStack {
            Button("New Pull Request…", systemImage: "plus") { showingCreate = true }
                .disabled(model.status.branch == nil || model.status.branch == model.defaultBranch || model.currentPullRequest != nil)
                .help(model.currentPullRequest != nil ? "This branch already has an open pull request"
                      : "Open a pull request from \(model.status.branch ?? "this branch")")
            Spacer()
            Toggle("Triage", systemImage: "list.number", isOn: $triageMode)
                .toggleStyle(.button)
                .disabled(scope == .closed)
                .help(scope == .closed ? "Triage works on open pull requests" : "Group duplicate PRs and rank the rest by review-worthiness")
            Button("Reload", systemImage: "arrow.clockwise") {
                Task {
                    if scope == .closed {
                        await model.loadClosedPullRequests(force: true)
                    } else {
                        await model.loadGitHub(force: true)
                        if triageMode { await model.loadTriage(force: true) }
                    }
                    if let selection { await model.loadComments(for: selection, force: true) }
                }
            }
            .labelStyle(.iconOnly)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let pr = selectedPR {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(pr.title).font(.title2.weight(.semibold)).textSelection(.enabled)
                        Text("#\(pr.number)").font(.title2).foregroundStyle(.secondary)
                        Spacer()
                        FocusModeButton()
                    }
                    HStack(spacing: 6) {
                        AsyncImage(url: pr.user.avatarURL) { $0.resizable() } placeholder: { Color.secondary.opacity(0.2) }
                            .frame(width: 18, height: 18).clipShape(Circle())
                        Text(pr.user.login).bold()
                        Text(pr.isMerged ? "merged" : pr.isOpen ? "wants to merge" : "proposed merging")
                        Text(pr.head.ref).monospaced().padding(.horizontal, 4).background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                        Text("into")
                        Text(pr.base.ref).monospaced().padding(.horizontal, 4).background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                        if pr.draft == true { Text("Draft").font(.caption).padding(.horizontal, 6).background(.gray.opacity(0.3), in: Capsule()) }
                    }
                    .font(.callout)
                    ItemStateLine(pr: pr)
                    HStack {
                        Button("Check Out", systemImage: "arrow.down.to.line") { Task { await model.checkout(pr) } }
                            .prominentButton()
                            .disabled(model.isBusy || model.status.hasChanges || !pr.isOpen)
                            .help(!pr.isOpen ? "This pull request is \(pr.isMerged ? "merged" : "closed"); its branch may be gone"
                                  : model.status.hasChanges ? "Commit or stash your changes first" : "Switch to this pull request's branch")
                        Button("Open on GitHub", systemImage: "safari") { NSWorkspace.shared.open(pr.htmlURL) }
                        ReviewButton(model: model, target: .pullRequest(pr.number))
                    }
                    ReviewPanel(model: model, target: .pullRequest(pr.number), pullRequestNumber: pr.number)
                    if let checks = model.prChecks[pr.number], !checks.items.isEmpty {
                        ChecksList(checks: checks)
                    }
                    Divider()
                    if let body = pr.body, !body.isEmpty {
                        Text(markdown(body)).textSelection(.enabled)
                    } else {
                        Text("No description provided.").foregroundStyle(.secondary).italic()
                    }
                    CommentsSection(model: model, number: pr.number)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .task(id: pr.number) { await model.loadComments(for: pr.number) }
        } else {
            ContentUnavailableView("Select a Pull Request", systemImage: "arrow.triangle.pull")
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

func markdown(_ text: String) -> AttributedString {
    (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
        ?? AttributedString(text)
}

private struct PullRequestRow: View {
    let pr: GitHubRepoAPI.PullRequest
    let checks: CheckSummary?
    let isCurrent: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: pr.isMerged ? "arrow.triangle.merge" : pr.isOpen ? "arrow.triangle.pull" : "xmark.circle")
                .foregroundStyle(PullRequestState(pr).color)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(pr.title).lineLimit(2)
                    if isCurrent { Text("current").font(.caption2).padding(.horizontal, 4).background(.tint.opacity(0.2), in: Capsule()) }
                }
                HStack(spacing: 4) {
                    Text("#\(pr.number)")
                    Text("·")
                    Text(pr.user.login)
                    Text("·")
                    if let date = pr.mergedAt ?? pr.closedAt {
                        Text("\(pr.isMerged ? "merged" : "closed") \(date.formatted(.relative(presentation: .named)))")
                    } else {
                        Text(pr.updatedAt, format: .relative(presentation: .named))
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
                if !pr.labels.isEmpty {
                    HStack(spacing: 3) {
                        ForEach(pr.labels.prefix(4), id: \.name) { LabelChip(label: $0) }
                    }
                }
            }
            Spacer()
            if let checks { ChecksBadge(checks: checks) }
        }
        .padding(.vertical, 3)
    }
}

struct LabelChip: View {
    let label: GitHubRepoAPI.Label

    var body: some View {
        Text(label.name)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Color(hex: label.color).opacity(0.35), in: Capsule())
    }
}

struct ChecksBadge: View {
    let checks: CheckSummary

    var body: some View {
        Group {
            switch checks.state {
            case .success: Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.added)
            case .failure: Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.removed)
            case .pending: Image(systemName: "clock.fill").foregroundStyle(Theme.modified)
            case .none: EmptyView()
            }
        }
        .help(checks.description)
    }
}

struct ChecksList: View {
    let checks: CheckSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                ChecksBadge(checks: checks)
                Text("Checks: \(checks.description)").font(.headline)
            }
            ForEach(Array(checks.items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 6) {
                    ChecksBadge(checks: CheckSummary(items: [item]))
                    if let url = item.url {
                        Link(item.name, destination: url)
                    } else {
                        Text(item.name)
                    }
                }
                .font(.callout)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}

extension Color {
    /// GitHub label colors are 6-digit hex without '#'.
    init(hex: String) {
        let value = UInt64(hex, radix: 16) ?? 0x888888
        self.init(red: Double((value >> 16) & 0xff) / 255, green: Double((value >> 8) & 0xff) / 255, blue: Double(value & 0xff) / 255)
    }
}

struct CreatePullRequestSheet: View {
    let model: RepoModel
    let onCreated: (GitHubRepoAPI.PullRequest) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var bodyText = ""
    @State private var base = ""
    @State private var draft = false
    @State private var working: String?
    @State private var error: String?

    private var bases: [String] {
        let remote = model.remoteBranches.filter { $0.remote == model.primaryRemote?.name }
        var names = (model.branches.map(\.name) + remote.map(\.name)).filter { $0 != model.status.branch }
        if let main = model.defaultBranch {
            names.removeAll { $0 == main }
            names.insert(main, at: 0)
        }
        return names
    }

    var body: some View {
        Form {
            Section {
                Picker("Merge \(model.status.branch ?? "") into", selection: $base) {
                    ForEach(bases, id: \.self) { Text($0).tag($0) }
                }
                TextField("Title", text: $title)
                Toggle("Draft", isOn: $draft)
            }
            Section {
                TextEditor(text: $bodyText)
                    .font(.body.monospaced())
                    .frame(minHeight: 180)
            } header: {
                HStack {
                    Text("Description (Markdown)")
                    Spacer()
                    Button("Write with AI", systemImage: "sparkles") { Task { await generate() } }
                        .disabled(!model.app.preferences.aiProvider.isReady || working != nil || base.isEmpty)
                        .help(!model.app.preferences.aiProvider.isReady ? "Add an Anthropic API key in Settings › AI" : "Draft the title and description from this branch's commits and diff")
                }
            }
            if model.status.upstream == nil || model.status.ahead > 0 {
                Text("The branch will be pushed first.").font(.caption).foregroundStyle(.secondary)
            }
            if let error {
                Text(error).foregroundStyle(Theme.removed)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 520)
        .navigationTitle("New Pull Request")
        .sheetActions(cancel: { dismiss() }) {
            HStack {
                if let working { ProgressView().controlSize(.small); Text(working).foregroundStyle(.secondary) }
                Button(Account.titled(draft ? "Create Draft" : "Create Pull Request", as: model.resolved.account?.login)) { Task { await create() } }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || base.isEmpty || working != nil)
                    .prominentButton()
            }
        }
        .task {
            base = bases.first ?? ""
            if let last = model.commits.first, title.isEmpty { title = last.subject }
        }
    }

    private func generate() async {
        working = "Asking Claude…"
        defer { working = nil }
        let commits = await model.commitsAhead(of: base)
        let diff = await model.diffAgainst(base: base)
        do {
            let (t, b) = try await Claude.pullRequest(commits: commits, diff: diff, base: base,
                                                       model: model.app.preferences.aiModel,
                                                       provider: model.app.preferences.aiProvider)
            title = t
            bodyText = b
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func create() async {
        working = "Creating…"
        defer { working = nil }
        do {
            let pr = try await model.createPullRequest(title: title, body: bodyText, base: base, draft: draft)
            onCreated(pr)
            NSWorkspace.shared.open(pr.htmlURL)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Which items a pull request or issue list shows.
enum ItemScope: Hashable { case open, closed }

/// A pull request's state, as GitHub colours it.
enum PullRequestState: Equatable {
    case open, draft, merged, closed

    init(_ pr: GitHubRepoAPI.PullRequest) {
        self = pr.isMerged ? .merged : !pr.isOpen ? .closed : pr.draft == true ? .draft : .open
    }

    var title: String {
        switch self {
        case .open: "Open"
        case .draft: "Draft"
        case .merged: "Merged"
        case .closed: "Closed"
        }
    }

    var color: Color {
        switch self {
        case .open: Theme.added
        case .draft: .secondary
        case .merged: .purple
        case .closed: Theme.removed
        }
    }
}

/// "Merged 3 days ago" / "Closed without merging on …", under a pull request's title.
private struct ItemStateLine: View {
    let pr: GitHubRepoAPI.PullRequest

    var body: some View {
        let state = PullRequestState(pr)
        HStack(spacing: 6) {
            Text(state.title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(state.color.opacity(0.18), in: Capsule())
                .foregroundStyle(state.color)
            Group {
                if let merged = pr.mergedAt {
                    Text("Merged \(merged.formatted(date: .abbreviated, time: .shortened))")
                } else if let closed = pr.closedAt {
                    Text("Closed without merging \(closed.formatted(date: .abbreviated, time: .shortened))")
                } else {
                    Text("Opened \(pr.createdAt.formatted(.relative(presentation: .named)))")
                }
            }
            .font(.callout).foregroundStyle(.secondary)
        }
    }
}

/// The conversation under an issue or pull request: every comment, oldest first.
struct CommentsSection: View {
    let model: RepoModel
    let number: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let comments = model.comments[number] {
                Text(comments.isEmpty ? "No comments" : "\(comments.count) comment\(comments.count == 1 ? "" : "s")")
                    .font(.headline)
                    .padding(.top, 8)
                ForEach(comments) { comment in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            AsyncImage(url: comment.user.avatarURL) { $0.resizable() } placeholder: { Color.secondary.opacity(0.2) }
                                .frame(width: 18, height: 18).clipShape(Circle())
                            Text(comment.user.login).font(.callout.weight(.semibold))
                            Text(comment.createdAt, format: .relative(presentation: .named))
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Open on GitHub", systemImage: "safari") { NSWorkspace.shared.open(comment.htmlURL) }
                                .labelStyle(.iconOnly).buttonStyle(.borderless)
                        }
                        if let body = comment.body, !body.isEmpty {
                            Text(markdown(body)).textSelection(.enabled)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.field, in: RoundedRectangle(cornerRadius: 8))
                }
            } else if let error = model.commentErrors[number] {
                Label("Couldn't load comments: \(error)", systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(Theme.modified)
            } else {
                ProgressView().controlSize(.small).padding(.top, 8)
            }
        }
    }
}
