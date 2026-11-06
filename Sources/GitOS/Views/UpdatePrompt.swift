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
                    .buttonStyle(.borderedProminent)
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
