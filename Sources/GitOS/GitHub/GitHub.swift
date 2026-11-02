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

    private struct TokenResponse: Decodable {
        let accessToken: String?
        let error: String?
        let errorDescription: String?
        let interval: Int?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token", error, errorDescription = "error_description", interval
        }
    }

    static func requestCode(clientID: String) async throws -> DeviceCode {
        try await post("https://github.com/login/device/code", form: ["client_id": clientID, "scope": scopes])
    }

    static func pollForToken(clientID: String, code: DeviceCode) async throws -> String {
        var interval = max(code.interval, 5)
        let deadline = Date().addingTimeInterval(TimeInterval(code.expiresIn))
        while Date() < deadline {
            try await Task.sleep(for: .seconds(interval))
            let response: TokenResponse = try await post("https://github.com/login/oauth/access_token", form: [
                "client_id": clientID,
                "device_code": code.deviceCode,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
            ])
            if let token = response.accessToken { return token }
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
        return try JSONDecoder().decode(T.self, from: data)
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

    func user() async throws -> User { try await get("/user") }
    func emails() async throws -> [Email] { try await get("/user/emails") }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        var request = URLRequest(url: URL(string: "https://api.github.com" + path)!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw GitHubError(message: "GitHub API \(path) returned \(http.statusCode).")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
