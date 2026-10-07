import Foundation

public enum TutorAIError: LocalizedError {
    case noAPIKey
    case emptyResponse
    case refused(String?)
    case http(Int, String)
    case unparseable(String)

    public var errorDescription: String? {
        switch self {
            case .noAPIKey: return "No Anthropic API key is stored. Add one in Settings → Lessons."
            case .emptyResponse: return "The model returned an empty response."
            case .refused(let reason): return "The request was declined\(reason.map { ": \($0)" } ?? ".")"
            case .http(let code, let body): return "Request failed (HTTP \(code)): \(body)"
            case .unparseable(let text): return "The model's reply could not be parsed: \(text.prefix(200))"
        }
    }
}

/// Minimal Anthropic Messages API client (raw HTTP, no SDK). Text and image
/// inputs, text output. Deliberately standalone so it can later sit behind a
/// shared `AIProvider` abstraction.
public struct AnthropicMessagesClient: Sendable {
    public static let defaultModel = "claude-opus-5-5"

    public var apiKey: String
    public var model: String
    public var endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    public var maxTokens = 1024
    public var effort = "low"
    /// Seconds before URLSession gives up. Long extractions need minutes.
    public var timeout: TimeInterval = 60

    public init(apiKey: String, model: String = AnthropicMessagesClient.defaultModel) {
        self.apiKey = apiKey
        self.model = model
    }

    public enum ContentPart: Sendable {
        case text(String)
        case imagePNG(Data)

        var json: [String: Any] {
            switch self {
                case .text(let text):
                    return ["type": "text", "text": text]
                case .imagePNG(let data):
                    return ["type": "image", "source": ["type": "base64", "media_type": "image/png", "data": data.base64EncodedString()]]
            }
        }
    }

    /// Single-turn request; returns the concatenated text blocks.
    /// `cachedSystem` is sent as a system block marked for prompt caching
    /// (put large, repeated context such as a specification list there).
    public func complete(system: String?, cachedSystem: String? = nil, user: [ContentPart], session: URLSession = .shared) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")

        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "output_config": ["effort": effort],
            "fallbacks": "default",
            "messages": [["role": "user", "content": user.map(\.json)]],
        ]
        var systemBlocks: [[String: Any]] = []
        if let system { systemBlocks.append(["type": "text", "text": system]) }
        if let cachedSystem { systemBlocks.append(["type": "text", "text": cachedSystem, "cache_control": ["type": "ephemeral"]]) }
        if !systemBlocks.isEmpty { body["system"] = systemBlocks }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw TutorAIError.http(0, "No HTTP response.") }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { $0["error"] as? [String: Any] }
                .flatMap { $0["message"] as? String } ?? String(decoding: data.prefix(300), as: UTF8.self)
            throw TutorAIError.http(http.statusCode, message)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw TutorAIError.emptyResponse }
        if json["stop_reason"] as? String == "refusal" {
            throw TutorAIError.refused((json["stop_details"] as? [String: Any])?["explanation"] as? String)
        }
        let text = (json["content"] as? [[String: Any]] ?? [])
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw TutorAIError.emptyResponse }
        return text
    }

    /// Extracts the first `{...}` JSON object from a reply.
    public static func decodeJSONObject<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") else { throw TutorAIError.unparseable(text) }
        do { return try JSONDecoder().decode(type, from: Data(String(text[start...end]).utf8)) }
        catch { throw TutorAIError.unparseable(text) }
    }
}
