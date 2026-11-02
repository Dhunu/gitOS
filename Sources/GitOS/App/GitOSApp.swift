import SwiftUI

@main
struct GitOSApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var app = AppState()

    var body: some Scene {
        WindowGroup("GitOS", id: "main") {
            ContentView()
                .environment(app)
                .frame(minWidth: 960, minHeight: 600)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Add Local Repository…") { app.addRepositoryViaPanel() }
                    .keyboardShortcut("o")
            }
        }

        Settings {
            SettingsView()
                .environment(app)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare SwiftPM executable (outside an .app bundle).
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
