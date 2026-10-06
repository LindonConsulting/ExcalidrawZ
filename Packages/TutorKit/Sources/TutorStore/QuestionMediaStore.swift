import Foundation
import TutorModels

/// On-disk payloads: `media/<questionID>/elements.json | files.json | thumb.png`.
public struct QuestionMediaStore: Sendable {
    public let directory: URL
    private var fileManager: FileManager { .default }

    public init(directory: URL) {
        self.directory = directory
    }

    public func folder(for id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    public func save(_ payload: QuestionPayload, for id: UUID) throws {
        let folder = folder(for: id)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        try payload.elementsJSON.write(to: folder.appendingPathComponent("elements.json"), options: .atomic)
        if let files = payload.filesJSON {
            try files.write(to: folder.appendingPathComponent("files.json"), options: .atomic)
        }
        if let thumb = payload.thumbnailPNG {
            try thumb.write(to: folder.appendingPathComponent("thumb.png"), options: .atomic)
        }
    }

    public func load(for id: UUID) throws -> QuestionPayload {
        let folder = folder(for: id)
        return QuestionPayload(
            elementsJSON: try Data(contentsOf: folder.appendingPathComponent("elements.json")),
            filesJSON: try? Data(contentsOf: folder.appendingPathComponent("files.json")),
            thumbnailPNG: try? Data(contentsOf: folder.appendingPathComponent("thumb.png"))
        )
    }

    public func thumbnailPNG(for id: UUID) -> Data? {
        try? Data(contentsOf: folder(for: id).appendingPathComponent("thumb.png"))
    }

    public func delete(for id: UUID) {
        try? fileManager.removeItem(at: folder(for: id))
    }
}
