import SwiftUI

/// Edit the commits from a chosen commit up to HEAD, then run them as an interactive rebase.
struct InteractiveRebaseSheet: View {
    let model: RepoModel
    /// Commits to rewrite, oldest first.
    let commits: [Commit]
    @Environment(\.dismiss) private var dismiss
    @State private var steps: [RebaseStep] = []
    @State private var loading = true

    private var base: String? { commits.first?.parents.first }
    private var problem: String? { RebaseTodo.validate(steps) }
    /// Commits at or below the upstream have been pushed; rewriting them needs a force push.
    private var rewritesPushed: Bool {
        guard model.status.upstream != nil else { return false }
        return commits.count > model.status.ahead
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Interactive Rebase").font(.title2.weight(.semibold))
                Text("Oldest commit first. Drag to reorder. Squash and fixup meld a commit into the one above it.")
                    .foregroundStyle(.secondary)
            }
            .padding(16)

            List {
                ForEach($steps) { $step in
                    RebaseStepRow(step: $step)
                }
                .onMove { steps.move(fromOffsets: $0, toOffset: $1) }
            }
            .overlay { if loading { ProgressView() } }

            VStack(alignment: .leading, spacing: 6) {
                if let problem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.modified)
                }
                if rewritesPushed {
                    Label("This rewrites commits that are already pushed. You'll need to force push afterwards.",
                          systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                        .foregroundStyle(Theme.modified)
                }
                if model.status.hasChanges {
                    Label("Commit or stash your changes first.", systemImage: "tray.full").foregroundStyle(Theme.removed)
                }
            }
            .font(.callout)
            .padding(.horizontal, 16)
            .padding(.top, 8)

            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Text("\(steps.filter { $0.action != .pick }.count) change(s)").foregroundStyle(.secondary)
                Button("Start Rebase") {
                    let (steps, base) = (steps, base)
                    dismiss()
                    Task { await model.interactiveRebase(steps: steps, base: base) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(problem != nil || model.status.hasChanges || loading || steps.allSatisfy { $0.action == .pick } && steps.map(\.sha) == commits.map(\.sha))
            }
            .padding(16)
        }
        .frame(width: 680, height: 560)
        .task {
            var loaded: [RebaseStep] = []
            for commit in commits {
                let message = (try? await model.repo.fullMessage(of: commit.sha)) ?? commit.subject
                loaded.append(RebaseStep(sha: commit.sha, subject: commit.subject, message: message))
            }
            steps = loaded
            loading = false
        }
    }
}

private struct RebaseStepRow: View {
    @Binding var step: RebaseStep

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                Picker("Action", selection: $step.action) {
                    ForEach(RebaseStep.Action.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .frame(width: 100)
                .help(step.action.help)
                Text(String(step.sha.prefix(7))).monospaced().foregroundStyle(.secondary)
                Text(step.subject)
                    .strikethrough(step.action == .drop)
                    .foregroundStyle(step.action == .drop ? .secondary : .primary)
                    .lineLimit(1)
                if step.action == .squash || step.action == .fixup {
                    Image(systemName: "arrow.turn.left.up").foregroundStyle(.secondary).help("Melds into the commit above")
                }
            }
            if step.action == .reword {
                TextEditor(text: $step.message)
                    .font(.body.monospaced())
                    .frame(height: 70)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(.separator))
            }
        }
        .padding(.vertical, 3)
    }
}

/// Shown above the repository content while a rebase/merge/cherry-pick is stopped.
struct OperationBanner: View {
    let model: RepoModel
    let operation: RepoOperation
    let onResolve: () -> Void

    var body: some View {
        let conflicts = model.status.conflicted.count
        HStack(spacing: 12) {
            Image(systemName: conflicts > 0 ? "exclamationmark.triangle.fill" : "arrow.triangle.merge")
                .foregroundStyle(conflicts > 0 ? Theme.modified : Theme.accent)
                .font(.title3)
            VStack(alignment: .leading, spacing: 1) {
                Text(operation.title).font(.headline)
                Text(conflicts > 0
                     ? "\(conflicts) conflicted file\(conflicts == 1 ? "" : "s"). Resolve them, then continue."
                     : "All conflicts resolved. Continue when ready.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            // Less common ways out stay one click away without competing with the next step.
            Menu {
                if case .rebase = operation {
                    Button("Skip Commit") { Task { await model.skipRebaseStep() } }
                }
                Button("Abort \(operation.command.capitalized)", role: .destructive) { Task { await model.abortOperation() } }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(operation.command == "rebase" ? "Skip this commit or abort the rebase" : "Abort the \(operation.command)")
            .accessibilityLabel("More options")
            // The prominent button is always the next step: resolve, then continue.
            if conflicts > 0 {
                Button("Resolve Conflicts…", action: onResolve)
                    .prominentButton()
            } else {
                Button("Continue") { Task { await model.continueOperation() } }
                    .prominentButton()
            }
        }
        .disabled(model.isBusy)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Theme.modified.opacity(0.12))
    }
}
