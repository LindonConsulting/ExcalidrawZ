//
//  LessonRecapBuilder.swift
//  ExcalidrawZ
//
//  Builds the content of a new lesson file: the previous lesson's elements
//  carried over inside a "Recap – <date>" frame, plus an AI summary text
//  block beside it. Works on raw JSON dictionaries so files containing
//  element types unknown to the Swift model still round-trip untouched.
//

import Foundation
import TutorAI

struct LessonRecapBuilder {
    enum BuildError: LocalizedError {
        case invalidTemplate
        case invalidPreviousFile

        var errorDescription: String? {
            switch self {
                case .invalidTemplate: return "The bundled Excalidraw template could not be read."
                case .invalidPreviousFile: return "The previous lesson file could not be parsed."
            }
        }
    }

    static let framePadding: Double = 40
    static let summaryGap: Double = 80
    static let summaryFontSize: Double = 20
    static let summaryLineHeight: Double = 1.25

    /// Parses the elements array out of an `.excalidraw` document.
    static func elements(from data: Data) throws -> [[String: Any]] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BuildError.invalidPreviousFile
        }
        return json["elements"] as? [[String: Any]] ?? []
    }

    /// Live (non-deleted) elements, excluding frames themselves (nested
    /// frames are not supported by Excalidraw; their children are kept).
    static func liveElements(_ elements: [[String: Any]]) -> [[String: Any]] {
        elements.filter { element in
            guard element["isDeleted"] as? Bool != true else { return false }
            let type = element["type"] as? String ?? ""
            return type != "frame" && type != "magicframe"
        }
    }

    /// Text and structure handed to the summarizer.
    static func recapInput(
        from elements: [[String: Any]],
        student: String,
        subject: String?,
        previousLessonDate: Date
    ) -> LessonRecapInput {
        let live = liveElements(elements)
        let texts = live
            .filter { ($0["type"] as? String) == "text" }
            .sorted { lhs, rhs in
                let ly = lhs["y"] as? Double ?? 0, ry = rhs["y"] as? Double ?? 0
                if abs(ly - ry) > 12 { return ly < ry }
                return (lhs["x"] as? Double ?? 0) < (rhs["x"] as? Double ?? 0)
            }
            .compactMap { element -> String? in
                let text = (element["originalText"] as? String) ?? (element["text"] as? String) ?? ""
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
        var counts: [String: Int] = [:]
        for element in live {
            let type = element["type"] as? String ?? "unknown"
            counts[type, default: 0] += 1
        }
        return LessonRecapInput(
            student: student,
            subject: subject,
            previousLessonDate: previousLessonDate,
            texts: texts,
            elementCounts: counts
        )
    }

    /// Produces the new file's content.
    /// - Parameters:
    ///   - previousElements: raw elements of the previous lesson (may be empty).
    ///   - previousLessonDate: used for the frame name.
    ///   - summary: AI recap text, or `nil` when unavailable.
    static func buildFileContent(
        previousElements: [[String: Any]],
        previousLessonDate: Date?,
        summary: String?
    ) throws -> Data {
        guard let templateData = ExcalidrawFile().content,
              var document = try JSONSerialization.jsonObject(with: templateData) as? [String: Any]
        else { throw BuildError.invalidTemplate }

        var newElements: [[String: Any]] = []
        var frameRight: Double = 0

        let carried = liveElements(previousElements)
        if !carried.isEmpty, let previousLessonDate {
            let bounds = boundingBox(of: carried)
            let frameID = randomID()
            let frameWidth = bounds.width + framePadding * 2
            let frameHeight = bounds.height + framePadding * 2
            let dx = framePadding - bounds.minX
            let dy = framePadding - bounds.minY

            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none

            newElements.append(makeElement(type: "frame", id: frameID, x: 0, y: 0, width: frameWidth, height: frameHeight, extra: [
                "name": "Recap – \(formatter.string(from: previousLessonDate))",
                "strokeColor": "#bbb",
                "backgroundColor": "transparent",
                "roughness": 0,
            ]))

            for var element in carried {
                element["x"] = (element["x"] as? Double ?? 0) + dx
                element["y"] = (element["y"] as? Double ?? 0) + dy
                element["frameId"] = frameID
                element["index"] = nil
                newElements.append(element)
            }
            frameRight = frameWidth
        }

        if let summary, !summary.trimmingCharacters(in: .whitespaces).isEmpty {
            let x = frameRight > 0 ? frameRight + summaryGap : 0
            newElements.append(makeTextElement(text: summary, x: x, y: 0))
        }

        document["elements"] = newElements
        return try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
    }

    // MARK: - Element construction

    private static func boundingBox(of elements: [[String: Any]]) -> (minX: Double, minY: Double, width: Double, height: Double) {
        var minX = Double.infinity, minY = Double.infinity, maxX = -Double.infinity, maxY = -Double.infinity
        for element in elements {
            let x = element["x"] as? Double ?? 0
            let y = element["y"] as? Double ?? 0
            let w = element["width"] as? Double ?? 0
            let h = element["height"] as? Double ?? 0
            minX = min(minX, x, x + w); maxX = max(maxX, x, x + w)
            minY = min(minY, y, y + h); maxY = max(maxY, y, y + h)
        }
        if !minX.isFinite { return (0, 0, 0, 0) }
        return (minX, minY, maxX - minX, maxY - minY)
    }

    static func makeTextElement(text: String, x: Double, y: Double) -> [String: Any] {
        let lines = text.components(separatedBy: "\n")
        let longest = lines.map(\.count).max() ?? 0
        let width = max(40, Double(longest) * summaryFontSize * 0.6)
        let height = Double(max(lines.count, 1)) * summaryFontSize * summaryLineHeight
        return makeElement(type: "text", id: randomID(), x: x, y: y, width: width, height: height, extra: [
            "text": text,
            "originalText": text,
            "fontSize": summaryFontSize,
            "fontFamily": 5,
            "textAlign": "left",
            "verticalAlign": "top",
            "containerId": NSNull(),
            "autoResize": true,
            "lineHeight": summaryLineHeight,
        ])
    }

    private static func makeElement(
        type: String,
        id: String,
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        extra: [String: Any]
    ) -> [String: Any] {
        var element: [String: Any] = [
            "type": type,
            "id": id,
            "x": x,
            "y": y,
            "width": width,
            "height": height,
            "angle": 0,
            "strokeColor": "#1e1e1e",
            "backgroundColor": "transparent",
            "fillStyle": "solid",
            "strokeWidth": 1,
            "strokeStyle": "solid",
            "roughness": 1,
            "opacity": 100,
            "groupIds": [],
            "frameId": NSNull(),
            "roundness": NSNull(),
            "seed": Int.random(in: 1...Int(Int32.max)),
            "version": 1,
            "versionNonce": Int.random(in: 1...Int(Int32.max)),
            "isDeleted": false,
            "boundElements": NSNull(),
            "updated": Date().timeIntervalSince1970 * 1000,
            "link": NSNull(),
            "locked": false,
        ]
        element.merge(extra) { _, new in new }
        return element
    }

    private static func randomID() -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        return String((0..<20).map { _ in alphabet.randomElement()! })
    }
}
