import SwiftUI

/// Tells the user a downloaded update is ready. It only installs from the Restart button.
struct UpdatePrompt: View {
    let updater: AppUpdater

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.circle.fill").foregroundStyle(Theme.accent)
                Text(updater.availableVersion.map { "GitOS \($0) is ready" } ?? "An update is ready")
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
            }
            HStack(spacing: 8) {
                Button("Restart to Update") { updater.installAndRestart() }
                    .prominentButton()
                    .controlSize(.small)
                Button("Later") { updater.isPromptHidden = true }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help("You can still restart from the GitOS menu. Quitting won't install the update.")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.field, in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.separator) }
        .padding(.horizontal, 10)
    }
}

/// The update row in Settings, showing what the updater is doing.
struct UpdateStatusRow: View {
    let updater: AppUpdater

    var body: some View {
        switch updater.phase {
        case .idle:
            EmptyView()
        case .checking:
            Label("Checking for updates…", systemImage: "arrow.triangle.2.circlepath")
        case .downloading(let fraction):
            if let fraction {
                ProgressView("Downloading update…", value: fraction)
            } else {
                ProgressView("Downloading update…")
            }
        case .preparing:
            Text("Preparing update…")
        case .ready:
            HStack {
                Text(updater.availableVersion.map { "GitOS \($0) is ready to install." } ?? "An update is ready to install.")
                Spacer()
                Button("Restart to Update") { updater.installAndRestart() }
            }
        case .installing:
            Text("Installing update…")
        case .upToDate:
            Text("GitOS is up to date.").foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.modified)
        }
    }
}

/// What the Software Update window says for each step of an update. Kept apart from the view so
/// the wording and progress for every phase can be tested without Sparkle.
struct UpdateStatus: Equatable {
    enum Progress: Equatable { case none, indeterminate, fraction(Double) }

    var title: String
    var detail: String
    var progress: Progress
    var systemImage: String

    static func describe(_ phase: AppUpdater.Phase, version: String?, currentVersion: String,
                         received: UInt64, expected: UInt64, extraction: Double?) -> UpdateStatus {
        let name = version.map { "GitOS \($0)" } ?? "the update"
        switch phase {
        case .idle:
            return .init(title: "Software Update",
                         detail: "GitOS \(currentVersion) checks for updates when it opens and every hour.",
                         progress: .none, systemImage: "arrow.down.circle")
        case .checking:
            return .init(title: "Checking for updates…", detail: "Looking for a newer version of GitOS.",
                         progress: .indeterminate, systemImage: "arrow.triangle.2.circlepath")
        case .downloading(let fraction):
            let bytes = expected > 0
                ? "\(format(received)) of \(format(expected))"
                : (received > 0 ? "\(format(received)) downloaded" : "Starting the download…")
            return .init(title: "Downloading \(name)…", detail: bytes,
                         progress: fraction.map { .fraction($0) } ?? .indeterminate, systemImage: "arrow.down.circle")
        case .preparing:
            return .init(title: "Extracting \(name)…", detail: "Unpacking the download and checking its signature.",
                         progress: extraction.map { .fraction($0) } ?? .indeterminate, systemImage: "shippingbox")
        case .ready:
            return .init(title: "\(version.map { "GitOS \($0)" } ?? "An update") is ready to install",
                         detail: "Restart GitOS to finish. Your repositories, accounts and settings stay as they are. Quitting doesn't install it.",
                         progress: .fraction(1), systemImage: "checkmark.circle")
        case .installing:
            return .init(title: "Installing \(name)…", detail: "GitOS will reopen in a moment.",
                         progress: .indeterminate, systemImage: "gearshape.2")
        case .upToDate:
            return .init(title: "You're up to date", detail: "GitOS \(currentVersion) is the latest version.",
                         progress: .none, systemImage: "checkmark.seal")
        case .failed(let message):
            return .init(title: "Couldn't update GitOS", detail: message,
                         progress: .none, systemImage: "exclamationmark.triangle")
        }
    }

    private static func format(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

/// The Software Update window: opened by Check for Updates in the GitOS menu or the menu bar,
/// it follows the update through checking, downloading, extracting and installing.
struct UpdateWindow: View {
    let updater: AppUpdater
    @Environment(\.dismissWindow) private var dismissWindow

    private var status: UpdateStatus {
        UpdateStatus.describe(updater.phase, version: updater.availableVersion,
                              currentVersion: Bundle.main.shortVersion,
                              received: updater.receivedBytes, expected: updater.expectedBytes,
                              extraction: updater.extractionFraction)
    }

    var body: some View {
        let status = status
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                GitOSMark(size: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Label(status.title, systemImage: status.systemImage)
                        .font(.headline)
                        .foregroundStyle(isFailed ? Theme.modified : .primary)
                    Text(status.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            switch status.progress {
            case .none: EmptyView()
            case .indeterminate: ProgressView().progressViewStyle(.linear)
            case .fraction(let value): ProgressView(value: value).progressViewStyle(.linear)
            }
            HStack {
                Spacer()
                buttons
            }
        }
        .padding(20)
        .frame(width: 440)
        .animation(.snappy(duration: 0.2), value: status)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var buttons: some View {
        switch updater.phase {
        case .ready:
            Button("Later") {
                updater.isPromptHidden = true
                dismissWindow()
            }
            .keyboardShortcut(.cancelAction)
            Button("Restart to Update") { updater.installAndRestart() }
                .keyboardShortcut(.defaultAction)
                .prominentButton()
        case .failed:
            Button("Close") { close() }.keyboardShortcut(.cancelAction)
            Button("Try Again") { updater.checkForUpdates() }
                .keyboardShortcut(.defaultAction)
                .disabled(!updater.isAvailable)
        case .idle:
            Button("Close") { close() }.keyboardShortcut(.cancelAction)
            Button("Check for Updates") { updater.checkForUpdates() }
                .keyboardShortcut(.defaultAction)
                .disabled(!updater.isAvailable)
                .help(updater.isAvailable ? "" : "Updates only work in GitOS.app, not under swift run.")
        case .upToDate:
            Button("OK") { close() }.keyboardShortcut(.defaultAction)
        case .checking, .downloading, .preparing, .installing:
            // Sparkle keeps going in the background, so closing only hides the window.
            Button("Hide") { dismissWindow() }
                .keyboardShortcut(.cancelAction)
                .help("The update keeps going. GitOS tells you when it's ready.")
        }
    }

    private var isFailed: Bool {
        if case .failed = updater.phase { return true }
        return false
    }

    private func close() {
        updater.dismissStatus()
        dismissWindow()
    }
}

/// A one-line update status for the menu bar window, shown only while something is happening.
struct UpdateMenuBarRow: View {
    let updater: AppUpdater
    let open: () -> Void

    var body: some View {
        let status = UpdateStatus.describe(updater.phase, version: updater.availableVersion,
                                           currentVersion: Bundle.main.shortVersion,
                                           received: updater.receivedBytes, expected: updater.expectedBytes,
                                           extraction: updater.extractionFraction)
        if updater.phase != .idle {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 6) {
                    Label(status.title, systemImage: status.systemImage)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    switch status.progress {
                    case .none: EmptyView()
                    case .indeterminate: ProgressView().progressViewStyle(.linear).controlSize(.small)
                    case .fraction(let value): ProgressView(value: value).progressViewStyle(.linear).controlSize(.small)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .help("Show the Software Update window")
        }
    }
}

extension Bundle {
    /// The version people see, e.g. 0.4.4. "dev" when running outside an app bundle.
    var shortVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}

/// The GitOS menu's update item. Checking opens the Software Update window so the progress shows.
struct UpdateCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            if AppUpdater.shared.isReadyToInstall {
                Button("Restart to Update…") { AppUpdater.shared.installAndRestart() }
            } else {
                Button("Check for Updates…") {
                    openWindow(id: UpdateWindow.id)
                    AppUpdater.shared.checkForUpdates()
                }
                .disabled(!AppUpdater.shared.isAvailable)
            }
        }
    }
}

extension UpdateWindow {
    static let id = "software-update"
}
