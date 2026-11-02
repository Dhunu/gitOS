import SwiftUI

/// The menu bar extra: default account switcher plus a live status list of every repository.
struct MenuBarView: View {
    @Environment(AppState.self) private var app
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if let account = app.account(id: app.defaultAccountID) {
                    AvatarView(account: account, size: 24)
                }
                Menu {
                    ForEach(app.accounts) { account in
                        Button {
                            app.defaultAccountID = account.id
                        } label: {
                            if app.defaultAccountID == account.id {
                                Label(account.title, systemImage: "checkmark")
                            } else {
                                Text(account.title)
                            }
                        }
                    }
                    if app.accounts.isEmpty { Text("No accounts") }
                } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(app.account(id: app.defaultAccountID)?.title ?? "No default account")
                            .font(.headline)
                        Text("Default account").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .menuStyle(.borderlessButton)
                Spacer()
            }
            .padding(12)

            Divider()

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(app.repos) { repo in
                        MenuBarRepoRow(repo: repo) {
                            app.selectedRepoID = repo.id
                            open()
                        }
                    }
                    if app.repos.isEmpty {
                        Text("No repositories").foregroundStyle(.secondary).padding()
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 360)

            Divider()

            HStack {
                Button("Fetch All", systemImage: "arrow.clockwise") { Task { await app.sync.fetchAll() } }
                Spacer()
                Button("Open GitOS") { open() }
                Button("Settings", systemImage: "gearshape") {
                    NSApp.activate()
                    openSettings()
                }
                .labelStyle(.iconOnly)
                Button("Quit", systemImage: "power") { NSApp.terminate(nil) }
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .padding(10)
        }
        .frame(width: 340)
        .onAppear { OpenMainWindow.action = { openWindow(id: "main") } }
    }

    private func open() {
        OpenMainWindow.action = { openWindow(id: "main") }
        AppDelegate.showMainWindow()
    }
}

private struct MenuBarRepoRow: View {
    @Environment(AppState.self) private var app
    let repo: RepoRef
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let resolved = app.resolveAccount(for: repo)
        let summary = app.summaries[repo.id]
        Button(action: action) {
            HStack(spacing: 8) {
                if let account = resolved.account {
                    AvatarView(account: account, size: 18)
                } else {
                    Image(systemName: "person.crop.circle.badge.questionmark").frame(width: 18)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(repo.name).lineLimit(1)
                    Text(summary?.branch ?? "…").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if let summary { SummaryBadges(summary: summary) }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(hovering ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(resolved.account.map { "\($0.title): \(resolved.explanation)" } ?? resolved.explanation)
    }
}
