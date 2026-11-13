import SwiftUI

/// Stands in for a Pro tab or pane when Pro isn't available: says what it is and how to get it.
struct ProLockedView: View {
    let feature: ProFeature

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(feature.title)
            } icon: {
                Image(systemName: feature.systemImage)
            }
        } description: {
            Text("This is part of GitOS Pro. Your trial has ended; buy Pro or enter a license key to keep using it.")
        } actions: {
            HStack {
                Button("Enter License Key…") { Licensing.shared.upsell = feature }
                Button("Buy GitOS Pro") { NSWorkspace.shared.open(Licensing.purchaseURL) }
                    .prominentButton()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.canvas)
    }
}

/// Shows `content` with Pro, otherwise the locked page for `feature`.
struct ProGate<Content: View>: View {
    let feature: ProFeature
    @ViewBuilder let content: Content

    var body: some View {
        if Licensing.shared.isPro { content } else { ProLockedView(feature: feature) }
    }
}

/// A small "PRO" mark next to things that need Pro.
struct ProBadge: View {
    var body: some View {
        Text("PRO")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(Theme.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
            .accessibilityLabel("Pro feature")
    }
}

extension View {
    /// Presents the upgrade sheet whenever a Pro feature is refused (`Licensing.require`).
    func upgradeSheet() -> some View {
        modifier(UpgradeSheetPresenter())
    }
}

private struct UpgradeSheetPresenter: ViewModifier {
    @Bindable private var licensing = Licensing.shared

    func body(content: Content) -> some View {
        content.sheet(item: $licensing.upsell) { feature in
            UpgradeSheet(feature: feature)
                .flatPresentation()
        }
    }
}

private struct UpgradeSheet: View {
    let feature: ProFeature
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: feature.systemImage).font(.title2).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(feature.title).font(.headline)
                    Text("Part of GitOS Pro").foregroundStyle(.secondary)
                }
            }
            Text("Pro adds unlimited GitHub accounts, pull requests and issues, AI commit messages and code review, the conflict editor, interactive rebase, worktrees and every theme.")
                .fixedSize(horizontal: false, vertical: true)
            LicenseKeyForm { dismiss() }
            HStack {
                Button("Not Now") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Buy GitOS Pro") { NSWorkspace.shared.open(Licensing.purchaseURL) }
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}

/// A license key field with an Activate button.
struct LicenseKeyForm: View {
    var onActivated: () -> Void = {}
    @State private var key = ""
    @State private var working = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("License key", text: $key, prompt: Text("GITOS-XXXX-XXXX-XXXX"))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(activate)
                Button(working ? "Activating…" : "Activate", action: activate)
                    .prominentButton()
                    .disabled(working || key.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(Theme.removed)
            }
        }
    }

    private func activate() {
        guard !working else { return }
        working = true
        error = nil
        Task {
            do {
                try await Licensing.shared.activate(key: key)
                onActivated()
            } catch {
                self.error = error.localizedDescription
            }
            working = false
        }
    }
}

/// Settings › License.
struct LicenseSettings: View {
    private let licensing = Licensing.shared

    var body: some View {
        Form {
            Section("Plan") {
                LabeledContent("Status") {
                    if licensing.hasLicense {
                        Text("GitOS Pro").foregroundStyle(Theme.added)
                    } else if let days = licensing.trialDaysLeft {
                        Text("Pro trial · \(days) day\(days == 1 ? "" : "s") left").foregroundStyle(Theme.modified)
                    } else {
                        Text("Free")
                    }
                }
                if let license = licensing.license, licensing.hasLicense {
                    LabeledContent("Key", value: "…" + license.key.suffix(4))
                    if let expires = license.expiresAt {
                        LabeledContent("Renews or ends", value: expires.formatted(date: .abbreviated, time: .omitted))
                    }
                    Button("Deactivate This Mac") { Task { await licensing.deactivate() } }
                        .help("Frees this Mac's activation so you can use the key on another Mac")
                } else {
                    LicenseKeyForm()
                    Button("Buy GitOS Pro") { NSWorkspace.shared.open(Licensing.purchaseURL) }
                }
            }
            Section("Free and Pro") {
                Text("Free: committing, staging lines and hunks, history and the commit graph, branches, stashes, cloning, signing, and \(Licensing.freeAccountLimit) GitHub accounts with folder rules.")
                Text("Pro: unlimited accounts, pull requests, issues and CI checks, AI commit messages and code review, the conflict editor, interactive rebase, worktrees and every theme.")
            }
            .font(.callout)
        }
        .formStyle(.grouped)
    }
}
