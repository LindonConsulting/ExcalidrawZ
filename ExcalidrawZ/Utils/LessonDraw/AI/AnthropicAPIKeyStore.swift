//
//  AnthropicAPIKeyStore.swift
//  ExcalidrawZ
//
//  The user's Anthropic API key, in the login keychain (service/account kept
//  stable across versions so stored keys survive).
//

import Foundation
import TutorAI

enum AnthropicAPIKeyStore {
    static var store: KeychainSecretStore {
        KeychainSecretStore(
            service: "\(Bundle.main.bundleIdentifier ?? "com.chocoford.excalidraw").lesson-draw.anthropic",
            account: "anthropic-api-key"
        )
    }

    static func load() throws -> String? { try store.load() }
    static func hasKey() -> Bool { store.hasValue() }
    static func save(_ key: String) throws { try store.save(key) }
    static func remove() throws { try store.remove() }

    /// A Messages client using the stored key and the configured model, or nil when no key is stored.
    @MainActor
    static func makeClient(preferences: LessonDrawPreferences? = nil) throws -> AnthropicMessagesClient? {
        guard let key = try load() else { return nil }
        return AnthropicMessagesClient(apiKey: key, model: (preferences ?? LessonDrawPreferences.shared).anthropicModelID)
    }
}
