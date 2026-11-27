import CryptoKit
import Foundation
import Security
import Synchronization

/// Saves tokens, API keys and license state in GitOS's own folder instead of the login Keychain,
/// so macOS never asks for the Keychain password, however a build or an update is signed.
///
/// The values sit in `secrets.bin`, encrypted with AES-GCM using a key in `secrets.key` next to it.
/// Both files are 0600 in a 0700 folder. Be clear about what that buys: other users on the Mac and
/// anyone glancing at the files (or a backup) can't read the tokens, but any program running as you
/// can read both files and decrypt them. The Keychain didn't fully stop that either (it prompted),
/// and that trade was asked for so updates never prompt.
final class SecretStore: Sendable {
    static let shared = SecretStore(
        directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GitOS"),
        legacy: LegacyKeychain())

    /// Where secrets lived before; read once, copied over and deleted.
    protocol Legacy: Sendable {
        /// The saved items, empty if they couldn't be read. Reading may make macOS prompt one last time.
        func readAll() -> [String: String]
        func hasItems() -> Bool
        func delete(_ keys: [String])
    }

    /// Set by the `gitos` CLI: it reads secrets but never writes. Its copy is loaded when it starts, so a
    /// save could undo a token the app refreshed meanwhile, and refresh tokens are single-use.
    static let readOnly = Mutex(false)

    let directory: URL
    private let legacy: Legacy?
    private let cache = Mutex<[String: String]?>(nil)

    init(directory: URL, legacy: Legacy? = nil) {
        self.directory = directory
        self.legacy = legacy
    }

    private var dataURL: URL { directory.appendingPathComponent("secrets.bin") }
    private var keyURL: URL { directory.appendingPathComponent("secrets.key") }
    private var migratedURL: URL { directory.appendingPathComponent("secrets.migrated") }

    func get(_ key: String) -> String? {
        cache.withLock { loaded(&$0)[key] }
    }

    func set(_ value: String, for key: String) throws {
        if Self.readOnly.withLock({ $0 }) { return }
        try cache.withLock {
            var values = loaded(&$0)
            values[key] = value
            try save(values)
            $0 = values
        }
    }

    func delete(_ key: String) {
        if Self.readOnly.withLock({ $0 }) { return }
        cache.withLock {
            var values = loaded(&$0)
            guard values.removeValue(forKey: key) != nil else { return }
            // Keep the old value in memory if the write fails, rather than pretend it's gone.
            if (try? save(values)) != nil { $0 = values }
        }
    }

    private func loaded(_ cache: inout [String: String]?) -> [String: String] {
        if let cache { return cache }
        var values = read()
        if !Self.readOnly.withLock({ $0 }) { migrate(into: &values) }
        cache = values
        return values
    }

    /// Copies old Keychain items over once. If macOS's prompt is denied, the items stay in the
    /// Keychain untouched and the user signs in again; it isn't retried on every launch.
    private func migrate(into values: inout [String: String]) {
        guard let legacy, !FileManager.default.fileExists(atPath: migratedURL.path) else { return }
        if legacy.hasItems() {
            let old = legacy.readAll()
            values.merge(old) { current, _ in current }
            guard !old.isEmpty else { return markMigrated() }
            do { try save(values) } catch { return }  // Nothing deleted, so it's tried again next launch.
            legacy.delete(Array(old.keys))
        }
        markMigrated()
    }

    private func markMigrated() {
        try? prepareDirectory()
        FileManager.default.createFile(atPath: migratedURL.path, contents: nil,
                                       attributes: [.posixPermissions: 0o600])
    }

    private func read() -> [String: String] {
        guard let sealed = try? Data(contentsOf: dataURL) else { return [:] }
        guard let keyData = try? Data(contentsOf: keyURL), keyData.count == 32,
              let box = try? AES.GCM.SealedBox(combined: sealed),
              let plain = try? AES.GCM.open(box, using: SymmetricKey(data: keyData)),
              let values = try? JSONDecoder().decode([String: String].self, from: plain) else {
            // Damaged or the key is gone: start empty (the user signs in again) instead of crashing.
            // The next save replaces the file.
            NSLog("GitOS: couldn't read saved credentials; starting empty.")
            return [:]
        }
        return values
    }

    private func save(_ values: [String: String]) throws {
        try prepareDirectory()
        let key = try loadOrCreateKey()
        let sealed = try AES.GCM.seal(JSONEncoder().encode(values), using: key)
        try writeAtomically(sealed.combined!, to: dataURL)
    }

    private func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }

    private func loadOrCreateKey() throws -> SymmetricKey {
        if let data = try? Data(contentsOf: keyURL), data.count == 32 { return SymmetricKey(data: data) }
        let key = SymmetricKey(size: .bits256)
        try writeAtomically(key.withUnsafeBytes { Data($0) }, to: keyURL)
        return key
    }

    /// Writes a 0600 temporary file and renames it over the old one, so the file is never
    /// half-written or briefly readable by others.
    private func writeAtomically(_ data: Data, to url: URL) throws {
        let temp = directory.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: temp.path, contents: data,
                                             attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
        guard rename(temp.path, url.path) == 0 else {
            let code = errno
            try? FileManager.default.removeItem(at: temp)
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
    }
}

/// The generic passwords older GitOS versions saved in the login Keychain.
struct LegacyKeychain: SecretStore.Legacy {
    private let service = "com.angelsaikia.gitos.github-token"

    func hasItems() -> Bool {
        // Attributes only: listing items never prompts.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    func readAll() -> [String: String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else { return [:] }
        var values: [String: String] = [:]
        for item in items {
            if let account = item[kSecAttrAccount as String] as? String,
               let data = item[kSecValueData as String] as? Data,
               let value = String(data: data, encoding: .utf8) {
                values[account] = value
            }
        }
        return values
    }

    func delete(_ keys: [String]) {
        for key in keys {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key,
            ]
            SecItemDelete(query as CFDictionary)
        }
    }
}
