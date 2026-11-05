import SwiftUI

struct PullRequestsView: View {
    @Bindable var model: RepoModel
    @State private var selection: Int?
    @State private var showingCreate = false

    var body: some View {
        if let reason = model.githubUnavailableReason {
            GitHubUnavailableView(title: "Pull Requests Unavailable", systemImage: "arrow.triangle.pull", reason: reason, model: model)
        } else {
            HSplitView {
                List(model.pullRequests, selection: $selection) { pr in
                    PullRequestRow(pr: pr, checks: model.prChecks[pr.number], isCurrent: model.currentPullRequest == pr)
                        .tag(pr.number)
                        .contextMenu {
                            Button("Check Out") { Task { await model.checkout(pr) } }
                            Button("Open on GitHub") { NSWorkspace.shared.open(pr.htmlURL) }
                            Button("Copy Link") { copy(pr.htmlURL.absoluteString) }
                        }
                }
                .safeAreaInset(edge: .top, spacing: 0) { toolbar }
                .overlay {
                    if model.pullRequests.isEmpty {
                        ContentUnavailableView("No Open Pull Requests", systemImage: "arrow.triangle.pull",
                                               description: Text(model.githubError ?? ""))
                    }
                }
                .canvasList()
                .frame(minWidth: 300, idealWidth: 380, maxWidth: 560)

                detail.frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
            }
            .task { await model.loadGitHub() }
            .sheet(isPresented: $showingCreate) {
                CreatePullRequestSheet(model: model) { selection = $0.number }
            }
        }
    }

    private var toolbar: some View {
        HStack {
            Button("New Pull Request…", systemImage: "plus") { showingCreate = true }
                .disabled(model.status.branch == nil || model.status.branch == model.defaultBranch || model.currentPullRequest != nil)
                .help(model.currentPullRequest != nil ? "This branch already has an open pull request"
                      : "Open a pull request from \(model.status.branch ?? "this branch")")
            Spacer()
            Button("Reload", systemImage: "arrow.clockwise") { Task { await model.loadGitHub(force: true) } }
                .labelStyle(.iconOnly)
        }
        .padding(8)
        .background(Theme.panel)
    }

    @ViewBuilder
    private var detail: some View {
        if let pr = model.pullRequests.first(where: { $0.number == selection }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(pr.title).font(.title2.weight(.semibold)).textSelection(.enabled)
                        Text("#\(pr.number)").font(.title2).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 6) {
                        AsyncImage(url: pr.user.avatarURL) { $0.resizable() } placeholder: { Color.secondary.opacity(0.2) }
                            .frame(width: 18, height: 18).clipShape(Circle())
                        Text(pr.user.login).bold()
                        Text("wants to merge")
                        Text(pr.head.ref).monospaced().padding(.horizontal, 4).background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                        Text("into")
                        Text(pr.base.ref).monospaced().padding(.horizontal, 4).background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                        if pr.draft == true { Text("Draft").font(.caption).padding(.horizontal, 6).background(.gray.opacity(0.3), in: Capsule()) }
                    }
                    .font(.callout)
                    HStack {
                        Button("Check Out", systemImage: "arrow.down.to.line") { Task { await model.checkout(pr) } }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.isBusy || model.status.hasChanges)
                            .help(model.status.hasChanges ? "Commit or stash your changes first" : "Switch to this pull request's branch")
                        Button("Open on GitHub", systemImage: "safari") { NSWorkspace.shared.open(pr.htmlURL) }
                    }
                    if let checks = model.prChecks[pr.number], !checks.items.isEmpty {
                        ChecksList(checks: checks)
                    }
                    Divider()
                    if let body = pr.body, !body.isEmpty {
                        Text(markdown(body)).textSelection(.enabled)
                    } else {
                        Text("No description provided.").foregroundStyle(.secondary).italic()
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
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
            Image(systemName: "arrow.triangle.pull")
                .foregroundStyle(pr.draft == true ? Color.secondary : Theme.added)
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
                    Text(pr.updatedAt, format: .relative(presentation: .named))
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
        var names = model.branches.map(\.name).filter { $0 != model.status.branch }
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
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                HStack {
                    if let working { ProgressView().controlSize(.small); Text(working).foregroundStyle(.secondary) }
                    Button(draft ? "Create Draft" : "Create Pull Request") { Task { await create() } }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || base.isEmpty || working != nil)
                }
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
