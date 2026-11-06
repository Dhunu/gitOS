import AppKit
import Observation
@preconcurrency import Sparkle

/// Finds and downloads new versions from GitHub Releases, then waits for the user to restart.
///
/// This drives Sparkle directly because its automatic mode installs silently on quit. Here an
/// update only installs when the user chooses Restart to Update.
@MainActor
@Observable
final class AppUpdater: NSObject {
    static let shared = AppUpdater()

    enum Phase: Equatable {
        case idle
        case checking
        case downloading(fraction: Double?)
        case preparing
        case ready
        case installing
        case upToDate
        case failed(String)
    }

    private(set) var phase = Phase.idle
    private(set) var availableVersion: String?
    /// "Later" hides the prompt for this update. It stays in the GitOS menu and Settings.
    var isPromptHidden = false

    @ObservationIgnored private var updater: SPUUpdater?
    @ObservationIgnored private var installReply: ((SPUUserUpdateChoice) -> Void)?
    @ObservationIgnored private var isUserInitiated = false
    @ObservationIgnored private var isCancelling = false
    @ObservationIgnored private var isQuitWaiting = false
    @ObservationIgnored private var expectedBytes: UInt64 = 0
    @ObservationIgnored private var receivedBytes: UInt64 = 0

    /// Pass false to test the update flow without a running updater.
    init(starting: Bool = true) {
        super.init()
        // Sparkle needs an app bundle, so it stays off under `swift run` and in tests.
        guard starting, Bundle.main.bundleURL.pathExtension == "app" else { return }
        let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: self, delegate: nil)
        guard (try? updater.start()) != nil else { return }
        self.updater = updater
        if updater.automaticallyChecksForUpdates { updater.checkForUpdatesInBackground() }
    }

    var isAvailable: Bool { updater != nil }
    var isReadyToInstall: Bool { phase == .ready }
    var showsPrompt: Bool { isReadyToInstall && !isPromptHidden }

    var automaticallyChecksForUpdates: Bool {
        get { updater?.automaticallyChecksForUpdates ?? false }
        set { updater?.automaticallyChecksForUpdates = newValue }
    }

    func checkForUpdates() {
        updater?.checkForUpdates()
    }

    func installAndRestart() {
        guard let reply = installReply else { return }
        installReply = nil
        phase = .installing
        reply(.install)
    }

    var hasPendingInstall: Bool { installReply != nil }

    /// Stops a downloaded update from installing when the app quits, then quits. Sparkle would
    /// otherwise install it anyway. This version isn't skipped, so it's offered again next launch.
    ///
    /// The installer is a separate process that outlives the app, and Sparkle only sends it the
    /// cancel from the main queue. So the first quit is refused, and this quits again after that.
    func cancelPendingInstallThenQuit() {
        guard let reply = installReply else { return }
        installReply = nil
        isQuitWaiting = true
        reply(.skip)
        Task {
            try? await Task.sleep(for: .seconds(2))
            self.quitIfWaiting()
        }
    }

    /// For logout and shutdown, where refusing to quit would stop the Mac. Those arrive as Apple
    /// events rather than from the main queue, so waiting here lets the cancel go out.
    func cancelPendingInstall(timeout: TimeInterval = 2, settle: TimeInterval = 0.3) {
        guard let reply = installReply else { return }
        installReply = nil
        isCancelling = true
        reply(.skip)

        let deadline = Date.now.addingTimeInterval(timeout)
        while isCancelling, Date.now < deadline {
            RunLoop.main.run(mode: .default, before: .now.addingTimeInterval(0.02))
        }
        isCancelling = false
        RunLoop.main.run(mode: .default, before: .now.addingTimeInterval(settle))
    }

    private func quitIfWaiting() {
        guard isQuitWaiting else { return }
        isQuitWaiting = false
        // Gives the cancel time to reach the installer before this process goes away.
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            NSApplication.shared.terminate(nil)
        }
    }

    func dismissStatus() {
        if phase == .upToDate || isFailed { phase = .idle }
    }

    private var isFailed: Bool {
        if case .failed = phase { return true }
        return false
    }
}

extension AppUpdater: SPUUserDriver {
    nonisolated func show(_ request: SPUUpdatePermissionRequest,
                          reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
    }

    nonisolated func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        MainActor.assumeIsolated {
            isUserInitiated = true
            phase = .checking
        }
    }

    nonisolated func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState,
                                     reply: @escaping (SPUUserUpdateChoice) -> Void) {
        nonisolated(unsafe) let reply = reply
        let version = appcastItem.displayVersionString
        let isInformationOnly = appcastItem.isInformationOnlyUpdate
        let isInstalling = state.stage == .installing
        MainActor.assumeIsolated {
            availableVersion = version
            if isInformationOnly {
                reply(.dismiss)
            } else if isInstalling {
                // Replying install here would relaunch at once, so ask first.
                installReply = reply
                isPromptHidden = false
                phase = .ready
            } else {
                reply(.install)
            }
        }
    }

    nonisolated func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

    nonisolated func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}

    nonisolated func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        MainActor.assumeIsolated {
            if isUserInitiated { phase = .upToDate }
        }
        acknowledgement()
    }

    nonisolated func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        let message = error.localizedDescription
        MainActor.assumeIsolated {
            // A failed background check shouldn't interrupt anyone. The next one tries again.
            phase = isUserInitiated ? .failed(message) : .idle
        }
        acknowledgement()
    }

    nonisolated func showDownloadInitiated(cancellation: @escaping () -> Void) {
        MainActor.assumeIsolated {
            expectedBytes = 0
            receivedBytes = 0
            phase = .downloading(fraction: nil)
        }
    }

    nonisolated func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        MainActor.assumeIsolated { expectedBytes = expectedContentLength }
    }

    nonisolated func showDownloadDidReceiveData(ofLength length: UInt64) {
        MainActor.assumeIsolated {
            receivedBytes += length
            phase = .downloading(fraction: Self.fraction(received: receivedBytes, expected: expectedBytes))
        }
    }

    nonisolated func showDownloadDidStartExtractingUpdate() {
        MainActor.assumeIsolated { phase = .preparing }
    }

    nonisolated func showExtractionReceivedProgress(_ progress: Double) {}

    nonisolated func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        nonisolated(unsafe) let reply = reply
        MainActor.assumeIsolated {
            installReply = reply
            isPromptHidden = false
            phase = .ready
        }
    }

    nonisolated func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool,
                                          retryTerminatingApplication: @escaping () -> Void) {
        MainActor.assumeIsolated { phase = .installing }
    }

    nonisolated func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        acknowledgement()
    }

    nonisolated func showUpdateInFocus() {}

    nonisolated func dismissUpdateInstallation() {
        MainActor.assumeIsolated {
            isUserInitiated = false
            installReply = nil
            if phase != .upToDate, !isFailed { phase = .idle }
            isCancelling = false
            quitIfWaiting()
        }
    }

    nonisolated static func fraction(received: UInt64, expected: UInt64) -> Double? {
        expected > 0 ? min(Double(received) / Double(expected), 1) : nil
    }
}

extension AppUpdater {
    /// Test seam: stands in for Sparkle reporting a downloaded update.
    func simulateReady(version: String, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        availableVersion = version
        installReply = reply
        isPromptHidden = false
        phase = .ready
    }
}
