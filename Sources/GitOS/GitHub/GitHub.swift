import Foundation

struct GitHubError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// OAuth device flow: https://docs.github.com/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps#device-flow
enum GitHubDeviceFlow {
    static let scopes = "repo read:org workflow user:email"

    struct DeviceCode: Decodable, Sendable {
        let deviceCode: String
        let userCode: String
        let verificationURI: URL
        let expiresIn: Int
        let interval: Int

        enum CodingKeys: String, CodingKey {
            case deviceCode = "device_code", userCode = "user_code", verificationURI = "verification_uri"
            case expiresIn = "expires_in", interval
        }
    }

    /// What GitHub issues at sign-in. Apps with token expiration on also get a refresh token.
    struct TokenGrant: Sendable, Equatable {
        let accessToken: String
        let refreshToken: String?
        let expiresAt: Date?
    }

    /// GitHub refused the refresh token, so only signing in again can help.
    struct RefreshRefused: Error {}

    struct TokenResponse: Decodable {
        let accessToken: String?
        let refreshToken: String?
        let expiresIn: Int?
        let error: String?
        let errorDescription: String?
        let interval: Int?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token", refreshToken = "refresh_token", expiresIn = "expires_in"
            case error, errorDescription = "error_description", interval
        }

        func grant(now: Date = .now) -> TokenGrant? {
            accessToken.map { token in
                TokenGrant(accessToken: token, refreshToken: refreshToken,
                           expiresAt: expiresIn.map { now.addingTimeInterval(TimeInterval($0)) })
            }
        }
    }

    static func requestCode(clientID: String) async throws -> DeviceCode {
        try await post("https://github.com/login/device/code", form: ["client_id": clientID, "scope": scopes])
    }

    static func pollForToken(clientID: String, code: DeviceCode) async throws -> TokenGrant {
        var interval = max(code.interval, 5)
        let deadline = Date().addingTimeInterval(TimeInterval(code.expiresIn))
        while Date() < deadline {
            try await Task.sleep(for: .seconds(interval))
            let response: TokenResponse = try await post("https://github.com/login/oauth/access_token", form: [
                "client_id": clientID,
                "device_code": code.deviceCode,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
            ])
            if let grant = response.grant() { return grant }
            switch response.error {
            case "authorization_pending": continue
            case "slow_down": interval = response.interval ?? interval + 5
            case "access_denied": throw GitHubError(message: "Sign-in was cancelled on GitHub.")
            case "expired_token": throw GitHubError(message: "The code expired. Start again.")
            default: throw GitHubError(message: response.errorDescription ?? response.error ?? "Sign-in failed.")
            }
        }
        throw GitHubError(message: "The code expired. Start again.")
    }

    /// Device-flow tokens can be refreshed without a client secret, which a desktop app can't keep.
    static func refresh(clientID: String, refreshToken: String) async throws -> TokenGrant {
        let response: TokenResponse = try await post("https://github.com/login/oauth/access_token", form: [
            "client_id": clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
        ])
        guard let grant = response.grant() else { throw RefreshRefused() }
        return grant
    }

    private static func post<T: Decodable>(_ url: String, form: [String: String]) async throws -> T {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = Data((components.percentEncodedQuery ?? "").utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw GitHubError(message: "GitHub returned \(http.statusCode). Check the OAuth app's Client ID and that Device Flow is enabled.")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }
}

struct GitHubAPI: Sendable {
    let token: String

    struct User: Decodable, Sendable {
        let id: Int
        let login: String
        let name: String?
        let avatarURL: URL?
        enum CodingKeys: String, CodingKey { case id, login, name, avatarURL = "avatar_url" }
    }

    struct Email: Decodable, Sendable {
        let email: String
        let primary: Bool
        let verified: Bool
    }

    struct Repository: Decodable, Identifiable, Hashable, Sendable {
        struct Owner: Decodable, Hashable, Sendable { let login: String }
        let id: Int
        let name: String
        let fullName: String
        let owner: Owner
        let isPrivate: Bool
        let fork: Bool
        let description: String?
        let cloneURL: String
        let pushedAt: Date?

        enum CodingKeys: String, CodingKey {
            case id, name, owner, fork, description
            case fullName = "full_name", isPrivate = "private", cloneURL = "clone_url", pushedAt = "pushed_at"
        }
    }

    func user() async throws -> User { try await get("/user") }
    func emails() async throws -> [Email] { try await get("/user/emails") }

    /// Every repo the account can access (own, collaborator, org member), most recently pushed first.
    func repositories(maxPages: Int = 10) async throws -> [Repository] {
        var all: [Repository] = []
        for page in 1...maxPages {
            let batch: [Repository] = try await get(
                "/user/repos?per_page=100&page=\(page)&sort=pushed&affiliation=owner,collaborator,organization_member")
            all += batch
            if batch.count < 100 { break }
        }
        return all
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        try await send("GET", path, body: Optional<[String: String]>.none)
    }

    func send<T: Decodable, Body: Encodable>(_ method: String, _ path: String, body: Body?) async throws -> T {
        var request = URLRequest(url: URL(string: "https://api.github.com" + path)!)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            let detail = (try? JSONDecoder().decode(APIErrorBody.self, from: data)).map { error in
                ([error.message] + (error.errors ?? []).map(\.message)).compactMap { $0 }.joined(separator: ": ")
            }
            throw GitHubError(message: detail?.nilIfEmpty ?? "GitHub API \(path) returned \(http.statusCode).")
        }
        return try GitHubAPI.decoder.decode(T.self, from: data)
    }

    /// GitHub puts the useful part of an error in "message" and per-field "errors".
    private struct APIErrorBody: Decodable {
        struct Detail: Decodable { let message: String? }
        let message: String?
        let errors: [Detail]?
    }

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
