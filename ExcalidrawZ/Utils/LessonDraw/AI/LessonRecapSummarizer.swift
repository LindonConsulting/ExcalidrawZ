//
//  LessonRecapSummarizer.swift
//  ExcalidrawZ
//
//  Standalone summarizer for the "New Lesson Draw" recap. Deliberately
//  independent of LLMKit / the hosted AI so it can later become the first
//  consumer of a shared `AIProvider` abstraction (issue #6).
//

import Foundation

/// What the summarizer sees from the previous lesson's canvas.
struct LessonRecapInput: Sendable {
    var student: String
    var subject: String?
    var previousLessonDate: Date
    /// Text elements in reading order (top-to-bottom, left-to-right).
    var texts: [String]
    /// Counts by element type (`rectangle`, `arrow`, `freedraw`, ...).
    var elementCounts: [String: Int]

    var isEmpty: Bool { texts.isEmpty && elementCounts.isEmpty }
}

protocol LessonRecapSummarizing: Sendable {
    var displayName: String { get }
    func summarize(_ input: LessonRecapInput) async throws -> String
}

enum LessonRecapSummarizerError: LocalizedError {
    case noBackendAvailable
    case emptyResponse
    case refused(String?)
    case http(Int, String)

    var errorDescription: String? {
        switch self {
            case .noBackendAvailable:
                return "No recap backend is available. Add an Anthropic API key in Settings → Lessons, or enable Apple Intelligence."
            case .emptyResponse:
                return "The recap backend returned an empty response."
            case .refused(let reason):
                return "The recap request was declined\(reason.map { ": \($0)" } ?? ".")"
            case .http(let code, let body):
                return "Recap request failed (HTTP \(code)): \(body)"
        }
    }
}

enum LessonRecapSummarizer {
    /// Picks a backend according to the user's preference and what is
    /// actually available on this machine. Returns `nil` when recaps are
    /// off or nothing usable exists; callers still create the file.
    @MainActor
    static func resolve(
        preferences: LessonDrawPreferences? = nil,
        keyStore: AnthropicAPIKeyStore = AnthropicAPIKeyStore()
    ) async -> (any LessonRecapSummarizing)? {
        let preferences = preferences ?? LessonDrawPreferences.shared
        switch preferences.backend {
            case .off:
                return nil
            case .apple:
                return await appleBackend()
            case .anthropic:
                return anthropicBackend(preferences: preferences, keyStore: keyStore)
            case .automatic:
                if let apple = await appleBackend() { return apple }
                return anthropicBackend(preferences: preferences, keyStore: keyStore)
        }
    }

    static func appleBackend() async -> (any LessonRecapSummarizing)? {
#if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *) {
            return await AppleFoundationModelsSummarizer.makeIfAvailable()
        }
#endif
        return nil
    }

    @MainActor
    static func anthropicBackend(
        preferences: LessonDrawPreferences,
        keyStore: AnthropicAPIKeyStore
    ) -> (any LessonRecapSummarizing)? {
        guard let key = try? keyStore.load() else { return nil }
        return AnthropicMessagesSummarizer(apiKey: key, model: preferences.anthropicModelID)
    }

    // MARK: - Shared prompt

    static let systemPrompt = """
    You write a short recap of a tutoring lesson for the tutor to glance at when the next lesson starts. \
    You are given the text written on the previous lesson's whiteboard plus rough counts of drawn shapes. \
    Reply with plain text only, no markdown, at most 8 short lines, in exactly this shape:

    Last time: <one or two lines on what was covered>
    To revisit: <two to four bullet-like lines, each starting with "- ", on things worth checking or continuing>

    If the whiteboard text is too thin to tell, say so briefly in the "Last time" line and suggest one general check-in under "To revisit". Do not invent topics that are not supported by the text.
    """

    static func userPrompt(for input: LessonRecapInput) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        var lines: [String] = []
        lines.append("Student: \(input.student)")
        if let subject = input.subject { lines.append("Subject: \(subject)") }
        lines.append("Previous lesson: \(formatter.string(from: input.previousLessonDate))")
        let counts = input.elementCounts
            .sorted { $0.key < $1.key }
            .map { "\($0.key)×\($0.value)" }
            .joined(separator: ", ")
        lines.append("Canvas elements: \(counts.isEmpty ? "none" : counts)")
        lines.append("")
        lines.append("Whiteboard text (reading order):")
        if input.texts.isEmpty {
            lines.append("(no text on the canvas)")
        } else {
            for text in input.texts {
                lines.append("- " + text.replacingOccurrences(of: "\n", with: " / "))
            }
        }
        return lines.joined(separator: "\n")
    }
}
