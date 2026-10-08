//
//  LessonspaceScene.swift
//  LessonspaceImport
//
//  Turns a tab's Fabric.js objects into drawing-model-neutral items in
//  absolute canvas coordinates. The app maps these onto its Excalidraw
//  element models.
//

import Foundation
import CoreGraphics
import ImageIO
#if canImport(PDFKit)
import PDFKit
#endif

public enum LessonspaceShapeKind: Sendable { case rectangle, ellipse, triangle }
public enum LessonspaceTextAlign: String, Sendable { case left, center, right }

public struct LessonspaceImageAsset: Equatable, Sendable {
    /// Stable id derived from the Lessonspace asset UUID (and page, for PDFs).
    public var id: String
    public var mimeType: String
    public var data: Data
}

public enum LessonspaceItem: Sendable {
    case stroke(LessonspaceStroke)
    case shape(kind: LessonspaceShapeKind, frame: CGRect, angle: Double, strokeColor: String, fillColor: String, strokeWidth: Double, dashed: Bool)
    /// Polyline in absolute coordinates; `arrow` draws an arrowhead at the last point.
    case line(points: [CGPoint], arrow: Bool, strokeColor: String, strokeWidth: Double, dashed: Bool, angle: Double)
    case text(text: String, frame: CGRect, fontSize: Double, color: String, align: LessonspaceTextAlign, angle: Double, lineHeight: Double)
    case image(asset: LessonspaceImageAsset, frame: CGRect, angle: Double, flipX: Bool, flipY: Bool)

    public var frame: CGRect {
        switch self {
            case .stroke(let s): return s.boundingBox
            case .shape(_, let frame, _, _, _, _, _): return frame
            case .line(let points, _, _, _, _, _):
                guard let f = points.first else { return .zero }
                var r = CGRect(origin: f, size: .zero)
                for p in points { r = r.union(CGRect(origin: p, size: .zero)) }
                return r
            case .text(_, let frame, _, _, _, _, _): return frame
            case .image(_, let frame, _, _, _): return frame
        }
    }
}

public struct LessonspaceTabScene: Sendable {
    public var name: String
    public var items: [LessonspaceItem]
    /// Fabric object types the converter did not understand.
    public var skippedTypes: [String]

    public var boundingBox: CGRect {
        guard let first = items.first?.frame else { return .zero }
        return items.dropFirst().reduce(first) { $0.union($1.frame) }
    }
}

public enum LessonspaceSceneBuilder {
    /// Gap (canvas px) between stacked PDF pages.
    public static let pdfPageGap: Double = 24
    /// Pixels per PDF point when rasterising pages.
    public static let pdfRenderScale: CGFloat = 2

    public static func scene(for tab: LessonspaceTab, assets: [String: Data]) -> LessonspaceTabScene {
        var items: [LessonspaceItem] = []
        var skipped: [String] = []
        var assetCache: [String: [LessonspaceImageAsset]] = [:]
        for object in tab.objects {
            let converted = convert(object, assets: assets, assetCache: &assetCache)
            if converted.isEmpty, let type = object["type"] as? String, !Self.silentTypes.contains(type) {
                skipped.append(type)
            }
            items += converted
        }
        return LessonspaceTabScene(name: tab.name, items: items, skippedTypes: skipped)
    }

    /// Types whose absence from the output is expected (hidden text, empty strokes…).
    static let silentTypes: Set<String> = ["Buffer", "i-text", "textbox", "text", "image"]

    // MARK: - Objects

    static func convert(_ o: [String: Any], assets: [String: Data], assetCache: inout [String: [LessonspaceImageAsset]]) -> [LessonspaceItem] {
        guard let type = o["type"] as? String else { return [] }
        let sx = num(o["scaleX"]).flatMap { $0 == 0 ? nil : $0 } ?? 1
        let sy = num(o["scaleY"]).flatMap { $0 == 0 ? nil : $0 } ?? 1
        let angle = (num(o["angle"]) ?? 0) * .pi / 180
        let stroke = (o["stroke"] as? String).map { hexColor($0, default: "#1e1e1e") } ?? "transparent"
        let fill = (o["fill"] as? String).map { hexColor($0, default: "transparent") } ?? "transparent"
        let strokeWidth = (num(o["strokeWidth"]) ?? 1) * sx
        let dashed = (o["strokeDashArray"] as? [Any])?.isEmpty == false

        switch type {
            case "Buffer":
                guard let raw = o["data"] as? [Any] else { return [] }
                let bytes = raw.compactMap { num($0) }.map { UInt8(truncatingIfNeeded: Int($0)) }
                guard let s = LessonspaceStrokeDecoder.decode(bytes), s.points.count > 1 else { return [] }
                return [.stroke(s)]

            case "rect", "ellipse", "triangle":
                let w: Double, h: Double
                if type == "ellipse" {
                    w = (num(o["rx"]) ?? (num(o["width"]) ?? 0) / 2) * 2 * sx
                    h = (num(o["ry"]) ?? (num(o["height"]) ?? 0) / 2) * 2 * sy
                } else {
                    w = (num(o["width"]) ?? 0) * sx
                    h = (num(o["height"]) ?? 0) * sy
                }
                guard w > 0, h > 0 else { return [] }
                let origin = topLeft(o, width: w, height: h)
                let kind: LessonspaceShapeKind = type == "rect" ? .rectangle : type == "ellipse" ? .ellipse : .triangle
                return [.shape(kind: kind, frame: CGRect(origin: origin, size: CGSize(width: w, height: h)), angle: angle,
                               strokeColor: stroke, fillColor: fill, strokeWidth: strokeWidth, dashed: dashed)]

            case "line":
                guard let x1 = num(o["x1"]), let y1 = num(o["y1"]), let x2 = num(o["x2"]), let y2 = num(o["y2"]) else { return [] }
                let w = abs(x2 - x1) * sx, h = abs(y2 - y1) * sy
                let origin = topLeft(o, width: w, height: h)
                let minX = min(x1, x2), minY = min(y1, y2)
                let points = [CGPoint(x: origin.x + (x1 - minX) * sx, y: origin.y + (y1 - minY) * sy),
                              CGPoint(x: origin.x + (x2 - minX) * sx, y: origin.y + (y2 - minY) * sy)]
                return [.line(points: points, arrow: false, strokeColor: stroke, strokeWidth: strokeWidth, dashed: dashed, angle: angle)]

            case "arrow-line", "segment":
                var raw: [CGPoint] = []
                if type == "segment" {
                    for p in o["points"] as? [[String: Any]] ?? [] {
                        if let x = num(p["x"]), let y = num(p["y"]) { raw.append(CGPoint(x: x, y: y)) }
                    }
                } else {
                    // First M…L is the shaft; the remaining commands draw the head.
                    for cmd in o["path"] as? [[Any]] ?? [] {
                        guard cmd.count >= 3, let c = cmd[0] as? String, let x = num(cmd[1]), let y = num(cmd[2]) else { continue }
                        if c == "M" || c == "L" { raw.append(CGPoint(x: x, y: y)) }
                        if c == "L", raw.count >= 2 { break }
                    }
                }
                guard raw.count >= 2 else { return [] }
                var box = CGRect(origin: raw[0], size: .zero)
                for p in raw { box = box.union(CGRect(origin: p, size: .zero)) }
                let w = box.width * sx, h = box.height * sy
                let origin = topLeft(o, width: w, height: h)
                let points = raw.map { CGPoint(x: origin.x + ($0.x - box.minX) * sx, y: origin.y + ($0.y - box.minY) * sy) }
                return [.line(points: points, arrow: type == "arrow-line", strokeColor: stroke, strokeWidth: strokeWidth, dashed: dashed, angle: 0)]

            case "i-text", "textbox", "text":
                if o["visible"] as? Bool == false { return [] }
                let text = o["text"] as? String ?? ""
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
                let fontSize = (num(o["fontSize"]) ?? 24) * sy
                let w = (num(o["width"]) ?? 0) * sx, h = (num(o["height"]) ?? 0) * sy
                let origin = topLeft(o, width: w, height: h)
                let lines = max(1, text.components(separatedBy: "\n").count)
                let lineHeight = fontSize > 0 && h > 0 ? (h / (fontSize * Double(lines))).rounded(toPlaces: 3) : 1.25
                let align = LessonspaceTextAlign(rawValue: o["textAlign"] as? String ?? "left") ?? .left
                return [.text(text: text, frame: CGRect(origin: origin, size: CGSize(width: w, height: h)), fontSize: fontSize,
                              color: (o["fill"] as? String).map { hexColor($0, default: "#1e1e1e") } ?? "#1e1e1e",
                              align: align, angle: angle, lineHeight: min(max(lineHeight, 0.9), 2.0))]

            case "image":
                guard let src = o["src"] as? String, let data = assets[src] else { return [] }
                let pages: [LessonspaceImageAsset]
                if let cached = assetCache[src] {
                    pages = cached
                } else {
                    pages = imageAssets(for: src, data: data)
                    assetCache[src] = pages
                }
                guard let first = pages.first else { return [] }
                var w = (num(o["width"]) ?? 0) * sx, h = (num(o["height"]) ?? 0) * sy
                if w <= 0 || h <= 0 {
                    let size = pixelSize(of: first.data) ?? CGSize(width: 400, height: 300)
                    w = size.width * sx; h = size.height * sy
                }
                let origin = topLeft(o, width: w, height: h)
                let flipX = o["flipX"] as? Bool ?? false, flipY = o["flipY"] as? Bool ?? false
                var items: [LessonspaceItem] = []
                var y = origin.y
                for page in pages {
                    let aspect = pixelSize(of: page.data).map { $0.height / max($0.width, 1) } ?? (h / max(w, 1))
                    let pageHeight = page.id == first.id ? h : w * aspect
                    items.append(.image(asset: page, frame: CGRect(x: origin.x, y: y, width: w, height: pageHeight), angle: angle, flipX: flipX, flipY: flipY))
                    y += pageHeight + pdfPageGap
                }
                return items

            default:
                return []
        }
    }

    // MARK: - Assets

    /// One asset per image, or one per page for PDFs.
    static func imageAssets(for src: String, data: Data) -> [LessonspaceImageAsset] {
        let baseID = String(src.replacingOccurrences(of: "-", with: "").prefix(40))
        if data.starts(with: [0x25, 0x50, 0x44, 0x46]) { // %PDF
            let pages = renderPDFPages(data)
            return pages.enumerated().map { index, png in
                LessonspaceImageAsset(id: pages.count == 1 ? baseID : "\(baseID.prefix(36))p\(index + 1)", mimeType: "image/png", data: png)
            }
        }
        return [LessonspaceImageAsset(id: baseID, mimeType: mimeType(of: data), data: data)]
    }

    public static func mimeType(of data: Data) -> String {
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        if data.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        if data.starts(with: [0x47, 0x49, 0x46, 0x38]) { return "image/gif" }
        if data.count > 12, data[data.startIndex + 8..<data.startIndex + 12] == Data([0x57, 0x45, 0x42, 0x50]) { return "image/webp" }
        if let text = String(data: data.prefix(256), encoding: .utf8), text.contains("<svg") { return "image/svg+xml" }
        return "application/octet-stream"
    }

    public static func pixelSize(of data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Double,
              let h = props[kCGImagePropertyPixelHeight] as? Double
        else { return nil }
        return CGSize(width: w, height: h)
    }

    /// Rasterises every page of a PDF to PNG.
    public static func renderPDFPages(_ data: Data) -> [Data] {
#if canImport(PDFKit)
        guard let document = PDFDocument(data: data) else { return [] }
        var pages: [Data] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index), let cgPage = page.pageRef else { continue }
            let box = cgPage.getBoxRect(.mediaBox)
            let rotation = cgPage.rotationAngle
            let rotated = rotation % 180 != 0
            let pointSize = CGSize(width: rotated ? box.height : box.width, height: rotated ? box.width : box.height)
            let pixelWidth = Int((pointSize.width * pdfRenderScale).rounded(.up))
            let pixelHeight = Int((pointSize.height * pdfRenderScale).rounded(.up))
            guard pixelWidth > 0, pixelHeight > 0,
                  let context = CGContext(data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { continue }
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
            context.interpolationQuality = .high
            context.saveGState()
            context.concatenate(cgPage.getDrawingTransform(.mediaBox, rect: CGRect(x: 0, y: 0, width: CGFloat(pixelWidth), height: CGFloat(pixelHeight)), rotate: 0, preserveAspectRatio: true))
            context.drawPDFPage(cgPage)
            context.restoreGState()
            guard let image = context.makeImage(), let png = pngData(image) else { continue }
            pages.append(png)
        }
        return pages
#else
        return []
#endif
    }

    static func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    // MARK: - Helpers

    /// Canvas top-left of a Fabric object given its origin setting.
    static func topLeft(_ o: [String: Any], width: Double, height: Double) -> CGPoint {
        var left = num(o["left"]) ?? 0, top = num(o["top"]) ?? 0
        switch o["originX"] as? String {
            case "center": left -= width / 2
            case "right": left -= width
            default: break
        }
        switch o["originY"] as? String {
            case "center": top -= height / 2
            case "bottom": top -= height
            default: break
        }
        return CGPoint(x: left, y: top)
    }

    static func num(_ value: Any?) -> Double? { LessonspaceRoomExport.number(value) }

    /// `rgba(r,g,b,a)` / `#hex` / a few CSS names → `#rrggbb` or `transparent`.
    public static func hexColor(_ s: String, default fallback: String) -> String {
        let value = s.trimmingCharacters(in: .whitespaces)
        if value.isEmpty { return fallback }
        if value == "transparent" { return "transparent" }
        if value.hasPrefix("#") {
            if value.count == 4 { // #rgb
                let c = Array(value.dropFirst())
                return "#\(c[0])\(c[0])\(c[1])\(c[1])\(c[2])\(c[2])".lowercased()
            }
            return String(value.prefix(7)).lowercased()
        }
        if value.hasPrefix("rgb"), let open = value.firstIndex(of: "("), let close = value.firstIndex(of: ")") {
            let parts = value[value.index(after: open)..<close].split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
            guard parts.count >= 3 else { return fallback }
            if parts.count > 3, parts[3] == 0 { return "transparent" }
            return String(format: "#%02x%02x%02x", Int(parts[0].clamped(0, 255)), Int(parts[1].clamped(0, 255)), Int(parts[2].clamped(0, 255)))
        }
        let named = ["white": "#ffffff", "black": "#000000", "red": "#e03131", "blue": "#1971c2", "green": "#2f9e44",
                     "yellow": "#f08c00", "orange": "#e8590c", "purple": "#6741d9", "grey": "#868e96", "gray": "#868e96"]
        return named[value.lowercased()] ?? fallback
    }
}

extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10.0, Double(places))
        return (self * factor).rounded() / factor
    }

    func clamped(_ lower: Double, _ upper: Double) -> Double { Swift.min(Swift.max(self, lower), upper) }
}
