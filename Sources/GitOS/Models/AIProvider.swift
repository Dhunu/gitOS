import Foundation

/// Where AI text comes from: a CLI the user is already signed in to, or an Anthropic API key.
enum AIProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case claudeCode, codex, apiKey

    var id: String { rawValue }

    var name: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .apiKey: "Anthropic API key"
        }
    }

    var command: String? {
        switch self {
        case .claudeCode: "claude"
        case .codex: "codex"
        case .apiKey: nil
        }
    }

    var installURL: URL? {
        switch self {
        case .claudeCode: URL(string: "https://claude.com/product/claude-code")
        case .codex: URL(string: "https://developers.openai.com/codex/cli")
        case .apiKey: nil
        }
    }

    /// A CLI's install and sign-in are checked when it runs, so its errors can say what to do.
    var isReady: Bool { self != .apiKey || Claude.apiKey != nil }
}
