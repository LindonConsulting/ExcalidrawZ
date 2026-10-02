//
//  AnthropicMessagesSummarizer.swift
//  ExcalidrawZ
//
//  Minimal Anthropic Messages API client (raw HTTP, no SDK) for the lesson
//  recap. The key comes from the Keychain; the user enters it in Settings.
//

import Foundation

struct AnthropicMessagesSummarizer: LessonRecapSummarizing {
    let apiKey: String
    let model: String
    var endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    var session: URLSession = .shared

    var displayName: String { "Anthropic (\(model))" }

    func summarize(_ input: LessonRecapInput) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "output_config": ["effort": "low"],
            "fallbacks": "default",
            "system": LessonRecapSummarizer.systemPrompt,
            "messages": [
                ["role": "user", "content": LessonRecapSummarizer.userPrompt(for: input)]
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LessonRecapSummarizerError.http(0, "No HTTP response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = Self.errorMessage(from: data) ?? String(decoding: data.prefix(300), as: UTF8.self)
            throw LessonRecapSummarizerError.http(http.statusCode, message)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LessonRecapSummarizerError.emptyResponse
        }
        if json["stop_reason"] as? String == "refusal" {
            let details = json["stop_details"] as? [String: Any]
            throw LessonRecapSummarizerError.refused(details?["explanation"] as? String)
        }
        let blocks = json["content"] as? [[String: Any]] ?? []
        let text = blocks
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw LessonRecapSummarizerError.emptyResponse }
        return text
    }

    private static func errorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any]
        else { return nil }
        return error["message"] as? String
    }
}
