import Foundation

/// The canvas side of a question: raw Excalidraw elements JSON, the binary
/// files they reference, and a PNG thumbnail. Stored on disk, not in SQL.
public struct QuestionPayload: Sendable {
    public var elementsJSON: Data
    public var filesJSON: Data?
    public var thumbnailPNG: Data?

    public init(elementsJSON: Data, filesJSON: Data? = nil, thumbnailPNG: Data? = nil) {
        self.elementsJSON = elementsJSON; self.filesJSON = filesJSON; self.thumbnailPNG = thumbnailPNG
    }
}
