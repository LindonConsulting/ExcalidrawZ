//
//  AnthropicAPIKeyStore.swift
//  ExcalidrawZ
//
//  Keychain storage for the user's own Anthropic API key used by the lesson
//  recap summarizer. Follows the WebDAVCredentialStore pattern.
//

import Foundation
import Security

struct AnthropicAPIKeyStore: Sendable {
    private let service: String
    private let account = "anthropic-api-key"

    init(bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.chocoford.excalidraw") {
        self.service = "\(bundleIdentifier).lesson-draw.anthropic"
    }

    func load() throws -> String? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(baseQuery.merging([
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]) { _, new in new } as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw keychainError(status) }
        let key = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
    }

    func hasKey() -> Bool {
        (try? load()) != nil
    }

    func save(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try remove()
            return
        }
        let data = Data(trimmed.utf8)
        let status = SecItemAdd(baseQuery.merging([
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]) { _, new in new } as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updateStatus = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            guard updateStatus == errSecSuccess else { throw keychainError(updateStatus) }
        } else if status != errSecSuccess {
            throw keychainError(status)
        }
    }

    func remove() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw keychainError(status) }
    }

    private var baseQuery: [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        // Deliberately not `kSecUseDataProtectionKeychain`: that keychain
        // requires an application-identifier entitlement, which ad-hoc signed
        // local builds don't have (errSecMissingEntitlement on save).
        return query
    }

    private func keychainError(_ status: OSStatus) -> Error {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
        return NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Keychain error: \(message)"])
    }
}
