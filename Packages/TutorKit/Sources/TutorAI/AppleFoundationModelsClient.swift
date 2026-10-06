import Foundation

#if canImport(FoundationModels)
import FoundationModels

/// On-device text model (macOS 26+). Text-only.
@available(macOS 26.0, iOS 26.0, *)
public struct AppleFoundationModelsClient: Sendable {
    public init() {}

    public static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    public static var availabilityDescription: String {
        switch SystemLanguageModel.default.availability {
            case .available: return "Available"
            case .unavailable(let reason): return "Unavailable (\(String(describing: reason)))"
        }
    }

    public func complete(instructions: String, prompt: String) async throws -> String {
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: prompt)
        let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw TutorAIError.emptyResponse }
        return text
    }
}
#endif
