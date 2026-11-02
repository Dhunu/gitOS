import Foundation

/// Installs the `gitos` shell command, which opens a repository in the app.
enum CLIInstaller {
    static let script = """
    #!/bin/sh
    # Opens a git repository in GitOS. Usage: gitos [path]
    target="${1:-.}"
    dir="$(cd "$target" 2>/dev/null && pwd)" || { echo "gitos: no such directory: $target" >&2; exit 1; }
    root="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || { echo "gitos: not a git repository: $dir" >&2; exit 1; }
    exec open -b com.angelsaikia.gitos "$root"

    """

    /// Candidate install locations, preferring ones already on the user's PATH.
    static var candidates: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            URL(fileURLWithPath: "/opt/homebrew/bin"),
            URL(fileURLWithPath: "/usr/local/bin"),
            home.appendingPathComponent(".local/bin"),
        ]
    }

    static var installedPath: String? {
        candidates.map { $0.appendingPathComponent("gitos").path }
            .first { FileManager.default.fileExists(atPath: $0) }
    }

    /// Writes the script to the first writable candidate and returns its path.
    static func install() throws -> String {
        let fm = FileManager.default
        for dir in candidates {
            if !fm.fileExists(atPath: dir.path) {
                guard dir.path.hasPrefix(fm.homeDirectoryForCurrentUser.path) else { continue }
                try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            guard fm.isWritableFile(atPath: dir.path) else { continue }
            let target = dir.appendingPathComponent("gitos")
            try script.write(to: target, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path)
            return target.path
        }
        throw NSError(domain: "GitOS", code: 1, userInfo: [NSLocalizedDescriptionKey: "No writable folder for the gitos command."])
    }
}
