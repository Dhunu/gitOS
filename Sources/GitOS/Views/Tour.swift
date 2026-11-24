import SwiftUI

/// One stop on the interactive tour. Each stop is attached to the real control it explains and
/// shows as a popover pointing at it.
enum TourStep: Int, CaseIterable, Identifiable {
    case sidebar, account, branch, sync, tabs, changes, diff, commit, finish

    var id: Int { rawValue }

    /// Stops that point at a repository's window only work while one is open.
    var needsRepository: Bool { self != .sidebar && self != .finish }

    var title: String {
        switch self {
        case .sidebar: "Your repositories"
        case .account: "The account for this repository"
        case .branch: "Branches"
        case .sync: "Fetch, pull and push"
        case .tabs: "Everything about this repository"
        case .changes: "What changed"
        case .diff: "Stage exactly what you mean"
        case .commit: "Commit"
        case .finish: "That's the tour"
        }
    }

    var message: String {
        switch self {
        case .sidebar:
            "Every repository you add shows up here with its branch. ↑ is commits to push, ↓ is commits to pull, and a dot means uncommitted changes. Add more with + or File › Add Local Repository (⌘O)."
        case .account:
            "GitOS picks this account from your folder rules, or the default account. Every fetch, commit and push here uses it. Click to override it for just this repository."
        case .branch:
            "Switch branches, create one with New Branch (⇧⌘N), or right-click a branch to merge it or copy its name."
        case .sync:
            "Fetch, pull and push with this repository's account. Background fetch keeps every repository up to date."
        case .tabs:
            "Changes, History, Pull Requests, Issues, Stashes and Worktrees. Press ⌘1 to ⌘6 to jump between them."
        case .changes:
            "Unstaged and staged files. Stage a file with its checkbox or right-click it for more. Select a file to see its diff."
        case .diff:
            "Use Stage Hunk above a hunk, or click line numbers (Shift-click for a range) to stage single lines."
        case .commit:
            "Write a message and press ⌘↩ to commit. ✨ writes the message for you (⇧⌘G), and the person button adds co-authors."
        case .finish:
            "Press ⇧⌘F to give any pane the whole window. Help › GitOS Guide (⌘?) explains every feature, and Help › Take the Tour runs this again."
        }
    }

    var arrowEdge: Edge {
        switch self {
        case .sidebar, .changes, .commit: .trailing
        case .account, .branch, .sync, .tabs: .bottom
        case .diff: .leading
        case .finish: .trailing
        }
    }

    /// The tab a stop needs to be visible.
    var requiredTab: RepoView.Tab? {
        switch self {
        case .changes, .diff, .commit: .changes
        default: nil
        }
    }

    /// The guide page that goes deeper into this stop.
    var guideTopic: String {
        switch self {
        case .sidebar: "repositories"
        case .account: "accounts"
        case .branch: "branches"
        case .sync: "sync"
        case .tabs: "history"
        case .changes, .diff, .commit: "changes"
        case .finish: "focus"
        }
    }
}

/// Where the tour is. `steps` drops the stops that need a repository when none is open.
@MainActor
@Observable
final class Tour {
    static let shared = Tour()

    private(set) var step: TourStep?
    private(set) var steps: [TourStep] = []

    nonisolated static func steps(hasRepository: Bool) -> [TourStep] {
        TourStep.allCases.filter { hasRepository || !$0.needsRepository }
    }

    var position: Int { step.flatMap { steps.firstIndex(of: $0) } ?? 0 }
    var isFirst: Bool { position == 0 }
    var isLast: Bool { position == steps.count - 1 }

    /// Waits a moment so a closing sheet or a window coming forward doesn't swallow the first popover.
    func start(hasRepository: Bool) {
        end()
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            startNow(hasRepository: hasRepository)
        }
    }

    func startNow(hasRepository: Bool) {
        steps = Self.steps(hasRepository: hasRepository)
        step = steps.first
    }

    func next() {
        guard !isLast else { return end() }
        step = steps[position + 1]
    }

    func back() {
        guard !isFirst else { return }
        step = steps[position - 1]
    }

    func end() {
        step = nil
        steps = []
    }
}

extension View {
    /// Marks the control the tour explains at `step`. The popover appears while that stop is current.
    func tourStop(_ step: TourStep) -> some View {
        modifier(TourStopModifier(step: step))
    }
}

private struct TourStopModifier: ViewModifier {
    let step: TourStep
    private let tour = Tour.shared

    func body(content: Content) -> some View {
        content.popover(isPresented: Binding(
            get: { tour.step == step },
            // Clicking outside the popover ends the tour. Moving on changes `step` first, so it doesn't.
            set: { shown in if !shown, tour.step == step { tour.end() } }
        ), arrowEdge: step.arrowEdge) {
            TourCard(step: step)
        }
    }
}

private struct TourCard: View {
    let step: TourStep
    private let tour = Tour.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(tour.position + 1) of \(tour.steps.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Text(step.title).font(.headline)
            Text(step.message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Learn More") {
                    GuideRouter.shared.requestedTopic = step.guideTopic
                    openWindow(id: GuideWindow.id)
                }
                .buttonStyle(.link)
                Spacer()
                if tour.isLast {
                    Button("Done") { tour.end() }
                        .keyboardShortcut(.defaultAction)
                        .prominentButton()
                } else {
                    Button("Skip Tour") { tour.end() }
                        .keyboardShortcut(.cancelAction)
                    if !tour.isFirst {
                        Button("Back") { tour.back() }
                    }
                    Button("Next") { tour.next() }
                        .keyboardShortcut(.defaultAction)
                        .prominentButton()
                }
            }
            .controlSize(.small)
        }
        .padding(16)
        .frame(width: 320)
    }
}
