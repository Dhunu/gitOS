import SwiftUI

/// The triage take on the PR list: duplicate groups first, then every PR ranked by score.
/// GitOS computes hints; only the maintainer's clicks change anything on GitHub.
struct TriageList: View {
    @Bindable var model: RepoModel
    @Binding var selection: Int?
    @State private var checked: Set<Int> = []
    @State private var closing: CloseRequest?

    struct CloseRequest: Identifiable {
        let id = UUID()
        var numbers: [Int]
        var template: String
    }

    var body: some View {
        List(selection: $selection) {
            if !model.triage.clusters.isEmpty {
                Section("Same change, many PRs") {
                    ForEach(model.triage.clusters, id: \.self) { cluster in
                        ClusterRow(model: model, cluster: cluster) { keep in
                            closing = CloseRequest(numbers: cluster.filter { $0 != keep },
                                                   template: PRTriage.closeTemplate(keeping: keep))
                        }
                    }
                }
            }
            Section(model.triage.clusters.isEmpty ? "Ranked by triage score" : "Everything else, ranked") {
                ForEach(ranked) { pr in
                    TriageRow(model: model, pr: pr, checked: binding(for: pr.number))
                        .tag(pr.number)
                }
            }
        }
        .overlay {
            if model.triage.isLoading && model.triage.loadedAt == nil {
                ProgressView("Comparing open pull requests…")
            } else if model.pullRequests.isEmpty {
                ContentUnavailableView("Nothing to triage", systemImage: "checkmark.seal",
                                       description: Text(model.triage.error ?? "No open pull requests."))
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !checked.isEmpty {
                HStack {
                    Text("\(checked.count) selected").foregroundStyle(.secondary)
                    Spacer()
                    Button("Deselect") { checked = [] }
                    Button("Close with Comment…") {
                        closing = CloseRequest(numbers: checked.sorted(), template: PRTriage.closeTemplate(keeping: nil))
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(8)
                .background(Theme.panel)
            }
        }
        .task { await model.loadTriage() }
        .sheet(item: $closing) { request in
            CloseWithCommentSheet(model: model, request: request) { closedAll in
                if closedAll { checked = [] }
            }
        }
    }

    private var ranked: [GitHubRepoAPI.PullRequest] {
        let clustered = model.triage.clustered
        return model.triagedPullRequests.filter { !clustered.contains($0.number) }
    }

    private func binding(for number: Int) -> Binding<Bool> {
        Binding(get: { checked.contains(number) },
                set: { if $0 { checked.insert(number) } else { checked.remove(number) } })
    }
}

/// A duplicate group: the PRs are near-identical, so one review answers them all.
private struct ClusterRow: View {
    let model: RepoModel
    let cluster: [Int]
    let closeOthers: (Int) -> Void

    var body: some View {
        let lead = best()
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "square.on.square").foregroundStyle(Theme.accent)
                Text(model.pullRequests.first { $0.number == lead }?.title ?? "#\(lead)").lineLimit(2)
                Text("×\(cluster.count) same change")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Theme.accent.opacity(0.18), in: Capsule())
                    .foregroundStyle(Theme.accent)
            }
            Text(cluster.map { "#\($0)" }.joined(separator: "  ") + "  ·  best: #\(lead)")
                .font(.caption).foregroundStyle(.secondary)
            Button("Keep #\(lead), close \(cluster.count - 1) with thanks…") { closeOthers(lead) }
                .font(.caption)
                .disabled(!model.triage.closing.isEmpty)
        }
        .padding(.vertical, 3)
    }

    /// Highest triage score wins; the oldest (lowest number) breaks ties.
    private func best() -> Int {
        cluster.min {
            let a = model.triage.scores[$0]?.total ?? 0
            let b = model.triage.scores[$1]?.total ?? 0
            return a == b ? $0 < $1 : a > b
        } ?? cluster[0]
    }
}

private struct TriageRow: View {
    let model: RepoModel
    let pr: GitHubRepoAPI.PullRequest
    @Binding var checked: Bool

    var body: some View {
        let score = model.triage.scores[pr.number]
        HStack(alignment: .top, spacing: 8) {
            Toggle("Select for batch actions", isOn: $checked)
                .toggleStyle(.checkbox).labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(pr.title).lineLimit(2)
                    if let score { ScorePill(score: score) }
                    if let review = model.reviewState.reviews[.pullRequest(pr.number)] {
                        ReviewVerdictChip(review: review)
                    }
                }
                HStack(spacing: 4) {
                    Text("#\(pr.number)")
                    Text("·")
                    Text(pr.user.login)
                    if let reasons = score?.reasons, !reasons.isEmpty {
                        Text("·")
                        Text(reasons.prefix(3).joined(separator: " · "))
                    }
                }
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if model.triage.reviewing.contains(pr.number) {
                    HStack(spacing: 5) {
                        ProgressView().controlSize(.mini)
                        Text("Pre-reviewing…").font(.caption).foregroundStyle(.secondary)
                    }
                } else if let verdict = model.triage.verdicts[pr.number] {
                    Text(verdict)
                        .font(.caption).italic().foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if model.reviewState.running.contains(.pullRequest(pr.number)) {
                    HStack(spacing: 5) {
                        ProgressView().controlSize(.mini)
                        Text("Reviewing…").font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    HStack(spacing: 10) {
                        Button("Pre-review with AI") { Task { await model.preReview(pr) } }
                            .help("Your signed-in AI checks whether the diff matches the description. A hint, not a decision.")
                        if model.reviewState.reviews[.pullRequest(pr.number)] == nil {
                            Button("Full review") { Task { await model.runReview(.pullRequest(pr.number)) } }
                                .help("A full code review with findings — select the PR to read it")
                        }
                    }
                    .font(.caption).buttonStyle(.link)
                    .disabled(!model.app.preferences.aiProvider.isReady)
                }
            }
            Spacer()
            if let checks = model.prChecks[pr.number] { ChecksBadge(checks: checks) }
        }
        .padding(.vertical, 3)
    }
}

struct ScorePill: View {
    let score: PRTriage.Score

    var body: some View {
        Text("\(score.total)")
            .font(.caption.weight(.bold).monospacedDigit())
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(tint.opacity(0.2), in: Capsule())
            .foregroundStyle(tint)
            .help(score.reasons.joined(separator: "\n"))
    }

    private var tint: Color {
        if score.flagged { return Theme.removed }
        return score.total >= 70 ? Theme.added : score.total >= 45 ? Theme.modified : .secondary
    }
}

/// Confirms a batch close. The comment is posted on every PR before it closes,
/// so no contributor gets a silent dismissal.
struct CloseWithCommentSheet: View {
    let model: RepoModel
    let request: TriageList.CloseRequest
    let done: (Bool) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var comment: String
    @State private var working = false
    @State private var error: String?

    init(model: RepoModel, request: TriageList.CloseRequest, done: @escaping (Bool) -> Void) {
        self.model = model
        self.request = request
        self.done = done
        _comment = State(initialValue: request.template)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Close \(request.numbers.count) pull request\(request.numbers.count == 1 ? "" : "s")")
                .font(.headline)
            Text(request.numbers.map { "#\($0)" }.joined(separator: "  "))
                .font(.callout.monospaced()).foregroundStyle(.secondary)
            Text("This comment is posted on each one first:")
                .font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $comment)
                .font(.body)
                .frame(minHeight: 120)
                .padding(6)
                .background(Theme.field, in: RoundedRectangle(cornerRadius: 6))
            if let error { Text(error).foregroundStyle(Theme.removed).font(.callout) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.disabled(working)
                Button(working ? "Closing…" : "Comment and Close") { Task { await close() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(working)
            }
        }
        .padding(16)
        .frame(width: 480)
    }

    private func close() async {
        working = true
        defer { working = false }
        let failed = await model.closePullRequests(request.numbers, comment: comment)
        if failed.isEmpty {
            done(true)
            dismiss()
        } else {
            error = "Couldn't close \(failed.map { "#\($0)" }.joined(separator: ", ")). The rest were closed."
            done(false)
        }
    }
}
