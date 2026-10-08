//
//  LessonspaceStrokeDecoder.swift
//  LessonspaceImport
//
//  Decodes the binary pen-stroke buffers found in Lessonspace Room Exports
//  (`{"type": "Buffer", "data": [bytes]}`), keyed by a little-endian u16
//  version in the first two bytes.
//
//  v3: [ver u16][strokeWidth u8][uuid 16][rgb 3][unknown varint][count varint]
//      [zigzag varint x0 y0, then dx dy …] in tenths of a canvas pixel.
//  v1: [ver u16][uuid 16][w, h, left, top i32 LE][stroke rgba][strokeWidth u8]
//      [fill rgba][6 zero][scaleX f32][scaleY f32][12 zero][count u16]
//      [nargs u8, cmd u8 (M/L/Q), f32 × nargs]* — a serialised Fabric.js path.
//

import Foundation
import CoreGraphics

/// A decoded freehand stroke in absolute canvas coordinates.
public struct LessonspaceStroke: Equatable, Sendable {
    public var points: [CGPoint]
    /// Pen width in canvas pixels.
    public var strokeWidth: Double
    /// `#rrggbb`
    public var colorHex: String

    public init(points: [CGPoint], strokeWidth: Double, colorHex: String) {
        self.points = points
        self.strokeWidth = strokeWidth
        self.colorHex = colorHex
    }

    public var boundingBox: CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in points {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

public enum LessonspaceStrokeDecoder {
    public enum PathSegment: Equatable, Sendable {
        case move(CGPoint)
        case line(CGPoint)
        case quad(control: CGPoint, end: CGPoint)
    }

    /// The raw fields of a v1 (serialised Fabric path) buffer.
    public struct V1Path: Equatable, Sendable {
        public var width: Int32
        public var height: Int32
        public var left: Int32
        public var top: Int32
        public var strokeRGBA: [UInt8]
        public var strokeWidth: UInt8
        public var scaleX: Float
        public var scaleY: Float
        public var segments: [PathSegment]
    }

    public static func version(of bytes: [UInt8]) -> UInt16? {
        guard bytes.count >= 2 else { return nil }
        return UInt16(bytes[0]) | UInt16(bytes[1]) << 8
    }

    /// Decodes either layout; `nil` for unknown versions or damaged data.
    public static func decode(_ bytes: [UInt8]) -> LessonspaceStroke? {
        switch version(of: bytes) {
            case 3: return decodeV3(bytes)
            case 1: return decodeV1(bytes)
            default: return nil
        }
    }

    // MARK: - v3

    public static func decodeV3(_ b: [UInt8]) -> LessonspaceStroke? {
        guard b.count > 22 else { return nil }
        let strokeWidth = Double(b[2])
        let color = hex(b[19], b[20], b[21])
        let values = varints(b, from: 22)
        guard values.count >= 2 else { return nil }
        let count = Int(values[1])
        let coords = Array(values.dropFirst(2))
        guard count >= 1, coords.count >= 2 * count else { return nil }

        var x = Double(zigzag(coords[0])) / 10
        var y = Double(zigzag(coords[1])) / 10
        var points = [CGPoint(x: x, y: y)]
        points.reserveCapacity(count)
        for i in 1..<count {
            x += Double(zigzag(coords[2 * i])) / 10
            y += Double(zigzag(coords[2 * i + 1])) / 10
            points.append(CGPoint(x: x, y: y))
        }
        return LessonspaceStroke(points: points, strokeWidth: strokeWidth, colorHex: color)
    }

    // MARK: - v1

    public static func parseV1(_ b: [UInt8]) -> V1Path? {
        guard b.count >= 71 else { return nil }
        let width = int32LE(b, 18), height = int32LE(b, 22), left = int32LE(b, 26), top = int32LE(b, 30)
        let stroke = Array(b[34..<38])
        let strokeWidth = b[38]
        let scaleX = float32LE(b, 49), scaleY = float32LE(b, 53)
        let count = Int(UInt16(b[69]) | UInt16(b[70]) << 8)
        var i = 71
        var segments: [PathSegment] = []
        segments.reserveCapacity(count)
        for _ in 0..<count {
            guard i + 2 <= b.count else { return nil }
            let nargs = Int(b[i]); let cmd = b[i + 1]; i += 2
            guard i + 4 * nargs <= b.count else { return nil }
            var args: [Float] = []
            for k in 0..<nargs { args.append(float32LE(b, i + 4 * k)) }
            i += 4 * nargs
            switch (cmd, nargs) {
                case (UInt8(ascii: "M"), 2): segments.append(.move(CGPoint(x: Double(args[0]), y: Double(args[1]))))
                case (UInt8(ascii: "L"), 2): segments.append(.line(CGPoint(x: Double(args[0]), y: Double(args[1]))))
                case (UInt8(ascii: "Q"), 4):
                    segments.append(.quad(control: CGPoint(x: Double(args[0]), y: Double(args[1])),
                                          end: CGPoint(x: Double(args[2]), y: Double(args[3]))))
                default: continue // unknown command: skip but keep going
            }
        }
        return V1Path(width: width, height: height, left: left, top: top, strokeRGBA: stroke,
                      strokeWidth: strokeWidth, scaleX: scaleX, scaleY: scaleY, segments: segments)
    }

    public static func decodeV1(_ b: [UInt8]) -> LessonspaceStroke? {
        guard let path = parseV1(b) else { return nil }
        let raw = flatten(path.segments)
        guard let first = raw.first else { return nil }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in raw {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        // Fabric paths are stored relative to their own centre (pathOffset);
        // canvas = left + w·sx/2 + (p − centre)·sx.
        let cx = (minX + maxX) / 2, cy = (minY + maxY) / 2
        let sx = Double(path.scaleX), sy = Double(path.scaleY)
        let originX = Double(path.left) + Double(path.width) * sx / 2
        let originY = Double(path.top) + Double(path.height) * sy / 2
        let points = raw.map { CGPoint(x: originX + ($0.x - cx) * sx, y: originY + ($0.y - cy) * sy) }
        let color = path.strokeRGBA.count >= 3 ? hex(path.strokeRGBA[0], path.strokeRGBA[1], path.strokeRGBA[2]) : "#1e1e1e"
        return LessonspaceStroke(points: points, strokeWidth: Double(path.strokeWidth), colorHex: color)
    }

    /// Samples quadratic segments at t = 0.25, 0.5, 0.75, 1.
    public static func flatten(_ segments: [PathSegment]) -> [CGPoint] {
        var out: [CGPoint] = []
        var current = CGPoint.zero
        for segment in segments {
            switch segment {
                case .move(let p), .line(let p):
                    current = p; out.append(p)
                case .quad(let c, let e):
                    for t in [0.25, 0.5, 0.75, 1.0] {
                        let mt = 1 - t
                        out.append(CGPoint(x: mt * mt * current.x + 2 * mt * t * c.x + t * t * e.x,
                                           y: mt * mt * current.y + 2 * mt * t * c.y + t * t * e.y))
                    }
                    current = e
            }
        }
        return out
    }

    // MARK: - Primitives

    static func varints(_ b: [UInt8], from start: Int) -> [UInt64] {
        var out: [UInt64] = []
        var i = start
        while i < b.count {
            var value: UInt64 = 0, shift: UInt64 = 0
            while i < b.count {
                let c = b[i]; i += 1
                if shift < 64 { value |= UInt64(c & 0x7F) << shift }
                shift += 7
                if c < 128 { break }
            }
            out.append(value)
        }
        return out
    }

    static func zigzag(_ v: UInt64) -> Int64 {
        Int64(bitPattern: (v >> 1)) ^ -Int64(bitPattern: v & 1)
    }

    static func int32LE(_ b: [UInt8], _ i: Int) -> Int32 {
        Int32(bitPattern: UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24)
    }

    static func float32LE(_ b: [UInt8], _ i: Int) -> Float {
        Float(bitPattern: UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24)
    }

    static func hex(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> String {
        String(format: "#%02x%02x%02x", r, g, b)
    }
}
