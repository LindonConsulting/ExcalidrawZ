//
//  QuestionTagSuggester.swift
//  ExcalidrawZ
//
//  AI tag suggestions for a captured question. Uses the Anthropic Messages
//  API (vision) with the user's own key; standalone, no LLMKit.
//

import Foundation
import os

private let qbLogger = os.Logger(subsystem: "com.lindon.questionbank", category: "tagger")

struct QuestionTagSuggestion: Decodable {
    var title: String?
    var topics: [String]?
    var board: String?
    var tier: String?
    var marks: Int?
    var source: String?
}

enum QuestionTagSuggesterError: LocalizedError {
    case noAPIKey
    case unparseable(String)

    var errorDescription: String? {
        switch self {
            case .noAPIKey: return "Add an Anthropic API key in Settings → Lessons to use AI tagging."
            case .unparseable(let text): return "The model's reply could not be parsed: \(text.prefix(200))"
        }
    }
}

struct QuestionTagSuggester {
    var apiKey: String
    var model: String
    var endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    @MainActor
    static func make(preferences: LessonDrawPreferences? = nil, keyStore: AnthropicAPIKeyStore = AnthropicAPIKeyStore()) throws -> QuestionTagSuggester {
        guard let key = try keyStore.load() else { throw QuestionTagSuggesterError.noAPIKey }
        return QuestionTagSuggester(apiKey: key, model: (preferences ?? LessonDrawPreferences.shared).anthropicModelID)
    }

    func suggest(thumbnailPNG: Data?, texts: [String]) async throws -> QuestionTagSuggestion {
        var content: [[String: Any]] = []
        if let thumbnailPNG {
            content.append([
                "type": "image",
                "source": ["type": "base64", "media_type": "image/png", "data": thumbnailPNG.base64EncodedString()],
            ])
        }
        var prompt = "Classify this maths tutoring question for a question bank."
        if !texts.isEmpty {
            prompt += "\n\nText on the canvas:\n" + texts.map { "- \($0)" }.joined(separator: "\n")
        }
        prompt += """


        Reply with JSON only, no prose, with these keys:
        {"title": short descriptive title (max 60 chars),
         "topics": 1-3 entries chosen from this list: \(QuestionBankTaxonomy.topics.joined(separator: "; ")),
         "board": one of \(QuestionBankTaxonomy.boards.joined(separator: ", ")) or "" if unknown,
         "tier": one of \(QuestionBankTaxonomy.tiers.joined(separator: ", ")) or "" if unknown,
         "marks": integer total marks if printed on the question, else null,
         "source": paper/year/question reference if visible, else ""}
        """
        content.append(["type": "text", "text": prompt])

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
            "messages": [["role": "user", "content": content]],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        qbLogger.info("tag request: model=\(model, privacy: .public) image=\(thumbnailPNG?.count ?? 0) bytes texts=\(texts.count)")
        let (data, response) = try await URLSession.shared.data(for: request)
        qbLogger.info("tag response: status=\((response as? HTTPURLResponse)?.statusCode ?? -1) bytes=\(data.count)")
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { $0["error"] as? [String: Any] }
                .flatMap { $0["message"] as? String } ?? String(decoding: data.prefix(300), as: UTF8.self)
            throw LessonRecapSummarizerError.http(code, message)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LessonRecapSummarizerError.emptyResponse
        }
        if json["stop_reason"] as? String == "refusal" {
            throw LessonRecapSummarizerError.refused((json["stop_details"] as? [String: Any])?["explanation"] as? String)
        }
        let text = (json["content"] as? [[String: Any]] ?? [])
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .joined()
        qbLogger.info("tag reply: \(text, privacy: .public)")
        return try Self.parse(text)
    }

    static func parse(_ text: String) throws -> QuestionTagSuggestion {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") else {
            throw QuestionTagSuggesterError.unparseable(text)
        }
        let slice = String(text[start...end])
        do {
            return try JSONDecoder().decode(QuestionTagSuggestion.self, from: Data(slice.utf8))
        } catch {
            throw QuestionTagSuggesterError.unparseable(text)
        }
    }
}
