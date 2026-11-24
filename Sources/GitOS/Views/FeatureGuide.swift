import SwiftUI

/// One feature explained in the GitOS Guide: what it is, how to use it, and its shortcuts.
struct GuideTopic: Identifiable, Hashable {
    var id: String
    var title: String
    var systemImage: String
    var isPro = false
    var summary: String
    var steps: [String]
    var shortcuts: [Shortcut] = []

    struct Shortcut: Hashable {
        var keys: String
        var action: String
    }
}

extension GuideTopic {
    /// Every feature, in the order a new user meets them. The tour and onboarding link to these ids.
    static let all: [GuideTopic] = [
        GuideTopic(
            id: "accounts", title: "Accounts and folder rules", systemImage: "person.2",
            summary: "GitOS picks the right GitHub account for each repository, so you never commit or push as the wrong person. Your ~/.gitconfig is never changed.",
            steps: [
                "Open Settings › Accounts and click + to sign in to each GitHub account. Keep the browser signed in to the account you're adding; use a private window for the second one.",
                "Open Settings › Folder Rules and map a folder to an account, for example ~/Work → your work account. Every repository inside that folder uses it.",
                "Everything without a rule uses the default account, shown at the top of the menu bar window.",
                "To override one repository, use the account button in its toolbar.",
                "Before you push, GitOS warns you if unpushed commits were written with an email that isn't on the repository's account.",
                "The free app has 2 accounts. Pro has unlimited accounts.",
            ]),
        GuideTopic(
            id: "repositories", title: "Adding repositories", systemImage: "folder.badge.plus",
            summary: "Add repositories you already have, or clone new ones. They appear in the sidebar with their branch, changes and how far ahead or behind they are.",
            steps: [
                "Choose File › Add Local Repository… and pick a folder that contains a git repository.",
                "Or choose File › Clone Repository… and paste a GitHub URL. GitOS clones it with the account its folder rule picks.",
                "Each sidebar row shows ↑ commits to push, ↓ commits to pull, and a dot for uncommitted changes.",
                "Right-click a repository to reveal it in Finder, open it in Terminal, or remove it from GitOS. Removing never deletes files.",
            ],
            shortcuts: [.init(keys: "⌘O", action: "Add a local repository"), .init(keys: "⇧⌘O", action: "Clone a repository")]),
        GuideTopic(
            id: "changes", title: "Changes, staging and commits", systemImage: "square.and.pencil",
            summary: "See every changed file, stage exactly what you mean — whole files, single hunks or individual lines — and commit.",
            steps: [
                "The Changes tab lists unstaged and staged files. Select a file to see its diff.",
                "Stage a whole file with its checkbox or right-click menu, or everything with Stage All.",
                "In the diff, use Stage Hunk above a hunk to stage just that part.",
                "Click a line number to select a line, Shift-click to select a range, then choose Stage N Lines.",
                "Write a message in the commit box and press ⌘↩. Add co-authors with the person button; GitOS adds the Co-authored-by lines for you.",
                "Discard Changes asks first. Untracked files go to the Trash, so you can get them back.",
            ],
            shortcuts: [.init(keys: "⌘↩", action: "Commit"), .init(keys: "⌘R", action: "Refresh")]),
        GuideTopic(
            id: "ai", title: "AI commit messages and reviews", systemImage: "sparkles", isPro: true,
            summary: "GitOS writes commit messages and pull request descriptions from your staged changes, and can review a commit or pull request for bugs.",
            steps: [
                "Choose a provider in Settings › AI: the Claude Code or Codex command-line tool you're already signed in to (no API key needed), or an Anthropic API key.",
                "Stage your changes and press ⇧⌘G, or click ✨ in the commit box. Edit the message before committing.",
                "In History, select a commit and choose Review Commit to get findings ranked by severity.",
                "Only the diff you choose and your recent commit subjects are sent, and only to the provider you picked.",
            ],
            shortcuts: [.init(keys: "⇧⌘G", action: "Generate a commit message")]),
        GuideTopic(
            id: "history", title: "History and the commit graph", systemImage: "clock.arrow.circlepath",
            summary: "Browse every commit with a graph of how branches split and merge, and open any commit to see its files and diff.",
            steps: [
                "Open the History tab. Each lane in the graph is a line of work; merges join them.",
                "Select a commit to see its message, author, files and diff.",
                "Right-click a commit for more: start an interactive rebase from it (Pro) or review it with AI (Pro).",
            ]),
        GuideTopic(
            id: "branches", title: "Branches and merging", systemImage: "arrow.triangle.branch",
            summary: "Switch, create and merge branches from the branch button in the toolbar.",
            steps: [
                "Click the branch button to see local and remote branches. Type to filter, use the arrow keys and Return to switch.",
                "Choose New Branch… to branch from where you are.",
                "Right-click a branch to merge it into the current branch or copy its name.",
            ],
            shortcuts: [.init(keys: "⇧⌘N", action: "New branch")]),
        GuideTopic(
            id: "sync", title: "Fetch, pull and push", systemImage: "arrow.up.arrow.down",
            summary: "Keep repositories in sync with GitHub, by hand or in the background.",
            steps: [
                "Use Fetch, Pull and Push in the repository toolbar. Each uses the repository's account.",
                "If unpushed commits were written with an email that isn't on the account, GitOS asks before pushing them.",
                "Background fetch (Settings › General) keeps every repository fresh and can notify you about new commits.",
                "Fetch every repository at once with Repository › Fetch All Repositories.",
            ],
            shortcuts: [.init(keys: "⌥⌘F", action: "Fetch all repositories")]),
        GuideTopic(
            id: "stashes", title: "Stashes", systemImage: "tray.full",
            summary: "Put unfinished work aside, switch tasks, and bring it back later.",
            steps: [
                "Open the Stashes tab and choose Stash Changes…. Untracked files are included.",
                "Select a stash to see its changes. Apply keeps the stash; Pop applies it and removes it.",
            ]),
        GuideTopic(
            id: "conflicts", title: "Merge conflicts", systemImage: "arrow.triangle.merge",
            summary: "When a merge, pull or rebase conflicts, GitOS shows a banner and lists the conflicted files.",
            steps: [
                "For any conflicted file, keep your version or theirs for the whole file.",
                "With Pro, open the 3-way conflict editor to pick hunks from each side or edit the result by hand.",
                "When every file is resolved, continue the merge or rebase from the banner, or abort it.",
            ]),
        GuideTopic(
            id: "pulls", title: "Pull requests, triage and CI checks", systemImage: "arrow.triangle.pull", isPro: true,
            summary: "See, open and review pull requests without leaving GitOS, with CI status for your branch.",
            steps: [
                "Open the Pull Requests tab to see open pull requests for the repository.",
                "Select one to read its description, files, checks and reviews.",
                "PR triage groups near-identical pull requests and orders the list by which are most worth your time.",
                "The checks button in the toolbar shows CI status for the current branch.",
            ]),
        GuideTopic(
            id: "issues", title: "Issues", systemImage: "smallcircle.filled.circle", isPro: true,
            summary: "Browse and read the repository's GitHub issues next to your code.",
            steps: ["Open the Issues tab and select an issue to read it and its comments."]),
        GuideTopic(
            id: "worktrees", title: "Worktrees", systemImage: "square.stack.3d.up", isPro: true,
            summary: "Check out more than one branch at once, each in its own folder, without stashing.",
            steps: [
                "Open the Worktrees tab to see every worktree of the repository.",
                "Choose New Worktree… for a branch, open it in GitOS or Finder, and remove it when you're done.",
            ]),
        GuideTopic(
            id: "focus", title: "Focus mode", systemImage: "arrow.up.left.and.arrow.down.right",
            summary: "Give a diff, conflict, commit, pull request, issue or stash the whole window.",
            steps: [
                "Press ⇧⌘F, or click the expand button on any detail pane.",
                "Press Esc to bring everything back. ⌘1–⌘6 still switch tabs while the tab bar is hidden.",
            ],
            shortcuts: [.init(keys: "⇧⌘F", action: "Focus mode"), .init(keys: "Esc", action: "Leave focus mode"),
                        .init(keys: "⌘1–⌘6", action: "Switch tabs")]),
        GuideTopic(
            id: "themes", title: "Themes and window styles", systemImage: "paintpalette",
            summary: "Make GitOS look the way you like.",
            steps: [
                "Settings › General has Liquid Glass and Flat window styles.",
                "The GitOS theme is free. Pro adds the other themes, such as Monokai, Tokyo Night, Dracula, One Dark Pro, GitHub, Nord, Catppuccin and Solarized.",
            ]),
        GuideTopic(
            id: "menubar", title: "Menu bar and the gitos command", systemImage: "menubar.rectangle",
            summary: "See every repository's status from the menu bar, and open repositories from Terminal.",
            steps: [
                "The menu bar window lists each repository with its account, branch and status. Click one to open it.",
                "While the menu bar icon is on, GitOS keeps running and fetching after you close its window.",
                "Settings › General › Install gitos Command, then run gitos . in any repository to open it in GitOS.",
            ]),
        GuideTopic(
            id: "updates", title: "Updates", systemImage: "arrow.down.circle",
            summary: "GitOS checks for new versions when it opens and every hour, and downloads them in the background.",
            steps: [
                "Choose GitOS › Check for Updates…, or the ⬇︎ button in the menu bar window, to see the Software Update window with each step.",
                "When an update is ready, choose Restart to Update. Nothing installs until you do; quitting doesn't install it.",
                "Your repositories, accounts and settings are kept.",
            ]),
        GuideTopic(
            id: "pro", title: "Free, Pro and building from source", systemImage: "checkmark.seal",
            summary: "GitOS is open source under the GPLv3. The signed app is free, and Pro unlocks the extras after a 30-day trial.",
            steps: [
                "Every new install gets a 30-day Pro trial with no payment details.",
                "Pro features show a PRO badge. When the trial ends they show what they do and how to unlock them; nothing else stops working.",
                "Enter a license key in Settings › License.",
                "If you build GitOS from source yourself, every feature is unlocked.",
            ]),
    ]

    static func topic(_ id: String) -> GuideTopic? { all.first { $0.id == id } }
}

/// The GitOS Guide window: every feature explained, opened from Help › GitOS Guide.
struct GuideWindow: View {
    static let id = "guide"
    @State private var selection: String? = GuideTopic.all.first?.id
    private let router = GuideRouter.shared

    var body: some View {
        NavigationSplitView {
            List(GuideTopic.all, selection: $selection) { topic in
                HStack {
                    Label(topic.title, systemImage: topic.systemImage)
                    if topic.isPro && Licensing.isOfficialBuild {
                        Spacer(minLength: 4)
                        ProBadge()
                    }
                }
                .tag(topic.id)
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 250)
        } detail: {
            if let topic = selection.flatMap(GuideTopic.topic) {
                GuideTopicView(topic: topic)
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .onAppear(perform: takeRequest)
        .onChange(of: router.requestedTopic) { takeRequest() }
    }

    private func takeRequest() {
        if let id = router.requestedTopic, GuideTopic.topic(id) != nil {
            selection = id
            router.requestedTopic = nil
        }
    }
}

/// Lets the tour and onboarding open the guide at a given topic.
@MainActor
@Observable
final class GuideRouter {
    static let shared = GuideRouter()
    var requestedTopic: String?
}

struct GuideTopicView: View {
    let topic: GuideTopic

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    Image(systemName: topic.systemImage)
                        .font(.title)
                        .foregroundStyle(Theme.accent)
                        .frame(width: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(topic.title).font(.title2.weight(.semibold))
                            if topic.isPro && Licensing.isOfficialBuild { ProBadge() }
                        }
                        Text(topic.summary).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("How to use it").font(.headline)
                    ForEach(Array(topic.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(index + 1)")
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .frame(width: 20, height: 20)
                                .background(Theme.accent.opacity(0.15), in: Circle())
                                .foregroundStyle(Theme.accent)
                            Text(step).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if !topic.shortcuts.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Shortcuts").font(.headline)
                        ForEach(topic.shortcuts, id: \.self) { shortcut in
                            HStack {
                                Text(shortcut.keys)
                                    .font(.callout.monospaced())
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Theme.field, in: RoundedRectangle(cornerRadius: 5))
                                    .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(.separator) }
                                Text(shortcut.action).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .textSelection(.enabled)
    }
}

/// Help menu items: the guide, plus the tour and welcome screens added alongside it.
struct HelpCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("GitOS Guide") { openWindow(id: GuideWindow.id) }
                .keyboardShortcut("?", modifiers: .command)
        }
    }
}
