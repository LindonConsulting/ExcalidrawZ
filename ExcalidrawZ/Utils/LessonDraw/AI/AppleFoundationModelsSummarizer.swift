//
//  AppleFoundationModelsSummarizer.swift
//  ExcalidrawZ
//
//  On-device recap via Apple FoundationModels (macOS 26+). Optional: probed
//  at runtime and skipped silently when Apple Intelligence is unavailable.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels

@available(macOS 26.0, iOS 26.0, *)
struct AppleFoundationModelsSummarizer: LessonRecapSummarizing {
    var displayName: String { "Apple Intelligence" }

    static func isAvailable() -> Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    static func availabilityDescription() -> String {
        switch SystemLanguageModel.default.availability {
            case .available:
                return "Available"
            case .unavailable(let reason):
                return "Unavailable (\(String(describing: reason)))"
        }
    }

    static func makeIfAvailable() async -> AppleFoundationModelsSummarizer? {
        isAvailable() ? AppleFoundationModelsSummarizer() : nil
    }

    func summarize(_ input: LessonRecapInput) async throws -> String {
        let session = LanguageModelSession(instructions: LessonRecapSummarizer.systemPrompt)
        let response = try await session.respond(to: LessonRecapSummarizer.userPrompt(for: input))
        let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw LessonRecapSummarizerError.emptyResponse }
        return text
    }
}
#endif
