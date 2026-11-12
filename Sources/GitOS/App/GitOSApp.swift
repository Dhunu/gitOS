import SwiftUI
import UserNotifications

@main
struct GitOSApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var app = AppState.shared

    var body: some Scene {
        WindowGroup("GitOS", id: "main") {
            ContentView()
                .environment(app)
                .themedWindow()
                .frame(minWidth: 960, minHeight: 600)
                .task { app.sync.start() }
        }
        .handlesExternalEvents(matching: [])
        .commands {
            CommandGroup(after: .appInfo) {
                if AppUpdater.shared.isReadyToInstall {
                    Button("Restart to Update…") { AppUpdater.shared.installAndRestart() }
                } else {
                    Button("Check for Updates…") { AppUpdater.shared.checkForUpdates() }
                        .disabled(!AppUpdater.shared.isAvailable)
                }
            }
            CommandGroup(after: .newItem) {
                Button("Add Local Repository…") { app.addRepositoryViaPanel() }
                    .keyboardShortcut("o")
                Button("Clone Repository…") { app.showingClone = true }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
            }
            FocusModeCommands()
            CommandMenu("Repository") {
                Button("Fetch All Repositories") { Task { await app.sync.fetchAll() } }
                    .keyboardShortcut("f", modifiers: [.command, .option])
            }
        }

        Settings {
            SettingsView()
                .environment(app)
                .themedWindow()
        }

        MenuBarExtra(isInserted: $app.preferences.showMenuBarExtra) {
            MenuBarView()
                .environment(app)
                .themedWindow()
        } label: {
            Image(nsImage: GitOSMark.menuBarImage)
                .accessibilityLabel("GitOS")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare SwiftPM executable (outside an .app bundle).
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().delegate = self
        }
        _ = AppUpdater.shared  // Checks for updates now, then every hour.
    }

    /// Quitting must not install a downloaded update, because only Restart to Update should.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated {
            let updater = AppUpdater.shared
            guard updater.hasPendingInstall else { return .terminateNow }
            // A reason means logout, restart or shutdown, which an app shouldn't hold up.
            let event = NSAppleEventManager.shared().currentAppleEvent
            if event?.attributeDescriptor(forKeyword: kAEQuitReason) != nil {
                updater.cancelPendingInstall()
                return .terminateNow
            }
            updater.cancelPendingInstallThenQuit()
            return .terminateCancel
        }
    }

    /// With the menu bar extra on, GitOS keeps running (and fetching) after its window closes.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        MainActor.assumeIsolated { !AppState.shared.preferences.showMenuBarExtra }
    }

    /// Folders opened with GitOS (e.g. by the `gitos` command) are added and selected.
    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            for url in urls where url.hasDirectoryPath || (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                await AppState.shared.addRepository(at: url)
            }
            Self.showMainWindow()
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let id = response.notification.request.content.userInfo["repoID"] as? String
        await MainActor.run {
            if let id, let uuid = UUID(uuidString: id) { AppState.shared.selectedRepoID = uuid }
            Self.showMainWindow()
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    @MainActor static func showMainWindow() {
        NSApp.activate()
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("main") == true && $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            OpenMainWindow.action?()
        }
    }
}

/// Lets AppKit code ask SwiftUI to open the main window when none is open.
@MainActor
enum OpenMainWindow {
    static var action: (() -> Void)?
}
