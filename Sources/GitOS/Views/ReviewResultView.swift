import SwiftUI

/// The "Review with AI" trigger. One look everywhere it appears.
struct ReviewButton: View {
    let model: RepoModel
    let target: ReviewState.Target
    var title = "Review with AI"

    var body: some View {
        let running = model.reviewState.running.contains(target)
        Button {
            Task { await model.runReview(target) }
        } label: {
            if running {
                HStack(spacing: 5) {
                    ProgressView().controlSize(.mini)
                    Text("Reviewing…")
                }
            } else {
                Label(model.reviewState.reviews[target] == nil ? title : "Re-review", systemImage: "sparkles")
            }
        }
        .disabled(running || !model.app.preferences.aiProvider.isReady)
        .help(model.app.preferences.aiProvider.isReady
              ? "Review these changes with \(model.app.preferences.aiProvider.name). Advisory only — nothing is posted or blocked."
              : "Add an Anthropic API key in Settings › AI")
    }
}

/// One review, rendered the same way for PRs, commits and uncommitted changes.
/// Appears only once a review ran (or failed); the trigger button lives with its surface.
struct ReviewPanel: View {
    @Bindable var model: RepoModel
    let target: ReviewState.Target
    /// Set on PR targets to enable "Post as PR Comment".
    var pullRequestNumber: Int?
    /// Jumps the surrounding view to a finding's file, when the surface can.
    var onJump: ((CodeReview.Finding) -> Void)?

    @State private var posting = false
    @State private var posted = false
    @State private var copied = false

    var body: some View {
        if let error = model.reviewState.errors[target] {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.modified)
                Text(error).textSelection(.enabled)
                Spacer()
                ReviewButton(model: model, target: target, title: "Try Again")
            }
            .font(.callout)
            .padding(10)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 8))
        } else if let review = model.reviewState.reviews[target] {
            VStack(alignment: .leading, spacing: 0) {
                header(review)
                if let stale = model.reviewStaleness(for: target) {
                    noteRow(icon: "clock.arrow.circlepath", text: stale)
                }
                if let compliance = review.issueCompliance {
                    noteRow(icon: "smallcircle.filled.circle", text: compliance)
                }
                findingRows(review)
                actions(review)
            }
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
        }
    }

    // MARK: Pieces

    private func header(_ review: CodeReview.Review) -> some View {
        let (icon, text, tint) = verdictLine(review)
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: icon)
            Text(text).font(.callout.weight(.semibold))
            Spacer()
            Text(review.date, format: .relative(presentation: .named))
                .font(.caption).foregroundStyle(.secondary)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12))
    }

    private func verdictLine(_ review: CodeReview.Review) -> (String, String, Color) {
        let counts = [(review.count(.blocker), "blocker"), (review.count(.warning), "warning"), (review.count(.nit), "nit")]
            .filter { $0.0 > 0 }
            .map { "\($0.0) \($0.1)\($0.0 == 1 ? "" : "s")" }
            .joined(separator: ", ")
        switch review.verdict {
        case .block: return ("xmark.octagon.fill", counts, Theme.removed)
        case .caution: return ("exclamationmark.triangle.fill", counts, Theme.modified)
        case .approve: return ("checkmark.seal.fill", review.findings.isEmpty ? "No issues found" : counts, Theme.added)
        }
    }

    private func noteRow(icon: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: icon).foregroundStyle(.secondary)
            Text(text).textSelection(.enabled)
        }
        .font(.caption)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(Divider(), alignment: .bottom)
    }

    @ViewBuilder
    private func findingRows(_ review: CodeReview.Review) -> some View {
        if !review.summary.isEmpty {
            Text(review.summary)
                .font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        let nits = review.findings.filter { $0.severity == .nit }
        let showNits = model.reviewState.showNits.contains(target)
        ForEach(review.findings.filter { $0.severity != .nit }) { finding in
            Divider()
            FindingRow(model: model, target: target, finding: finding, onJump: onJump)
        }
        if !nits.isEmpty {
            Divider()
            Button {
                if showNits { model.reviewState.showNits.remove(target) } else { model.reviewState.showNits.insert(target) }
            } label: {
                Label("\(nits.count) nit\(nits.count == 1 ? "" : "s") \(showNits ? "shown" : "hidden")",
                      systemImage: showNits ? "chevron.down" : "chevron.right")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 10).padding(.vertical, 6)
            if showNits {
                ForEach(nits) { finding in
                    Divider()
                    FindingRow(model: model, target: target, finding: finding, onJump: onJump)
                }
            }
        }
        if !review.skippedFiles.isEmpty {
            Divider()
            Text("Not reviewed (too large): \(review.skippedFiles.joined(separator: ", "))")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 10).padding(.vertical, 6)
        }
    }

    private func actions(_ review: CodeReview.Review) -> some View {
        HStack(spacing: 8) {
            if let number = pullRequestNumber {
                Button(posting ? "Posting…" : posted ? "Posted ✓" : model.resolved.account.map { "Post as @\($0.login)" } ?? "Post as PR Comment") {
                    Task {
                        posting = true
                        posted = await model.postReviewComment(for: number)
                        posting = false
                    }
                }
                .disabled(posting || posted)
                .help("Posts the whole review as one comment on #\(number)\(model.resolved.account.map { " as @\($0.login)" } ?? "")")
            }
            Button(copied ? "Copied ✓" : "Copy as Markdown") {
                copyToPasteboard(CodeReview.markdown(for: review, heading: headingName))
                copied = true
                Task { try? await Task.sleep(for: .seconds(2)); copied = false }
            }
            Spacer()
            ReviewButton(model: model, target: target)
        }
        .font(.caption)
        .controlSize(.small)
        .padding(8)
        .overlay(Divider(), alignment: .top)
    }

    private var headingName: String {
        switch target {
        case .pullRequest(let number): "pull request #\(number)"
        case .commit(let sha): "commit \(String(sha.prefix(7)))"
        case .workingTree: "uncommitted changes"
        }
    }
}

private struct FindingRow: View {
    let model: RepoModel
    let target: ReviewState.Target
    let finding: CodeReview.Finding
    let onJump: ((CodeReview.Finding) -> Void)?
    @State private var copiedFix = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                SeverityPill(severity: finding.severity)
                Text(location)
                    .font(.caption.monospaced())
                    .foregroundStyle(Theme.accent)
                    .lineLimit(1).truncationMode(.middle)
                Text(finding.confidence == .medium ? "" : "\(finding.confidence.rawValue) confidence")
                    .font(.caption2).foregroundStyle(.tertiary)
                Spacer()
            }
            Text(finding.title).font(.callout.weight(.medium)).textSelection(.enabled)
            if !finding.detail.isEmpty && finding.detail != finding.title {
                Text(finding.detail).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            }
            if let fix = finding.suggestion, !fix.isEmpty {
                Text(fix)
                    .font(.caption.monospaced()).textSelection(.enabled)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.field, in: RoundedRectangle(cornerRadius: 6))
            }
            HStack(spacing: 8) {
                Button(copiedFix ? "Copied ✓" : "Fix with AI") {
                    copyToPasteboard(CodeReview.fixPrompt(for: finding))
                    copiedFix = true
                    Task { try? await Task.sleep(for: .seconds(2)); copiedFix = false }
                }
                .help("Copies an agent-ready prompt — paste it into Claude Code or Codex in this repo")
                if let onJump {
                    Button("Show in Diff") { onJump(finding) }
                }
                Button("Dismiss") { model.dismissFinding(finding, for: target) }
                    .help("Hides this finding here and in future reviews of this repository")
            }
            .font(.caption)
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
    }

    private var location: String {
        finding.line.map { "\(finding.file):\($0)" } ?? finding.file
    }
}

/// Compact outcome of a finished review, for list rows.
struct ReviewVerdictChip: View {
    let review: CodeReview.Review

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(tint.opacity(0.18), in: Capsule())
            .foregroundStyle(tint)
            .help(review.summary)
    }

    private var label: String {
        switch review.verdict {
        case .block:
            let n = review.count(.blocker)
            return "\(n) blocker\(n == 1 ? "" : "s")"
        case .caution:
            let n = review.count(.warning)
            return "\(n) warning\(n == 1 ? "" : "s")"
        case .approve:
            return "reviewed ✓"
        }
    }

    private var tint: Color {
        switch review.verdict {
        case .block: Theme.removed
        case .caution: Theme.modified
        case .approve: Theme.added
        }
    }
}

struct SeverityPill: View {
    let severity: CodeReview.Severity

    var body: some View {
        Text(severity.rawValue.uppercased())
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(tint.opacity(0.18), in: Capsule())
            .foregroundStyle(tint)
    }

    private var tint: Color {
        switch severity {
        case .blocker: Theme.removed
        case .warning: Theme.modified
        case .nit: .secondary
        }
    }
}

func copyToPasteboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}
