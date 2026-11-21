import AppKit
import Foundation
import Observation

/// The Pro features. Each names what the upgrade sheet says the user tried to use.
enum ProFeature: String, Identifiable, Sendable {
    case accounts, pullRequests, issues, ai, conflictEditor, rebase, worktrees, themes, checks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .accounts: "More than \(Licensing.freeAccountLimit) GitHub accounts"
        case .pullRequests: "Pull requests"
        case .issues: "Issues"
        case .ai: "AI commit messages, descriptions and code review"
        case .conflictEditor: "The 3-way conflict editor"
        case .rebase: "Interactive rebase"
        case .worktrees: "Worktrees"
        case .themes: "Themes"
        case .checks: "CI checks"
        }
    }

    var systemImage: String {
        switch self {
        case .accounts: "person.2"
        case .pullRequests: "arrow.triangle.pull"
        case .issues: "smallcircle.filled.circle"
        case .ai: "sparkles"
        case .conflictEditor: "arrow.triangle.merge"
        case .rebase: "list.bullet.indent"
        case .worktrees: "square.stack.3d.up"
        case .themes: "paintpalette"
        case .checks: "checkmark.seal"
        }
    }
}

/// A Polar license key activated on this Mac, as last confirmed by Polar.
struct StoredLicense: Codable, Equatable, Sendable {
    var key: String
    var activationID: String
    var status: String
    var expiresAt: Date?
    var validatedAt: Date
}

/// Whether this Mac may use Pro: an active license, or the trial.
///
/// Licenses are Polar license keys. The app talks to Polar's public customer-portal endpoints
/// directly, so there is no GitOS server. A key is re-checked daily; without a network, the last
/// good check counts for `offlineGrace`, so Pro keeps working on a plane.
@Observable
@MainActor
final class Licensing {
    static let shared = Licensing()

    nonisolated static let freeAccountLimit = 2
    static let trialDays = 30
    /// People who used GitOS before Pro existed had every feature for free; they get longer.
    static let existingUserTrialDays = 90
    nonisolated static let offlineGrace: TimeInterval = 30 * 86_400
    static let purchaseURL = URL(string: "https://gitos.angelsaikia.com/#pricing")!

    /// Polar's ID for the GitOS organization (Polar dashboard › Settings). Licenses can't be
    /// activated until it's set.
    // shortcut: empty until the Polar organization exists; fill it in before shipping Pro.
    static let polarOrganizationID = ""

    private(set) var license: StoredLicense?
    private(set) var trialEndsAt: Date
    /// The feature whose upgrade sheet is showing, if any.
    var upsell: ProFeature?

    private static let licenseKey = "gitos.license"
    private static let trialKey = "gitos.trial-ends"

    init() {
        license = Keychain.get(Self.licenseKey).flatMap { try? JSONDecoder().decode(StoredLicense.self, from: Data($0.utf8)) }
        if let saved = Keychain.get(Self.trialKey).flatMap(Double.init) {
            trialEndsAt = Date(timeIntervalSince1970: saved)
        } else {
            // First run of a build with Pro: a saved state file means they used GitOS before.
            // (Not AppState: it asks for the license while it loads.)
            let stateFile = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("GitOS/state.json")
            let existing = FileManager.default.fileExists(atPath: stateFile.path)
            let days = existing ? Self.existingUserTrialDays : Self.trialDays
            trialEndsAt = Date().addingTimeInterval(TimeInterval(days) * 86_400)
            try? Keychain.set(String(trialEndsAt.timeIntervalSince1970), for: Self.trialKey)
        }
        // Shows the app as a free user sees it (screenshots, support). It can only take Pro away.
        if ProcessInfo.processInfo.environment["GITOS_FORCE_FREE"] != nil { trialEndsAt = .distantPast }
    }

    var isPro: Bool { Self.entitled(license: license, trialEndsAt: trialEndsAt, now: Date()) }
    var hasLicense: Bool { Self.licenseIsGood(license, now: Date()) }

    /// Whole days of trial left, or nil once it has ended.
    var trialDaysLeft: Int? {
        let left = trialEndsAt.timeIntervalSinceNow
        return left > 0 ? Int((left / 86_400).rounded(.up)) : nil
    }

    nonisolated static func entitled(license: StoredLicense?, trialEndsAt: Date, now: Date) -> Bool {
        licenseIsGood(license, now: now) || now < trialEndsAt
    }

    nonisolated static func licenseIsGood(_ license: StoredLicense?, now: Date) -> Bool {
        guard let license, license.status == "granted" else { return false }
        if let expiresAt = license.expiresAt, expiresAt <= now { return false }
        return now.timeIntervalSince(license.validatedAt) < offlineGrace
    }

    /// True when Pro is available. Otherwise shows the upgrade sheet for `feature` and returns false.
    @discardableResult
    func require(_ feature: ProFeature) -> Bool {
        if isPro { return true }
        upsell = feature
        return false
    }

    // MARK: Polar

    func activate(key: String) async throws {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !Self.polarOrganizationID.isEmpty else { throw LicenseError("Licenses can't be activated in this build.") }
        let label = Host.current().localizedName ?? "Mac"
        let activation: Activation = try await Self.post("activate", ["key": key, "organization_id": Self.polarOrganizationID,
                                                                      "label": label])
        let validated: Validated = try await Self.post("validate", ["key": key, "organization_id": Self.polarOrganizationID,
                                                                    "activation_id": activation.id])
        store(StoredLicense(key: key, activationID: activation.id, status: validated.status,
                            expiresAt: validated.expires_at, validatedAt: Date()))
        guard hasLicense else { throw LicenseError("This license key isn't active (\(validated.status)).") }
        upsell = nil
    }

    /// Frees this Mac's activation so the key can be used on another Mac.
    func deactivate() async {
        if let license, !Self.polarOrganizationID.isEmpty {
            let _: Empty? = try? await Self.post("deactivate", ["key": license.key, "organization_id": Self.polarOrganizationID,
                                                                "activation_id": license.activationID])
        }
        store(nil)
    }

    /// Re-checks the key with Polar at most once a day. Network failures keep the last result.
    func refreshIfNeeded() async {
        guard var license, !Self.polarOrganizationID.isEmpty,
              Date().timeIntervalSince(license.validatedAt) > 86_400 else { return }
        do {
            let validated: Validated = try await Self.post("validate", ["key": license.key,
                                                                        "organization_id": Self.polarOrganizationID,
                                                                        "activation_id": license.activationID])
            license.status = validated.status
            license.expiresAt = validated.expires_at
            license.validatedAt = Date()
            store(license)
        } catch let error as LicenseError where error.refused {
            // Polar answered and said no (revoked, deleted, or this activation removed).
            license.status = "revoked"
            store(license)
        } catch {}
    }

    private func store(_ license: StoredLicense?) {
        self.license = license
        if let license, let data = try? JSONEncoder().encode(license) {
            try? Keychain.set(String(decoding: data, as: UTF8.self), for: Self.licenseKey)
        } else {
            Keychain.delete(Self.licenseKey)
        }
        // A theme the user may no longer use falls back to the default, and back again.
        ThemeStore.shared.apply(AppState.shared.preferences)
    }

    private struct Activation: Decodable { let id: String }
    private struct Validated: Decodable {
        let status: String
        let expires_at: Date?
    }
    private struct Empty: Decodable {}

    struct LicenseError: LocalizedError {
        let message: String
        var refused = false
        init(_ message: String, refused: Bool = false) {
            self.message = message
            self.refused = refused
        }
        var errorDescription: String? { message }
    }

    private static func post<T: Decodable>(_ action: String, _ body: [String: String]) async throws -> T {
        var request = URLRequest(url: URL(string: "https://api.polar.sh/v1/customer-portal/license-keys/\(action)")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch code {
        case 200...299:
            if T.self == Empty.self, let empty = Empty() as? T { return empty }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { decoder in
                let text = try decoder.singleValueContainer().decode(String.self)
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = formatter.date(from: text) { return date }
                formatter.formatOptions = [.withInternetDateTime]
                if let date = formatter.date(from: text) { return date }
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: text))
            }
            return try decoder.decode(T.self, from: data)
        case 403: throw LicenseError("This key is revoked, expired, or already active on its maximum number of Macs.", refused: true)
        case 404: throw LicenseError("That license key wasn't found.", refused: true)
        default: throw LicenseError("Polar couldn't check the key (HTTP \(code)). Try again later.")
        }
    }
}
