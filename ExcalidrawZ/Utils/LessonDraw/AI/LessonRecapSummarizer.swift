//
//  LessonRecapSummarizer.swift
//  ExcalidrawZ
//
//  Picks a recap backend (Apple on-device or Anthropic) and runs the recap
//  prompt from TutorAI.
//

import Foundation
import TutorAI

typealias LessonRecapInput = TutorPrompts.RecapInput

extension LessonRecapInput {
    var isEmpty: Bool { texts.isEmpty && elementCounts.isEmpty }
}

protocol LessonRecapSummarizing: Sendable {
    var displayName: String { get }
    func summarize(_ input: LessonRecapInput) async throws -> String
}

typealias LessonRecapSummarizerError = TutorAIError

enum LessonRecapSummarizer {
    @MainActor
    static func resolve(preferences: LessonDrawPreferences? = nil) async -> (any LessonRecapSummarizing)? {
        let preferences = preferences ?? LessonDrawPreferences.shared
        switch preferences.backend {
            case .off: return nil
            case .apple: return appleBackend()
            case .anthropic: return anthropicBackend(preferences: preferences)
            case .automatic: return appleBackend() ?? anthropicBackend(preferences: preferences)
        }
    }

    static func appleBackend() -> (any LessonRecapSummarizing)? {
#if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *), AppleFoundationModelsClient.isAvailable {
            return AppleRecapSummarizer()
        }
#endif
        return nil
    }

    static var appleAvailabilityDescription: String {
#if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *) { return AppleFoundationModelsClient.availabilityDescription }
#endif
        return "Requires macOS 26"
    }

    @MainActor
    static func anthropicBackend(preferences: LessonDrawPreferences) -> (any LessonRecapSummarizing)? {
        guard let client = try? AnthropicAPIKeyStore.makeClient(preferences: preferences) else { return nil }
        return AnthropicRecapSummarizer(client: client)
    }
}

struct AnthropicRecapSummarizer: LessonRecapSummarizing {
    let client: AnthropicMessagesClient
    var displayName: String { "Anthropic (\(client.model))" }

    func summarize(_ input: LessonRecapInput) async throws -> String {
        try await client.complete(system: TutorPrompts.recapSystem, user: [.text(TutorPrompts.recapUser(input))])
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, iOS 26.0, *)
struct AppleRecapSummarizer: LessonRecapSummarizing {
    var displayName: String { "Apple Intelligence" }

    func summarize(_ input: LessonRecapInput) async throws -> String {
        try await AppleFoundationModelsClient().complete(instructions: TutorPrompts.recapSystem, prompt: TutorPrompts.recapUser(input))
    }
}
#endif
