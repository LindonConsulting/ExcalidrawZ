import Foundation
import GRDB
import TutorModels

/// Export / restore of the whole TutorKit store (SQLite + media) as a folder,
/// plus rolling automatic backups. Used for moving data between machines.
public struct TutorBackupManager: Sendable {
    public static let databaseFileName = TutorDatabase.databaseFileName
    public static let manifestFileName = "manifest.json"
    public static let folderPrefix = "TutorKit-Backup-"

    public struct Manifest: Codable, Sendable {
        public var version = 1
        public var createdAt: Date
        public var hostName: String
        public var questionCount: Int
        public var studentCount: Int
    }

    public enum BackupError: LocalizedError {
        case notABackup
        public var errorDescription: String? { "That folder is not a TutorKit backup (missing tutor.sqlite or manifest.json)." }
    }

    public let database: TutorDatabase

    public init(database: TutorDatabase) { self.database = database }

    /// Writes `<destination>/TutorKit-Backup-<timestamp>/` and returns it.
    @discardableResult
    public func exportBackup(to destination: URL, now: Date = .now) throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        let folder = destination.appendingPathComponent(Self.folderPrefix + formatter.string(from: now), isDirectory: true)
        let fm = FileManager.default
        try? fm.removeItem(at: folder)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)

        // Consistent SQLite copy via the online backup API.
        let target = try DatabaseQueue(path: folder.appendingPathComponent(Self.databaseFileName).path)
        try database.writer.backup(to: target)

        if fm.fileExists(atPath: database.media.directory.path) {
            try fm.copyItem(at: database.media.directory, to: folder.appendingPathComponent("media", isDirectory: true))
        }
        let manifest = Manifest(
            createdAt: now,
            hostName: ProcessInfo.processInfo.hostName,
            questionCount: try database.questions(includeArchived: true).count,
            studentCount: try database.students(includeArchived: true).count
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: folder.appendingPathComponent(Self.manifestFileName), options: .atomic)
        return folder
    }

    public static func manifest(of folder: URL) -> Manifest? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(manifestFileName)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Manifest.self, from: data)
    }

    /// Replaces the live database contents and media with the backup's.
    /// Takes a safety backup into `safetyDirectory` first when given.
    public func restoreBackup(from folder: URL, safetyDirectory: URL? = nil) throws {
        let fm = FileManager.default
        let sqlite = folder.appendingPathComponent(Self.databaseFileName)
        guard fm.fileExists(atPath: sqlite.path), Self.manifest(of: folder) != nil else { throw BackupError.notABackup }
        if let safetyDirectory { try exportBackup(to: safetyDirectory) }

        var config = Configuration()
        config.readonly = true
        let source = try DatabaseQueue(path: sqlite.path, configuration: config)
        try source.backup(to: database.writer)
        // The restored schema may be older than this build: run migrations.
        try TutorDatabase.migrator.migrate(database.writer)

        let mediaSource = folder.appendingPathComponent("media", isDirectory: true)
        try? fm.removeItem(at: database.media.directory)
        if fm.fileExists(atPath: mediaSource.path) {
            try fm.copyItem(at: mediaSource, to: database.media.directory)
        } else {
            try fm.createDirectory(at: database.media.directory, withIntermediateDirectories: true)
        }
    }

    /// Daily rolling backups into `directory`, keeping the newest `keep`.
    /// Returns the new backup folder, or nil when today's exists already.
    @discardableResult
    public func runAutomaticBackupIfDue(in directory: URL, keep: Int = 7, now: Date = .now) throws -> URL? {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let existing = try Self.backups(in: directory)
        if let latest = existing.first, Calendar.current.isDate(latest.manifest.createdAt, inSameDayAs: now) {
            return nil
        }
        let created = try exportBackup(to: directory, now: now)
        for old in try Self.backups(in: directory).dropFirst(keep) {
            try? fm.removeItem(at: old.url)
        }
        return created
    }

    public struct BackupEntry: Sendable {
        public var url: URL
        public var manifest: Manifest
    }

    /// Backups in a directory, newest first.
    public static func backups(in directory: URL) throws -> [BackupEntry] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return [] }
        return try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(folderPrefix) }
            .compactMap { url in manifest(of: url).map { BackupEntry(url: url, manifest: $0) } }
            .sorted { $0.manifest.createdAt > $1.manifest.createdAt }
    }
}
