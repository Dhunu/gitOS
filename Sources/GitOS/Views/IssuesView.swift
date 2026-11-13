import SwiftUI

struct IssuesView: View {
    @Bindable var model: RepoModel
    /// Called after an issue reference is added to the commit message, so the caller can show the commit box.
    let onReference: () -> Void
    @State private var selection: Int?
    @State private var search = ""
    @State private var showingNew = false
    @Environment(\.focusMode) private var focusMode

    private var filtered: [GitHubRepoAPI.Issue] {
        guard !search.isEmpty else { return model.issues }
        return model.issues.filter { $0.title.localizedCaseInsensitiveContains(search) || "#\($0.number)".hasPrefix(search) }
    }

    private var selectedIssue: GitHubRepoAPI.Issue? {
        model.issues.first { $0.number == selection }
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
            .sheet(isPresented: $showingNew) {
                NewIssueSheet(model: model) { selection = $0.number }
            }
        }
    }

    private var list: some View {
        List(filtered, selection: $selection) { issue in
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .top) {
                    Image(systemName: "smallcircle.filled.circle").foregroundStyle(Theme.added)
                    Text(issue.title).lineLimit(2)
                }
                HStack(spacing: 4) {
                    Text("#\(issue.number)")
                    Text("·")
                    Text(issue.user.login)
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
                Button("Close with Next Commit") { reference(issue, closes: true) }
                Button("Open on GitHub") { NSWorkspace.shared.open(issue.htmlURL) }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                TextField("Filter issues", text: $search).textFieldStyle(.roundedBorder)
                Button("New Issue…", systemImage: "plus") { showingNew = true }
            }
            .padding(8)
            .background(Theme.panel)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !model.allIssuesLoaded {
                ListLimitNotice(url: model.gitHubPage("issues"))
            }
        }
        .overlay {
            if model.issues.isEmpty {
                ContentUnavailableView("No Open Issues", systemImage: "checkmark.circle",
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
                    Text("Opened by \(issue.user.login) \(issue.createdAt.formatted(.relative(presentation: .named)))")
                        .font(.callout).foregroundStyle(.secondary)
                    HStack {
                        Button("Close with Next Commit", systemImage: "checkmark.circle") { reference(issue, closes: true) }
                            .buttonStyle(.borderedProminent)
                            .help("Adds “Fixes #\(issue.number)” to the commit message")
                        Button("Reference", systemImage: "number") { reference(issue, closes: false) }
                        Button("Open on GitHub", systemImage: "safari") { NSWorkspace.shared.open(issue.htmlURL) }
                    }
                    Divider()
                    if let body = issue.body, !body.isEmpty {
                        Text(markdown(body)).textSelection(.enabled)
                    } else {
                        Text("No description provided.").foregroundStyle(.secondary).italic()
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
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
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create Issue") {
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
            }
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
