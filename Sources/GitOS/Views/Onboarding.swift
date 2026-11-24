import SwiftUI

/// Whether the welcome flow is showing. It opens by itself once for new users, and again from
/// Help › Welcome to GitOS.
@MainActor
@Observable
final class Onboarding {
    static let shared = Onboarding()
    nonisolated static let doneKey = "gitos.onboarding-done"

    var isPresented = false

    /// New users see it on first launch. People upgrading from a version without it already have
    /// repositories or accounts set up, so they don't, but it's marked done for them either way.
    nonisolated static func showsOnLaunch(done: Bool, hasRepos: Bool, hasAccounts: Bool) -> Bool {
        !done && !hasRepos && !hasAccounts
    }

    func presentIfNeeded(app: AppState, defaults: UserDefaults = .standard) {
        let done = defaults.bool(forKey: Self.doneKey)
        if Self.showsOnLaunch(done: done, hasRepos: !app.repos.isEmpty, hasAccounts: !app.accounts.isEmpty) {
            isPresented = true
        } else if !done {
            defaults.set(true, forKey: Self.doneKey)
        }
    }

    func finish(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: Self.doneKey)
        isPresented = false
    }
}

/// The welcome flow: what GitOS is for, then accounts, folder rules and a first repository.
struct OnboardingView: View {
    @Environment(AppState.self) private var app
    @Environment(\.openWindow) private var openWindow
    @State private var page = Page.welcome
    /// Called with true when the user asks for the interactive tour at the end.
    var onFinish: (_ startTour: Bool) -> Void

    enum Page: Int, CaseIterable {
        case welcome, accounts, rules, repositories, plan, ready
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch page {
                case .welcome: welcome
                case .accounts: accounts
                case .rules: rules
                case .repositories: repositories
                case .plan: plan
                case .ready: ready
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(28)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .opacity))
            .id(page)

            Divider()
            footer.padding(16)
        }
        .frame(width: 560, height: 470)
        .animation(.snappy(duration: 0.25), value: page)
    }

    // MARK: Pages

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 16) {
            GitOSMark(size: 64)
            Text("Welcome to GitOS").font(.largeTitle.weight(.semibold))
            Text("A Mac git client that uses the right GitHub account in every folder, so you never commit or push as the wrong person.")
                .font(.title3).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 10) {
                point("person.2", "Sign in to each of your GitHub accounts once.")
                point("folder", "Tell GitOS which folders belong to which account.")
                point("checkmark.shield", "Every fetch, commit and push then uses the right one. Your ~/.gitconfig stays as it is.")
            }
            .padding(.top, 4)
            Text("This takes about a minute. You can skip any step and come back from Help › Welcome to GitOS.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var accounts: some View {
        VStack(alignment: .leading, spacing: 14) {
            header("person.2", "Add your GitHub accounts",
                   "GitOS signs in through your browser and keeps the sign-in on this Mac. It never sees your password.")
            VStack(alignment: .leading, spacing: 8) {
                step(1, "Click Add a GitHub Account. Settings opens on the Accounts tab; click + there.")
                step(2, "Keep the browser signed in to the account you're adding. For a second account, use a private window.")
                step(3, "Come back here when you're done.")
            }
            HStack {
                SettingsLink { Label("Add a GitHub Account…", systemImage: "person.crop.circle.badge.plus") }
                    .prominentButton()
                Spacer()
                status(app.accounts.isEmpty ? "No accounts yet" : "\(app.accounts.count) account\(app.accounts.count == 1 ? "" : "s") added",
                       done: !app.accounts.isEmpty)
            }
            if Licensing.isOfficialBuild {
                Text("The free app has \(Licensing.freeAccountLimit) accounts; Pro has as many as you need.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var rules: some View {
        VStack(alignment: .leading, spacing: 14) {
            header("folder.badge.person.crop", "Match folders to accounts",
                   "A folder rule says which account to use for every repository inside a folder.")
            VStack(alignment: .leading, spacing: 6) {
                ruleExample("~/Work", "your work account")
                ruleExample("~/Code", "your personal account")
                ruleExample("Everything else", "the default account")
            }
            .padding(12)
            .background(Theme.field, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 8) {
                step(1, "Open Settings › Folder Rules and add a rule for each folder.")
                step(2, "Pick the default account in Settings › Accounts for everything without a rule.")
                step(3, "To override one repository, use the account button in its toolbar later.")
            }
            HStack {
                SettingsLink { Label("Set Up Folder Rules…", systemImage: "folder.badge.gearshape") }
                Spacer()
                status(app.rules.isEmpty ? "No rules yet" : "\(app.rules.count) rule\(app.rules.count == 1 ? "" : "s")",
                       done: !app.rules.isEmpty)
            }
        }
    }

    private var repositories: some View {
        VStack(alignment: .leading, spacing: 14) {
            header("folder.badge.plus", "Add a repository",
                   "Add a repository you already have, or clone one from GitHub. You can add more any time from the File menu.")
            HStack(spacing: 10) {
                Button("Add Local Repository…") { app.addRepositoryViaPanel() }
                Button("Clone Repository…") {
                    finish(tour: false)
                    app.showingClone = true
                }
                .help("Closes this welcome and opens Clone")
            }
            status(app.repos.isEmpty ? "No repositories yet" : "\(app.repos.count) repositor\(app.repos.count == 1 ? "y" : "ies") added",
                   done: !app.repos.isEmpty)
            Text("Each repository shows its branch, ↑ commits to push, ↓ commits to pull, and a dot when it has uncommitted changes.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var plan: some View {
        VStack(alignment: .leading, spacing: 14) {
            if Licensing.isOfficialBuild {
                header("checkmark.seal", "Free, with a 30-day Pro trial",
                       "Everything you need for daily git work is free. For the next 30 days you also have every Pro feature, with no payment details.")
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(["Pull requests, PR triage and CI checks", "Issues", "AI commit messages and code review",
                             "3-way conflict editor and interactive rebase", "Worktrees", "Every theme and unlimited accounts"],
                            id: \.self) { item in
                        Label(item, systemImage: "checkmark").font(.callout)
                    }
                }
                Text("Pro features show a PRO badge. After the trial they explain how to unlock them; nothing else stops working. GitOS is open source, and building it yourself unlocks everything.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                header("hammer", "Every feature is unlocked",
                       "You built GitOS from source, so pull requests, issues, AI, the conflict editor, rebase, worktrees and every theme are all yours.")
                Text("Thanks for building GitOS yourself. Bug reports and pull requests are welcome on GitHub.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var ready: some View {
        VStack(alignment: .leading, spacing: 16) {
            header("sparkles", "You're ready", "Here's where to find help while you get going.")
            VStack(alignment: .leading, spacing: 8) {
                point("book", "Help › GitOS Guide (⌘?) explains every feature in detail.")
                point("keyboard", "⌘1–⌘6 switch tabs, ⌘↩ commits, ⇧⌘F gives a pane the whole window.")
            }
            Button("Open the GitOS Guide") { openWindow(id: GuideWindow.id) }
                .buttonStyle(.link)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(Page.allCases, id: \.self) { item in
                    Circle()
                        .fill(item == page ? Theme.accent : Color.secondary.opacity(0.3))
                        .frame(width: 7, height: 7)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Step \(page.rawValue + 1) of \(Page.allCases.count)")
            Spacer()
            if page == .welcome {
                Button("Skip") { finish(tour: false) }.keyboardShortcut(.cancelAction)
            } else {
                Button("Back") { move(-1) }
            }
            if page == .ready {
                Button("Start Using GitOS") { finish(tour: false) }
                    .keyboardShortcut(.defaultAction)
                    .prominentButton()
            } else {
                Button(page == .welcome ? "Get Started" : "Continue") { move(1) }
                    .keyboardShortcut(.defaultAction)
                    .prominentButton()
            }
        }
    }

    private func move(_ offset: Int) {
        page = Page(rawValue: page.rawValue + offset) ?? page
    }

    private func finish(tour: Bool) {
        Onboarding.shared.finish()
        onFinish(tour)
    }

    // MARK: Pieces

    private func header(_ icon: String, _ title: String, _ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).font(.system(size: 30)).foregroundStyle(Theme.accent)
            Text(title).font(.title.weight(.semibold))
            Text(message).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func point(_ icon: String, _ text: String) -> some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: icon).foregroundStyle(Theme.accent).frame(width: 20)
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .frame(width: 20, height: 20)
                .background(Theme.accent.opacity(0.15), in: Circle())
                .foregroundStyle(Theme.accent)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func ruleExample(_ folder: String, _ account: String) -> some View {
        HStack {
            Text(folder).font(.callout.monospaced())
            Image(systemName: "arrow.right").foregroundStyle(.secondary)
            Text(account).font(.callout)
        }
    }

    private func status(_ text: String, done: Bool) -> some View {
        Label(text, systemImage: done ? "checkmark.circle.fill" : "circle.dashed")
            .font(.callout)
            .foregroundStyle(done ? Theme.accent : .secondary)
            .contentTransition(.symbolEffect(.replace))
    }
}
