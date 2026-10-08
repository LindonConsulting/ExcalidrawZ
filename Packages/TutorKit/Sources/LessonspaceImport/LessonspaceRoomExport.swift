//
//  LessonspaceRoomExport.swift
//  LessonspaceImport
//
//  Reads a Lessonspace "Room Export" ZIP: `.room_exported`, one JSON file per
//  tab under `room.sh-<exportId>/<tabUUID>` (Fabric.js 5.1 scenes) and the
//  uploaded assets under `room.sh-<exportId>/files/<uuid>`.
//

import Foundation

public struct LessonspaceTab: @unchecked Sendable {
    public var id: String
    public var name: String
    public var position: Int
    public var width: Double
    public var height: Double
    /// Raw Fabric.js objects (`type`, `left`, `top`, …) or `{"type": "Buffer", "data": [...]}` strokes.
    public var objects: [[String: Any]]

    public var isTemplate: Bool { LessonspaceRoomExport.templateTabNames.contains(name) }
}

public struct LessonspaceRoomExport: @unchecked Sendable {
    public enum ExportError: LocalizedError {
        case noRoomFolder
        case noWhiteboards

        public var errorDescription: String? {
            switch self {
                case .noRoomFolder: return "This ZIP does not look like a Lessonspace Room Export (no room.sh-… folder)."
                case .noWhiteboards: return "The Room Export contains no whiteboard tabs."
            }
        }
    }

    /// Tabs MyTutor adds to every room; skipped unless the user asks for them.
    public static let templateTabNames: Set<String> = ["Blank Lesson Plan", "Lessonspace Games"]

    /// Whiteboard tabs sorted by their position in the room.
    public var tabs: [LessonspaceTab]
    /// Uploaded assets keyed by the UUID used in image `src` fields.
    public var assets: [String: Data]

    public init(tabs: [LessonspaceTab], assets: [String: Data]) {
        self.tabs = tabs
        self.assets = assets
    }

    public func tabs(includingTemplates: Bool) -> [LessonspaceTab] {
        includingTemplates ? tabs : tabs.filter { !$0.isTemplate }
    }

    public init(zipURL: URL) throws {
        try self.init(archive: try ZipArchive(url: zipURL))
    }

    public init(zipData: Data) throws {
        try self.init(archive: try ZipArchive(data: zipData))
    }

    init(archive: ZipArchive) throws {
        guard let roomPrefix = archive.entries
            .map(\.path)
            .compactMap({ path -> String? in
                guard let first = path.split(separator: "/").first, first.hasPrefix("room.sh-") else { return nil }
                return String(first) + "/"
            })
            .first
        else { throw ExportError.noRoomFolder }

        var tabs: [LessonspaceTab] = []
        var assets: [String: Data] = [:]
        for entry in archive.entries where entry.path.hasPrefix(roomPrefix) && !entry.isDirectory {
            let relative = String(entry.path.dropFirst(roomPrefix.count))
            if relative.hasPrefix("files/") {
                let name = String(relative.dropFirst("files/".count))
                guard !name.isEmpty, !name.contains("/") else { continue }
                assets[name] = try archive.contents(of: entry)
                continue
            }
            guard !relative.contains("/") else { continue }
            let data = try archive.contents(of: entry)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let meta = json["meta"] as? [String: Any],
                  meta["module"] as? String == "Whiteboard"
            else { continue }
            let inner = meta["meta"] as? [String: Any] ?? [:]
            tabs.append(LessonspaceTab(
                id: meta["id"] as? String ?? relative,
                name: (inner["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Whiteboard",
                position: Self.number(inner["position"]).map(Int.init) ?? 0,
                width: Self.number(inner["width"]) ?? 1280,
                height: Self.number(inner["height"]) ?? 720,
                objects: json["data"] as? [[String: Any]] ?? []
            ))
        }
        guard !tabs.isEmpty else { throw ExportError.noWhiteboards }
        tabs.sort { ($0.position, $0.name) < ($1.position, $1.name) }
        self.tabs = tabs
        self.assets = assets
    }

    /// Finds Room Export ZIPs in a folder, newest first (by name date, then modification date).
    public static func roomExportZIPs(in folder: URL) -> [URL] {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) else { return [] }
        return urls
            .filter { $0.pathExtension.lowercased() == "zip" && $0.lastPathComponent.lowercased().hasPrefix("room export") }
            .sorted { lhs, rhs in
                let l = (try? lhs.resourceValues(forKeys: keys).contentModificationDate) ?? .distantPast
                let r = (try? rhs.resourceValues(forKeys: keys).contentModificationDate) ?? .distantPast
                if l != r { return l > r }
                return lhs.lastPathComponent > rhs.lastPathComponent
            }
    }

    static func number(_ value: Any?) -> Double? {
        switch value {
            case let d as Double: return d
            case let i as Int: return Double(i)
            case let n as NSNumber: return n.doubleValue
            case let s as String: return Double(s)
            default: return nil
        }
    }
}
