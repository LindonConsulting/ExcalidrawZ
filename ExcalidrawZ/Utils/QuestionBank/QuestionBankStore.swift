//
//  QuestionBankStore.swift
//  ExcalidrawZ
//
//  Local, file-based storage for the question bank:
//  <Application Support>/QuestionBank/index.json plus one folder per question
//  with elements.json, files.json (Excalidraw binary files) and thumb.png.
//  Deliberately outside Core Data (which is CloudKit-mirrored).
//

import Foundation
import Combine

@MainActor
final class QuestionBankStore: ObservableObject {
    static let shared = QuestionBankStore()

    @Published private(set) var entries: [QuestionBankEntry] = []
    @Published private(set) var loadError: Error?

    private let fileManager = FileManager.default
    private var didLoad = false

    enum StoreError: LocalizedError {
        case missingEntry
        case directoryUnavailable

        var errorDescription: String? {
            switch self {
                case .missingEntry: return "That question is no longer in the bank."
                case .directoryUnavailable: return "The question bank folder could not be created."
            }
        }
    }

    private struct Index: Codable {
        var version: Int = 1
        var entries: [QuestionBankEntry]
    }

    // MARK: - Paths

    var rootURL: URL {
        get throws {
            let base = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let url = base.appendingPathComponent("QuestionBank", isDirectory: true)
            if !fileManager.fileExists(atPath: url.path) {
                try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            }
            return url
        }
    }

    private var indexURL: URL { get throws { try rootURL.appendingPathComponent("index.json") } }

    func folderURL(for id: UUID) throws -> URL {
        try rootURL.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    func thumbnailURL(for id: UUID) -> URL? {
        guard let url = try? folderURL(for: id).appendingPathComponent("thumb.png"),
              fileManager.fileExists(atPath: url.path) else { return nil }
        return url
    }

    // MARK: - Loading / saving

    func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        do {
            let url = try indexURL
            guard fileManager.fileExists(atPath: url.path) else { return }
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            entries = try decoder.decode(Index.self, from: data).entries
        } catch {
            loadError = error
        }
    }

    private func persistIndex() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(Index(entries: entries))
        try data.write(to: try indexURL, options: .atomic)
    }

    // MARK: - Mutations

    /// Stores a new question. `elements` and `files` are raw Excalidraw JSON.
    func add(
        _ entry: QuestionBankEntry,
        elementsJSON: Data,
        filesJSON: Data?,
        thumbnailPNG: Data?
    ) throws {
        let folder = try folderURL(for: entry.id)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        try elementsJSON.write(to: folder.appendingPathComponent("elements.json"), options: .atomic)
        if let filesJSON {
            try filesJSON.write(to: folder.appendingPathComponent("files.json"), options: .atomic)
        }
        var entry = entry
        if let thumbnailPNG {
            try thumbnailPNG.write(to: folder.appendingPathComponent("thumb.png"), options: .atomic)
            if entry.imageHash == nil { entry.imageHash = QuestionImageHash.hash(png: thumbnailPNG) }
        }
        entries.insert(entry, at: 0)
        try persistIndex()
    }

    func update(_ entry: QuestionBankEntry) throws {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { throw StoreError.missingEntry }
        entries[index] = entry
        try persistIndex()
    }

    func delete(_ id: UUID) throws {
        entries.removeAll { $0.id == id }
        try persistIndex()
        if let folder = try? folderURL(for: id), fileManager.fileExists(atPath: folder.path) {
            try? fileManager.removeItem(at: folder)
        }
    }

    func recordUse(of id: UUID, student: String, lessonFileID: String?) throws {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { throw StoreError.missingEntry }
        let name = student.trimmingCharacters(in: .whitespaces)
        entries[index].uses.append(QuestionUse(date: .now, student: name.isEmpty ? "Unknown" : name, lessonFileID: lessonFileID))
        try persistIndex()
    }

    func removeUse(_ use: QuestionUse, from id: UUID) throws {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { throw StoreError.missingEntry }
        entries[index].uses.removeAll { $0.id == use.id }
        try persistIndex()
    }

    // MARK: - Payload access

    func elementsJSON(for id: UUID) throws -> Data {
        try Data(contentsOf: try folderURL(for: id).appendingPathComponent("elements.json"))
    }

    func filesJSON(for id: UUID) -> Data? {
        guard let url = try? folderURL(for: id).appendingPathComponent("files.json") else { return nil }
        return try? Data(contentsOf: url)
    }

    func thumbnailPNG(for id: UUID) -> Data? {
        guard let url = thumbnailURL(for: id) else { return nil }
        return try? Data(contentsOf: url)
    }

    /// Entries whose thumbnail hash is within the duplicate threshold of `hash`.
    func likelyDuplicates(ofHash hash: String, excluding id: UUID? = nil) -> [QuestionBankEntry] {
        entries.filter { entry in
            guard entry.id != id, let other = entry.imageHash else { return false }
            return QuestionImageHash.distance(hash, other) <= QuestionImageHash.duplicateThreshold
        }
    }

    /// All distinct students seen in the usage log, for the filter menu.
    var knownStudents: [String] {
        Array(Set(entries.flatMap { $0.uses.map(\.student) })).sorted()
    }
}
