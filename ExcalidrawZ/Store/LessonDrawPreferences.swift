//
//  LessonDrawPreferences.swift
//  ExcalidrawZ
//
//  Settings for the "New Lesson Draw" feature (calendar-aware lesson files
//  with an AI recap of the previous lesson).
//

import Foundation

enum LessonRecapBackendPreference: String, CaseIterable, Identifiable {
    case automatic
    case apple
    case anthropic
    case off

    var id: String { rawValue }

    var title: String {
        switch self {
            case .automatic: return "Automatic"
            case .apple: return "Apple Intelligence (on-device)"
            case .anthropic: return "Anthropic API"
            case .off: return "Off"
        }
    }
}

@MainActor
final class LessonDrawPreferences: ObservableObject {
    static let shared = LessonDrawPreferences()

    /// Phase 0 default: `Frankie (CMT) - Maths GCSE` → student `Frankie`, subject `Maths GCSE`.
    nonisolated static let defaultTitlePattern = #"^(.+?)\s*(?:\([^)]*\))?\s*[-–]\s*(.+)$"#
    nonisolated static let defaultModelID = "claude-opus-5-5"
    nonisolated static let defaultLookbackMinutes = 15

    @Published var titlePattern: String {
        didSet { defaults.set(titlePattern, forKey: Keys.titlePattern) }
    }
    @Published var anthropicModelID: String {
        didSet { defaults.set(anthropicModelID, forKey: Keys.anthropicModelID) }
    }
    @Published var backend: LessonRecapBackendPreference {
        didSet { defaults.set(backend.rawValue, forKey: Keys.backend) }
    }
    /// Minutes before an event's start during which it already counts as "now".
    @Published var lookbackMinutes: Int {
        didSet { defaults.set(lookbackMinutes, forKey: Keys.lookbackMinutes) }
    }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let titlePattern = "LessonDraw.titlePattern"
        static let anthropicModelID = "LessonDraw.anthropicModelID"
        static let backend = "LessonDraw.backend"
        static let lookbackMinutes = "LessonDraw.lookbackMinutes"
    }

    private init() {
        let pattern = defaults.string(forKey: Keys.titlePattern) ?? ""
        titlePattern = pattern.isEmpty ? Self.defaultTitlePattern : pattern
        let model = defaults.string(forKey: Keys.anthropicModelID) ?? ""
        anthropicModelID = model.isEmpty ? Self.defaultModelID : model
        backend = LessonRecapBackendPreference(rawValue: defaults.string(forKey: Keys.backend) ?? "") ?? .automatic
        let lookback = defaults.integer(forKey: Keys.lookbackMinutes)
        lookbackMinutes = lookback > 0 ? lookback : Self.defaultLookbackMinutes
    }

    func resetTitlePattern() {
        titlePattern = Self.defaultTitlePattern
    }
}
