import Foundation
import Synchronization
import Testing
@testable import GitOS

struct SecretStoreTests {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SecretStoreTests-\(UUID().uuidString)")

    final class FakeKeychain: SecretStore.Legacy {
        let items: Mutex<[String: String]>
        let reads = Mutex(0)
        let readable: Bool
        init(_ items: [String: String], readable: Bool = true) { self.items = Mutex(items); self.readable = readable }
        func hasItems() -> Bool { items.withLock { !$0.isEmpty } }
        func readAll() -> [String: String] {
            reads.withLock { $0 += 1 }
            return readable ? items.withLock { $0 } : [:]  // A denied prompt reads nothing.
        }
        func delete(_ keys: [String]) { items.withLock { for k in keys { $0[k] = nil } } }
    }

    func permissions(_ url: URL) throws -> Int {
        try (FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as! NSNumber).intValue
    }

    @Test func roundTripsAcrossInstances() throws {
        let store = SecretStore(directory: dir)
        try store.set("token-1", for: "a")
        try store.set("token-2", for: "b")
        store.delete("b")
        let reopened = SecretStore(directory: dir)
        #expect(reopened.get("a") == "token-1")
        #expect(reopened.get("b") == nil)
        // Encrypted: the token isn't in the file as plain text.
        let raw = try Data(contentsOf: dir.appendingPathComponent("secrets.bin"))
        #expect(raw.range(of: Data("token-1".utf8)) == nil)
    }

    @Test func filesArePrivate() throws {
        try SecretStore(directory: dir).set("x", for: "a")
        #expect(try permissions(dir.appendingPathComponent("secrets.bin")) == 0o600)
        #expect(try permissions(dir.appendingPathComponent("secrets.key")) == 0o600)
        #expect(try permissions(dir) == 0o700)
    }

    @Test func corruptFileStartsEmptyAndRecovers() throws {
        try SecretStore(directory: dir).set("x", for: "a")
        try Data("garbage".utf8).write(to: dir.appendingPathComponent("secrets.bin"))
        let store = SecretStore(directory: dir)
        #expect(store.get("a") == nil)
        try store.set("y", for: "b")
        #expect(SecretStore(directory: dir).get("b") == "y")
    }

    @Test func missingKeyStartsEmpty() throws {
        try SecretStore(directory: dir).set("x", for: "a")
        try FileManager.default.removeItem(at: dir.appendingPathComponent("secrets.key"))
        #expect(SecretStore(directory: dir).get("a") == nil)
    }

    @Test func migratesOnceAndDeletesFromKeychain() throws {
        let keychain = FakeKeychain(["acct": "old-token", "gitos.trial-ends": "123"])
        let store = SecretStore(directory: dir, legacy: keychain)
        #expect(store.get("acct") == "old-token")
        #expect(keychain.hasItems() == false)
        // A later launch neither reads the Keychain again nor loses the values.
        let next = SecretStore(directory: dir, legacy: keychain)
        #expect(next.get("gitos.trial-ends") == "123")
        #expect(keychain.reads.withLock { $0 } == 1)
    }

    @Test func noKeychainItemsMeansNoRead() {
        let keychain = FakeKeychain([:])
        #expect(SecretStore(directory: dir, legacy: keychain).get("a") == nil)
        #expect(keychain.reads.withLock { $0 } == 0)
    }

    @Test func deniedPromptKeepsKeychainItemsAndDoesNotAskAgain() {
        let keychain = FakeKeychain(["acct": "old-token"], readable: false)
        #expect(SecretStore(directory: dir, legacy: keychain).get("acct") == nil)
        #expect(keychain.hasItems())  // Nothing lost.
        _ = SecretStore(directory: dir, legacy: keychain).get("acct")
        #expect(keychain.reads.withLock { $0 } == 1)
    }

    @Test func trialEndUsesTheEarlierCopy() {
        #expect(Licensing.earliest(200, 100) == 100)
        #expect(Licensing.earliest(nil, 100) == 100)
        #expect(Licensing.earliest(nil, nil) == nil)
    }
}
