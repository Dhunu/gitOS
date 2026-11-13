import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var app
    @State private var focusMode = false
    @State private var columns = NavigationSplitViewVisibility.all

    /// Entering focus mode also tucks the repo sidebar away; leaving brings it back.
    private var focusBinding: Binding<Bool> {
        Binding(
            get: { focusMode },
            set: { on in
                focusMode = on
                withAnimation(.snappy(duration: 0.2)) { columns = on ? .detailOnly : .all }
            }
        )
    }

    var body: some View {
        @Bindable var app = app
        NavigationSplitView(columnVisibility: $columns) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 360)
                // The flat style has no glass toolbar; View › Hide Sidebar still works.
                .toolbar(removing: Theme.isFlat ? .sidebarToggle : nil)
        } detail: {
            if let repo = app.selectedRepo {
                RepoView(model: RepoModel(ref: repo, app: app))
                    .id(repo.id)
                    // macOS 26 adds the floating sidebar's width to the detail's minimum; drop it.
                    .frame(minWidth: 0, maxWidth: .infinity)
            } else {
                GitOSWelcome(title: "Welcome to GitOS", message: "Add a local git repository to get started.") {
                    HStack {
                        Button("Add Local Repository…") { app.addRepositoryViaPanel() }
                        Button("Clone Repository…") { app.showingClone = true }
                            .prominentButton()
                    }
                }
                .background(Theme.canvas)
            }
        }
        .modifier(FlatWindowChrome())
        .environment(\.focusMode, focusBinding)
        .focusedSceneValue(\.focusMode, focusBinding)
        .onChange(of: app.selectedRepoID) {
            if focusMode { focusBinding.wrappedValue = false }
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
        .scrollContentBackground(Theme.solid ? .hidden : .automatic)
        .background(Theme.solid ? Theme.panel : Color.clear)
        .overlay {
            if app.repos.isEmpty {
                Text("No repositories yet").foregroundStyle(.secondary)
            }
        }
        .toolbar {
            if !Theme.isFlat {
                ToolbarItem { addMenu }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 8) {
                GitOSMark(size: 20)
                Text("GitOS").font(.system(.headline, design: .rounded).weight(.semibold))
                Spacer()
                if Theme.isFlat {
                    addMenu.labelStyle(.iconOnly).menuStyle(.button).buttonStyle(.borderless).menuIndicator(.hidden)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            // The flat style has no toolbar, so the traffic lights sit above the header.
            .padding(.top, Theme.isFlat ? 40 : 0)
        }
        .ignoresSafeArea(.container, edges: Theme.isFlat ? .top : [])
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if AppUpdater.shared.showsPrompt {
                    UpdatePrompt(updater: AppUpdater.shared)
                }
                DefaultAccountFooter()
            }
        }
    }

    private var addMenu: some View {
        Menu {
            Button("Add Local Repository…") { app.addRepositoryViaPanel() }
            Button("Clone Repository…") { app.showingClone = true }
        } label: {
            Label("Add Repository", systemImage: "plus")
        }
        .help("Add or clone a repository")
    }

    private func openInTerminal(_ url: URL) {
        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        NSWorkspace.shared.open([url], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
    }
}

/// The flat style draws its own header in place of the glass toolbar. The toolbar itself stays,
/// empty and transparent, because hiding it also hides the window's traffic lights.
private struct FlatWindowChrome: ViewModifier {
    func body(content: Content) -> some View {
        if Theme.isFlat {
            content
                .toolbar(removing: .title)
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        } else {
            content
        }
    }
}

private struct RepoRow: View {
    let repo: RepoRef
    let resolved: ResolvedAccount
    let summary: RepoSummary?

    var body: some View {
        HStack {
            RepoTile(name: repo.name, icon: RepoIconStore.shared.icon(for: repo, account: resolved.account))
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

/// A repository's icon: its website's favicon or owner's avatar when one is known,
/// otherwise its initial on a tint chosen from its name, so repos are easy to tell apart.
struct RepoTile: View {
    let name: String
    var icon: NSImage?

    var body: some View {
        if let icon {
            Image(nsImage: icon)
                .resizable()
                .scaledToFill()
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            let tint = Theme.lane(for: name)
            Text(name.prefix(1).uppercased())
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(Theme.isFlat ? Theme.chip : tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 6))
        }
    }
}

/// A way into account setup. It deliberately doesn't show the default account here: under the repo
/// list it read as "the account in use", which is per repository (see the toolbar).
private struct DefaultAccountFooter: View {
    @Environment(AppState.self) private var app

    var body: some View {
        if Theme.isFlat, let account = app.account(id: app.defaultAccountID) {
            // The flat style follows the website and names the default account, labelled as such.
            SettingsLink {
                HStack(spacing: 10) {
                    AvatarView(account: account, size: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(account.title).font(.caption.weight(.medium)).foregroundStyle(.primary)
                        Text("Default account").font(.caption2).foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Manage GitHub accounts, folder rules and the default account")
            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 12)
            .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1).padding(.horizontal, 10) }
        } else {
            glassBody
        }
    }

    private var glassBody: some View {
        SettingsLink {
            Label(app.accounts.isEmpty ? "Add a GitHub Account…" : "Accounts & Rules…",
                  systemImage: app.accounts.isEmpty ? "person.crop.circle.badge.plus" : "person.2.badge.gearshape")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help("Manage GitHub accounts, folder rules and the default account")
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

extension View {
    /// On macOS 26 the detail column runs under the floating sidebar, and an HSplitView adds that
    /// hidden strip to its panes' minimum widths, so narrower windows clip the panes. Turning the
    /// inset into plain padding keeps it out of their minimums. A no-op on 27, where the inset is 0.
    func sidebarInsetAsPadding() -> some View {
        GeometryReader { proxy in
            self
                .padding(.leading, proxy.safeAreaInsets.leading)
                .ignoresSafeArea(.container, edges: .leading)
        }
    }
}
