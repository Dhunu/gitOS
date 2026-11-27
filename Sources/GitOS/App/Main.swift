import Foundation

/// Runs a `gitos` command-line request and exits, or starts the app.
@main
enum Main {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if let command = arguments.first, GitOSCLI.commands.contains(command) {
            SecretStore.readOnly.withLock { $0 = true }
            let status = MainActor.assumeIsolated { GitOSCLI.run(command, Array(arguments.dropFirst())) }
            exit(status)
        }
        GitOSApp.main()
    }
}
