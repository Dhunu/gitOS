import Foundation
import Sparkle

/// Installs new versions published as GitHub Releases, using the feed set in Info.plist.
@MainActor
final class AppUpdater {
    static let shared = AppUpdater()

    private let controller: SPUStandardUpdaterController?

    private init() {
        // Sparkle needs an app bundle, so it stays off under `swift run` and in tests.
        let isAppBundle = Bundle.main.bundleURL.pathExtension == "app"
        controller = isAppBundle
            ? SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
            : nil
    }

    var isAvailable: Bool { controller != nil }

    var automaticallyChecksForUpdates: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}
