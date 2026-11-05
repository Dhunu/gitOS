import Foundation

/// Minimal Claude Messages API client (raw HTTP; there is no official Swift SDK).
enum Claude {
    static let keychainKey = "anthropic-api-key"
    static let defaultModel = "claude-opus-5-5"
    static let models: [(id: String, name: String)] = [
        ("claude-opus-5-5", "Claude Opus 5.5"),
        ("claude-sonnet-5-5", "Claude Sonnet 5.5"),
        ("claude-haiku-5-5", "Claude Haiku 5.5"),
    ]
    /// Inputs beyond this are refused rather than silently truncated.
    static let maxInputCharacters = 600_000

    static var apiKey: String? { Keychain.get(keychainKey) }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private struct Request: Encodable {
        struct Message: Encodable { let role: String; let content: String }
        struct OutputConfig: Encodable { let effort: String }
        let model: String
        let max_tokens: Int
        let system: String
        let messages: [Message]
        let output_config: OutputConfig
        let fallbacks: String?
    }

    private struct Response: Decodable {
        struct Block: Decodable { let type: String; let text: String? }
        let content: [Block]
        let stop_reason: String?
    }

    private struct ErrorResponse: Decodable {
        struct Detail: Decodable { let type: String; let message: String }
        let error: Detail
    }

    static func complete(system: String, prompt: String, model: String, provider: AIProvider) async throws -> String {
        guard prompt.count <= maxInputCharacters else {
            throw Failure(message: "The diff is too large to send (\(prompt.count / 1000)K characters). Commit in smaller pieces.")
        }
        if provider != .apiKey {
            return try await AICLI.complete(provider: provider, system: system, prompt: prompt, model: model)
        }
        guard let key = apiKey, !key.isEmpty else {
            throw Failure(message: "Add your Anthropic API key in Settings › AI.")
        }
        // Server-side refusal fallback is available for Opus and Sonnet, not Haiku.
        let supportsFallback = !model.contains("haiku")
        let body = Request(
            model: model,
            max_tokens: 16000,
            system: system,
            messages: [.init(role: "user", content: prompt)],
            output_config: .init(effort: "low"),
            fallbacks: supportsFallback ? "default" : nil
        )

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        if supportsFallback {
            request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        }
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            let detail = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error
            switch http.statusCode {
            case 401: throw Failure(message: "The Anthropic API key was rejected. Check it in Settings › AI.")
            case 429: throw Failure(message: "Rate limited by the Claude API. Try again in a moment.")
            default: throw Failure(message: detail.map { "\($0.type): \($0.message)" } ?? "Claude API returned \(http.statusCode).")
            }
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        if decoded.stop_reason == "refusal" {
            throw Failure(message: "Claude declined this request.")
        }
        let text = decoded.content.filter { $0.type == "text" }.compactMap(\.text).joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw Failure(message: "Claude returned an empty response.") }
        return text
    }

    /// Splits "title\n\nbody" output into its two parts.
    static func splitTitle(_ text: String) -> (title: String, body: String) {
        var lines = text.components(separatedBy: "\n")
        var title = lines.removeFirst().trimmingCharacters(in: .whitespaces)
        title = title.trimmingCharacters(in: CharacterSet(charactersIn: "#* `\""))
        return (title, lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: Prompts

    static func commitMessage(diff: String, recentSubjects: [String], model: String, provider: AIProvider) async throws -> (String, String) {
        let system = """
        You write git commit messages for the staged changes you are given. Reply with the message only: \
        a summary line of at most 72 characters in the imperative mood, then a blank line and a short plain-text \
        body explaining what changed and why. Leave the body out when the summary says it all. \
        Match the style of the repository's recent commit subjects. No markdown headings, no code fences.
        """
        let prompt = """
        Recent commit subjects in this repository:
        \(recentSubjects.prefix(15).map { "- \($0)" }.joined(separator: "\n"))

        Staged diff:
        \(diff)
        """
        return splitTitle(try await complete(system: system, prompt: prompt, model: model, provider: provider))
    }

    static func pullRequest(commits: [String], diff: String, base: String, model: String, provider: AIProvider) async throws -> (String, String) {
        let system = """
        You write GitHub pull request titles and descriptions. Reply with the title on the first line \
        (plain text, under 70 characters), a blank line, then a Markdown description: a short summary of \
        what the change does and why, a bulleted list of the notable changes, and how it was or can be tested \
        if that can be inferred. Don't invent facts the commits and diff don't support.
        """
        let prompt = """
        Base branch: \(base)

        Commits:
        \(commits.map { "---\n\($0)" }.joined(separator: "\n"))

        Diff:
        \(diff)
        """
        return splitTitle(try await complete(system: system, prompt: prompt, model: model, provider: provider))
    }
}
