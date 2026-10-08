//
//  ZipArchive.swift
//  LessonspaceImport
//
//  Minimal read-only ZIP reader (stored + deflate entries) built on the
//  Compression framework, so Room Export archives can be opened without a
//  third-party dependency or spawning `unzip`.
//

import Foundation
import Compression

public struct ZipArchive {
    public enum ZipError: LocalizedError {
        case notAZipFile
        case unsupportedCompression(UInt16, entry: String)
        case corruptEntry(String)

        public var errorDescription: String? {
            switch self {
                case .notAZipFile: return "The file is not a ZIP archive."
                case .unsupportedCompression(let method, let entry): return "Unsupported compression method \(method) for \(entry)."
                case .corruptEntry(let entry): return "The archive entry \(entry) is damaged."
            }
        }
    }

    public struct Entry {
        public var path: String
        public var compressedSize: Int
        public var uncompressedSize: Int
        var method: UInt16
        var localHeaderOffset: Int
        public var isDirectory: Bool { path.hasSuffix("/") }
    }

    private let data: Data
    public private(set) var entries: [Entry] = []

    public init(url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    public init(data: Data) throws {
        self.data = data
        self.entries = try Self.readCentralDirectory(data)
    }

    public func entry(at path: String) -> Entry? {
        entries.first { $0.path == path }
    }

    /// Decompressed contents of an entry.
    public func contents(of entry: Entry) throws -> Data {
        let base = entry.localHeaderOffset
        guard base + 30 <= data.count, data.readUInt32LE(at: base) == 0x0403_4b50 else {
            throw ZipError.corruptEntry(entry.path)
        }
        let nameLength = Int(data.readUInt16LE(at: base + 26))
        let extraLength = Int(data.readUInt16LE(at: base + 28))
        let start = base + 30 + nameLength + extraLength
        let end = start + entry.compressedSize
        guard end <= data.count else { throw ZipError.corruptEntry(entry.path) }
        let compressed = data.subdata(in: start..<end)

        switch entry.method {
            case 0:
                return compressed
            case 8:
                return try Self.inflate(compressed, expectedSize: entry.uncompressedSize, entry: entry.path)
            default:
                throw ZipError.unsupportedCompression(entry.method, entry: entry.path)
        }
    }

    // MARK: - Parsing

    private static func readCentralDirectory(_ data: Data) throws -> [Entry] {
        // End of central directory record: signature 0x06054b50, at least 22 bytes, followed by an optional comment.
        guard data.count >= 22 else { throw ZipError.notAZipFile }
        var eocd: Int?
        let minimum = max(0, data.count - 22 - 0xFFFF)
        var i = data.count - 22
        while i >= minimum {
            if data.readUInt32LE(at: i) == 0x0605_4b50 { eocd = i; break }
            i -= 1
        }
        guard let eocd else { throw ZipError.notAZipFile }
        let entryCount = Int(data.readUInt16LE(at: eocd + 10))
        var offset = Int(data.readUInt32LE(at: eocd + 16))

        var entries: [Entry] = []
        entries.reserveCapacity(entryCount)
        for _ in 0..<entryCount {
            guard offset + 46 <= data.count, data.readUInt32LE(at: offset) == 0x0201_4b50 else { break }
            let method = data.readUInt16LE(at: offset + 10)
            let compressedSize = Int(data.readUInt32LE(at: offset + 20))
            let uncompressedSize = Int(data.readUInt32LE(at: offset + 24))
            let nameLength = Int(data.readUInt16LE(at: offset + 28))
            let extraLength = Int(data.readUInt16LE(at: offset + 30))
            let commentLength = Int(data.readUInt16LE(at: offset + 32))
            let localHeaderOffset = Int(data.readUInt32LE(at: offset + 42))
            let nameStart = offset + 46
            guard nameStart + nameLength <= data.count else { break }
            let name = String(decoding: data.subdata(in: nameStart..<(nameStart + nameLength)), as: UTF8.self)
            entries.append(Entry(path: name, compressedSize: compressedSize, uncompressedSize: uncompressedSize,
                                 method: method, localHeaderOffset: localHeaderOffset))
            offset = nameStart + nameLength + extraLength + commentLength
        }
        return entries
    }

    private static func inflate(_ compressed: Data, expectedSize: Int, entry: String) throws -> Data {
        guard expectedSize > 0 else { return Data() }
        var output = Data(count: expectedSize)
        let written = output.withUnsafeMutableBytes { dst -> Int in
            compressed.withUnsafeBytes { src -> Int in
                guard let dstBase = dst.baseAddress, let srcBase = src.baseAddress else { return 0 }
                return compression_decode_buffer(
                    dstBase.assumingMemoryBound(to: UInt8.self), expectedSize,
                    srcBase.assumingMemoryBound(to: UInt8.self), compressed.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written == expectedSize else { throw ZipError.corruptEntry(entry) }
        return output
    }
}

extension Data {
    func readUInt16LE(at offset: Int) -> UInt16 {
        guard offset + 2 <= count else { return 0 }
        return UInt16(self[startIndex + offset]) | UInt16(self[startIndex + offset + 1]) << 8
    }

    func readUInt32LE(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        return UInt32(self[startIndex + offset])
            | UInt32(self[startIndex + offset + 1]) << 8
            | UInt32(self[startIndex + offset + 2]) << 16
            | UInt32(self[startIndex + offset + 3]) << 24
    }
}
