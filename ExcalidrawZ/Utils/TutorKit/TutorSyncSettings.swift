//
//  TutorSyncSettings.swift
//  ExcalidrawZ
//
//  Supabase (ConwyMaths) connection settings: URL in defaults, key in Keychain.
//

import Foundation
import TutorAI
import TutorSync

enum TutorSyncSettings {
    static let urlKey = "TutorSync.supabaseURL"
    static let defaultURL = "https://vndqkdnitcxgqsiwkwpe.supabase.co"

    static var keyStore: KeychainSecretStore {
        KeychainSecretStore(service: "\(Bundle.main.bundleIdentifier ?? "com.chocoford.excalidraw").tutor-sync", account: "supabase-service-key")
    }

    static var projectURL: String {
        get { UserDefaults.standard.string(forKey: urlKey) ?? defaultURL }
        set { UserDefaults.standard.set(newValue, forKey: urlKey) }
    }

    static func hasKey() -> Bool { keyStore.hasValue() }
    static func saveKey(_ key: String) throws { try keyStore.save(key) }
    static func removeKey() throws { try keyStore.remove() }

    static func makeClient() throws -> SupabaseRESTClient {
        guard let key = try keyStore.load(), let url = URL(string: projectURL) else { throw SupabaseRESTClient.ClientError.notConfigured }
        return SupabaseRESTClient(baseURL: url, apiKey: key)
    }
}
