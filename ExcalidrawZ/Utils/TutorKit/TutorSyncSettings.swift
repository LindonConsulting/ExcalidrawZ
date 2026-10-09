//
//  TutorSyncSettings.swift
//  ExcalidrawZ
//
//  Supabase (TutorKit project) connection settings: URL in defaults, key in Keychain.
//

import Foundation
import TutorAI
import TutorSync

enum TutorSyncSettings {
    static let urlKey = "TutorSync.supabaseURL"
    /// The TutorKit project (fresh, October 2026). The old ConwyMaths project is archived and paused.
    static let defaultURL = "https://futrtkratfqoxwijgrkc.supabase.co"
    static let legacyURL = "https://vndqkdnitcxgqsiwkwpe.supabase.co"

    static var keyStore: KeychainSecretStore {
        KeychainSecretStore(service: "\(Bundle.main.bundleIdentifier ?? "com.chocoford.excalidraw").tutor-sync", account: "supabase-service-key")
    }

    static var projectURL: String {
        get {
            let stored = UserDefaults.standard.string(forKey: urlKey)
            return (stored == nil || stored == legacyURL) ? defaultURL : stored!
        }
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
