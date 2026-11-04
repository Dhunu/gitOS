import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var app = app
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 360)
        } detail: {
            if let repo = app.selectedRepo {
                RepoView(model: RepoModel(ref: repo, app: app))
                    .id(repo.id)
            } else {
                GitOSWelcome(title: "Welcome to GitOS", message: "Add a local git repository to get started.") {
                    HStack {
                        Button("Add Local Repository…") { app.addRepositoryViaPanel() }
                        Button("Clone Repository…") { app.showingClone = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .background(Theme.canvas)
            }
        }
        .sheet(isPresented: $app.showingClone) {
            CloneSheet()
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { app.lastError != nil }, set: { if !$0 { app.lastError = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(app.lastError ?? "")
        }
    }
}

struct SidebarView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var app = app
        List(selection: $app.selectedRepoID) {
            Section("Repositories") {
                ForEach(app.repos) { repo in
                    RepoRow(repo: repo, resolved: app.resolveAccount(for: repo), summary: app.summaries[repo.id])
                        .tag(repo.id)
                        .contextMenu {
                            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([repo.url]) }
                            Button("Open in Terminal") { openInTerminal(repo.url) }
                            Divider()
                            Button("Remove from GitOS", role: .destructive) { app.removeRepository(repo.id) }
                        }
                }
            }
        }
        .overlay {
            if app.repos.isEmpty {
                Text("No repositories yet").foregroundStyle(.secondary)
            }
        }
        .toolbar {
            ToolbarItem {
                Menu {
                    Button("Add Local Repository…") { app.addRepositoryViaPanel() }
                    Button("Clone Repository…") { app.showingClone = true }
                } label: {
                    Label("Add Repository", systemImage: "plus")
                }
                .help("Add or clone a repository")
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 8) {
                GitOSMark(size: 20)
                Text("GitOS").font(.system(.headline, design: .rounded).weight(.semibold))
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
        }
        .safeAreaInset(edge: .bottom) {
            DefaultAccountFooter()
        }
    }

    private func openInTerminal(_ url: URL) {
        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        NSWorkspace.shared.open([url], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
    }
}

private struct RepoRow: View {
    let repo: RepoRef
    let resolved: ResolvedAccount
    let summary: RepoSummary?

    var body: some View {
        HStack {
            RepoTile(name: repo.name)
            VStack(alignment: .leading, spacing: 1) {
                Text(repo.name)
                Text((repo.path as NSString).deletingLastPathComponent.abbreviatingWithTildeInPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 4)
            if let summary {
                SummaryBadges(summary: summary)
            }
            if let account = resolved.account {
                AvatarView(account: account, size: 16)
                    .help("\(account.title): \(resolved.explanation)")
            }
        }
    }
}

/// A repository's icon: its initial on a tint chosen from its name, so repos are easy to tell apart.
struct RepoTile: View {
    let name: String

    var body: some View {
        let tint = Theme.lane(for: name)
        Text(name.prefix(1).uppercased())
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(tint)
            .frame(width: 24, height: 24)
            .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct DefaultAccountFooter: View {
    @Environment(AppState.self) private var app

    var body: some View {
        HStack(spacing: 8) {
            if let account = app.account(id: app.defaultAccountID) {
                AvatarView(account: account, size: 22)
                VStack(alignment: .leading, spacing: 0) {
                    Text(account.title).font(.callout).lineLimit(1)
                    Text("Default account").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "person.crop.circle.badge.plus")
                Text("No accounts").font(.callout)
            }
            Spacer()
            SettingsLink {
                Image(systemName: "person.2.badge.gearshape")
            }
            .buttonStyle(.borderless)
            .help("Manage accounts")
        }
        .padding(10)
    }
}

extension String {
    var abbreviatingWithTildeInPath: String { (self as NSString).abbreviatingWithTildeInPath }
}

struct SummaryBadges: View {
    let summary: RepoSummary

    var body: some View {
        HStack(spacing: 4) {
            if summary.behind > 0 { Text("↓\(summary.behind)").foregroundStyle(Theme.modified) }
            if summary.ahead > 0 { Text("↑\(summary.ahead)").foregroundStyle(Theme.accent) }
            if summary.changes > 0 {
                Circle().fill(Theme.head).frame(width: 6, height: 6)
                    .help("\(summary.changes) uncommitted change\(summary.changes == 1 ? "" : "s")")
            }
            if summary.fetchError != nil {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.modified)
                    .help(summary.fetchError ?? "")
            }
        }
        .font(.caption.monospacedDigit())
    }
}
