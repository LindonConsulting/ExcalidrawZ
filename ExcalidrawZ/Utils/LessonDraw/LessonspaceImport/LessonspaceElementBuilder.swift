//
//  LessonspaceElementBuilder.swift
//  ExcalidrawZ
//
//  Maps the drawing-neutral items produced by LessonspaceImport onto the
//  app's Excalidraw element models: one frame per Lessonspace tab, tabs
//  laid out left to right, images embedded through the files map.
//

import Foundation
import CoreGraphics
import LessonspaceImport

struct LessonspaceImportedContent {
    var elements: [ExcalidrawElement]
    var files: [String: ExcalidrawFile.ResourceFile]
    var frameNames: [String]
    /// Right edge of the last frame; useful for placing content after it.
    var maxX: Double

    var isEmpty: Bool { elements.isEmpty }

    /// Elements as JSON dictionaries, for merging into a stored `.excalidraw` document.
    func elementDictionaries() throws -> [[String: Any]] {
        let data = try JSONEncoder().encode(elements)
        return try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
    }

    func fileDictionaries() throws -> [String: Any] {
        let data = try JSONEncoder().encode(files)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }
}

enum LessonspaceElementBuilder {
    static let framePadding: Double = 40
    static let frameGap: Double = 200
    /// Excalidraw's sans-serif family (Nunito), the closest match to Lessonspace's Inter.
    static let fontFamily: FontFamily = .int(6)

    /// Lays each tab out as a frame, left to right starting at `origin`.
    static func build(scenes: [LessonspaceTabScene], origin: CGPoint = .zero) -> LessonspaceImportedContent {
        var elements: [ExcalidrawElement] = []
        var files: [String: ExcalidrawFile.ResourceFile] = [:]
        var names: [String] = []
        var cursorX = origin.x
        let now = Date().timeIntervalSince1970 * 1000

        for scene in scenes where !scene.items.isEmpty {
            let bounds = scene.boundingBox
            let frameID = randomID()
            let frameWidth = bounds.width + framePadding * 2
            let frameHeight = bounds.height + framePadding * 2
            let dx = cursorX + framePadding - bounds.minX
            let dy = origin.y + framePadding - bounds.minY

            elements.append(.frameLike(ExcalidrawFrameLikeElement(
                type: .frame, id: frameID, x: cursorX, y: origin.y,
                strokeColor: "#bbb", backgroundColor: "transparent", fillStyle: .solid, strokeWidth: 1, strokeStyle: .solid,
                roundness: nil, roughness: 0, opacity: 100, width: frameWidth, height: frameHeight, angle: 0,
                seed: randomSeed(), version: 1, versionNonce: randomSeed(), index: nil, isDeleted: false, groupIds: [],
                frameId: nil, boundElements: nil, updated: now, link: nil, locked: false, customData: nil,
                name: scene.name
            )))

            for item in scene.items {
                if let element = element(for: item, offset: CGPoint(x: dx, y: dy), frameID: frameID, files: &files, updated: now) {
                    elements.append(element)
                }
            }
            names.append(scene.name)
            cursorX += frameWidth + frameGap
        }
        return LessonspaceImportedContent(elements: elements, files: files, frameNames: names,
                                          maxX: names.isEmpty ? origin.x : cursorX - frameGap)
    }

    // MARK: - Items

    private static func element(for item: LessonspaceItem, offset: CGPoint, frameID: String,
                                files: inout [String: ExcalidrawFile.ResourceFile], updated: Double) -> ExcalidrawElement? {
        switch item {
            case .stroke(let stroke):
                guard let first = stroke.points.first else { return nil }
                let box = stroke.boundingBox
                let relative = stroke.points.map { CGPoint(x: $0.x - first.x, y: $0.y - first.y) }
                return .freeDraw(ExcalidrawFreeDrawElement(
                    id: randomID(), x: first.x + offset.x, y: first.y + offset.y,
                    strokeColor: stroke.colorHex, backgroundColor: "transparent", fillStyle: .solid,
                    strokeWidth: excalidrawStrokeWidth(stroke.strokeWidth), strokeStyle: .solid, roundness: nil,
                    roughness: 0, opacity: 100, width: box.width, height: box.height, angle: 0,
                    seed: randomSeed(), version: 1, versionNonce: randomSeed(), index: nil, isDeleted: false,
                    groupIds: [], frameId: frameID, boundElements: nil, updated: updated, link: nil, locked: false,
                    customData: nil, type: .freedraw,
                    points: relative, pressures: [], simulatePressure: true, lastCommittedPoint: relative.last
                ))

            case .shape(let kind, let frame, let angle, let strokeColor, let fillColor, let strokeWidth, let dashed):
                let x = frame.minX + offset.x, y = frame.minY + offset.y
                switch kind {
                    case .rectangle, .ellipse:
                        return .generic(ExcalidrawGenericElement(
                            type: kind == .rectangle ? .rectangle : .ellipse, id: randomID(), x: x, y: y,
                            strokeColor: strokeColor, backgroundColor: fillColor, fillStyle: .solid,
                            strokeWidth: excalidrawStrokeWidth(strokeWidth), strokeStyle: dashed ? .dashed : .solid,
                            roundness: nil, roughness: 0, opacity: 100, width: frame.width, height: frame.height, angle: angle,
                            seed: randomSeed(), version: 1, versionNonce: randomSeed(), index: nil, isDeleted: false, groupIds: [],
                            frameId: frameID, boundElements: nil, updated: updated, link: nil, locked: false, customData: nil,
                            strokeSharpness: nil
                        ))
                    case .triangle:
                        let w = frame.width, h = frame.height
                        let points = [CGPoint(x: w / 2, y: 0), CGPoint(x: w, y: h), CGPoint(x: 0, y: h), CGPoint(x: w / 2, y: 0)]
                        return .linear(linear(id: randomID(), x: x, y: y, width: w, height: h, angle: angle, points: points,
                                              strokeColor: strokeColor, backgroundColor: fillColor,
                                              strokeWidth: excalidrawStrokeWidth(strokeWidth), dashed: dashed, frameID: frameID, updated: updated))
                }

            case .line(let points, let arrow, let strokeColor, let strokeWidth, let dashed, let angle):
                guard let first = points.first, points.count >= 2 else { return nil }
                var box = CGRect(origin: first, size: .zero)
                for p in points { box = box.union(CGRect(origin: p, size: .zero)) }
                let relative = points.map { CGPoint(x: $0.x - first.x, y: $0.y - first.y) }
                let x = first.x + offset.x, y = first.y + offset.y
                let width = excalidrawStrokeWidth(strokeWidth)
                if arrow {
                    return .arrow(ExcalidrawArrowElement(
                        id: randomID(), x: x, y: y, strokeColor: strokeColor, backgroundColor: "transparent", fillStyle: .solid,
                        strokeWidth: width, strokeStyle: dashed ? .dashed : .solid, roundness: nil, roughness: 0, opacity: 100,
                        width: box.width, height: box.height, angle: angle, seed: randomSeed(), version: 1, versionNonce: randomSeed(),
                        index: nil, isDeleted: false, groupIds: [], frameId: frameID, boundElements: nil, updated: updated, link: nil,
                        locked: false, customData: nil, type: .arrow, points: relative, lastCommittedPoint: relative.last,
                        startBinding: nil, endBinding: nil, startArrowhead: nil, endArrowhead: .arrow, elbowed: false,
                        fixedSegments: nil, startIsSpecial: nil, endIsSpecial: nil
                    ))
                }
                return .linear(linear(id: randomID(), x: x, y: y, width: box.width, height: box.height, angle: angle, points: relative,
                                      strokeColor: strokeColor, backgroundColor: "transparent", strokeWidth: width, dashed: dashed,
                                      frameID: frameID, updated: updated))

            case .text(let text, let frame, let fontSize, let color, let align, let angle, let lineHeight):
                let textAlign: TextAlign = align == .center ? .center : align == .right ? .right : .left
                let lines = text.components(separatedBy: "\n")
                let width = frame.width > 0 ? frame.width : Double(lines.map(\.count).max() ?? 1) * fontSize * 0.6
                let height = frame.height > 0 ? frame.height : Double(lines.count) * fontSize * lineHeight
                return .text(ExcalidrawTextElement(
                    type: .text, id: randomID(), x: frame.minX + offset.x, y: frame.minY + offset.y,
                    strokeColor: color, backgroundColor: "transparent", fillStyle: .solid, strokeWidth: 1, strokeStyle: .solid,
                    roundness: nil, roughness: 0, opacity: 100, width: width, height: height, angle: angle,
                    seed: randomSeed(), version: 1, versionNonce: randomSeed(), index: nil, isDeleted: false, groupIds: [],
                    frameId: frameID, boundElements: nil, updated: updated, link: nil, locked: false, customData: nil,
                    fontSize: fontSize, fontFamily: fontFamily, text: text, textAlign: textAlign, verticalAlign: .top,
                    containerId: nil, originalText: text, autoResize: true, lineHeight: lineHeight
                ))

            case .image(let asset, let frame, let angle, let flipX, let flipY):
                if files[asset.id] == nil {
                    files[asset.id] = ExcalidrawFile.ResourceFile(
                        mimeType: asset.mimeType, id: asset.id, createdAt: Date(),
                        dataURL: "data:\(asset.mimeType);base64,\(asset.data.base64EncodedString())"
                    )
                }
                return .image(ExcalidrawImageElement(
                    type: .image, id: randomID(), x: frame.minX + offset.x, y: frame.minY + offset.y,
                    strokeColor: "transparent", backgroundColor: "transparent", fillStyle: .solid, strokeWidth: 1, strokeStyle: .solid,
                    roundness: nil, roughness: 0, opacity: 100, width: frame.width, height: frame.height, angle: angle,
                    seed: randomSeed(), version: 1, versionNonce: randomSeed(), index: nil, isDeleted: false, groupIds: [],
                    frameId: frameID, boundElements: nil, updated: updated, link: nil, locked: false, customData: nil,
                    fileId: asset.id, status: .saved, scale: [flipX ? -1 : 1, flipY ? -1 : 1], crop: nil
                ))
        }
    }

    private static func linear(id: String, x: Double, y: Double, width: Double, height: Double, angle: Double, points: [CGPoint],
                               strokeColor: String, backgroundColor: String, strokeWidth: Double, dashed: Bool,
                               frameID: String, updated: Double) -> ExcalidrawLinearElement {
        ExcalidrawLinearElement(
            id: id, x: x, y: y, strokeColor: strokeColor, backgroundColor: backgroundColor, fillStyle: .solid,
            strokeWidth: strokeWidth, strokeStyle: dashed ? .dashed : .solid, roundness: nil, roughness: 0, opacity: 100,
            width: width, height: height, angle: angle, seed: randomSeed(), version: 1, versionNonce: randomSeed(),
            index: nil, isDeleted: false, groupIds: [], frameId: frameID, boundElements: nil, updated: updated, link: nil,
            locked: false, customData: nil, type: .line, points: points, lastCommittedPoint: points.last,
            startBinding: nil, endBinding: nil, startArrowhead: nil, endArrowhead: nil
        )
    }

    // MARK: - Helpers

    /// Lessonspace pens are 2–6 px; Excalidraw uses 1 (thin), 2 (bold), 4 (extra bold).
    static func excalidrawStrokeWidth(_ pixels: Double) -> Double {
        min(4, max(1, (pixels / 3).rounded()))
    }

    static func randomSeed() -> Int { Int.random(in: 1...Int(Int32.max)) }

    static func randomID() -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        return String((0..<20).map { _ in alphabet.randomElement()! })
    }
}

// MARK: - Memberwise initialisers for models that define a custom decoder

extension ExcalidrawFreeDrawElement {
    init(id: String, x: Double, y: Double, strokeColor: String, backgroundColor: String, fillStyle: ExcalidrawFillStyle,
         strokeWidth: Double, strokeStyle: ExcalidrawStrokeStyle, roundness: ExcalidrawRoundness?, roughness: Double, opacity: Double,
         width: Double, height: Double, angle: Double, seed: Int, version: Int, versionNonce: Int, index: String?, isDeleted: Bool,
         groupIds: [String], frameId: String?, boundElements: [ExcalidrawBoundElement]?, updated: Double?, link: String?, locked: Bool?,
         customData: [String: AnyCodable]?, type: ExcalidrawElementType, points: [Point], pressures: [Double], simulatePressure: Bool,
         lastCommittedPoint: Point?) {
        self.id = id; self.x = x; self.y = y; self.strokeColor = strokeColor; self.backgroundColor = backgroundColor
        self.fillStyle = fillStyle; self.strokeWidth = strokeWidth; self.strokeStyle = strokeStyle; self.roundness = roundness
        self.roughness = roughness; self.opacity = opacity; self.width = width; self.height = height; self.angle = angle
        self.seed = seed; self.version = version; self.versionNonce = versionNonce; self.index = index; self.isDeleted = isDeleted
        self.groupIds = groupIds; self.frameId = frameId; self.boundElements = boundElements; self.updated = updated
        self.link = link; self.locked = locked; self.customData = customData; self.type = type
        self.points = points; self.pressures = pressures; self.simulatePressure = simulatePressure; self.lastCommittedPoint = lastCommittedPoint
    }
}
