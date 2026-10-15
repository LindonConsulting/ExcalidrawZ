//
//  MathsToolsElementFactory.swift
//  ExcalidrawZ
//
//  Builds Excalidraw element skeletons for the maths teaching tools
//  (triangles, angles, protractor). Everything is expressed in local
//  coordinates; the web side positions the batch at the viewport centre.
//

import Foundation

struct MathsToolsStyle {
    /// 0 = precise ("architect"), 1 = hand-drawn ("artist").
    var roughness: Double = 0
    var strokeColor: String = "#1e1e1e"
    var strokeWidth: Double = 2
    var fontSize: Double = 20
    var labelVertices: Bool = true

    /// Nunito for precise drawings, Excalifont when hand-drawn.
    var fontFamily: Int { roughness == 0 ? 6 : 5 }
}

struct MathsToolsBuild {
    var skeletons: [ExcalidrawCore.JSONValue]
    var groupID: String
    var title: String
}

enum MathsToolsElementFactory {
    typealias JSONValue = ExcalidrawCore.JSONValue
    typealias Point = (x: Double, y: Double)

    // MARK: Triangles

    /// Right angle at the bottom-left vertex; legs `size` × `0.8·size`.
    static func rightAngledTriangle(size: Double, style: MathsToolsStyle) -> MathsToolsBuild {
        let gid = makeGroupID()
        let a: Point = (0, 0.8 * size)          // right angle
        let b: Point = (0, 0)
        let c: Point = (size, 0.8 * size)
        var out: [JSONValue] = [
            line([b, a, c], closed: true, style: style, gid: gid)
        ]
        out.append(rightAngleMarker(at: a, arm1: b, arm2: c, size: 0.09 * size, style: style, gid: gid))
        if style.labelVertices {
            out += vertexLabels(for: [a, b, c], style: style, gid: gid)
        }
        return MathsToolsBuild(skeletons: out, groupID: gid, title: "right-angled triangle")
    }

    /// All sides `size` long, apex at the top, with equal-side tick marks.
    static func equilateralTriangle(size: Double, style: MathsToolsStyle) -> MathsToolsBuild {
        let gid = makeGroupID()
        let h = size * 3.0.squareRoot() / 2
        let a: Point = (size / 2, 0)
        let b: Point = (0, h)
        let c: Point = (size, h)
        var out: [JSONValue] = [
            line([a, b, c], closed: true, style: style, gid: gid)
        ]
        for (p, q) in [(a, b), (b, c), (c, a)] {
            out.append(contentsOf: tickMarks(on: p, q, count: 1, length: 0.07 * size, style: style, gid: gid))
        }
        if style.labelVertices {
            out += vertexLabels(for: [b, a, c], style: style, gid: gid)
        }
        return MathsToolsBuild(skeletons: out, groupID: gid, title: "equilateral triangle")
    }

    /// Two equal legs of length `size` meeting at `apexAngle` degrees, base at the bottom.
    static func isoscelesTriangle(size: Double, apexAngle: Double, style: MathsToolsStyle) -> MathsToolsBuild {
        let gid = makeGroupID()
        let half = apexAngle.clamped(to: 10...170) / 2 * .pi / 180
        let halfBase = size * sin(half)
        let height = size * cos(half)
        let apex: Point = (halfBase, 0)
        let b: Point = (0, height)
        let c: Point = (2 * halfBase, height)
        var out: [JSONValue] = [
            line([apex, b, c], closed: true, style: style, gid: gid)
        ]
        out.append(contentsOf: tickMarks(on: apex, b, count: 1, length: 0.07 * size, style: style, gid: gid))
        out.append(contentsOf: tickMarks(on: apex, c, count: 1, length: 0.07 * size, style: style, gid: gid))
        if style.labelVertices {
            out += vertexLabels(for: [b, apex, c], style: style, gid: gid)
        }
        return MathsToolsBuild(skeletons: out, groupID: gid, title: "isosceles triangle")
    }

    // MARK: Angle

    /// Two arms of length `size` from a shared vertex, measured anticlockwise
    /// from the horizontal, with an arc (or right-angle square) and a label.
    static func angle(degrees: Double, size: Double, showLabel: Bool, style: MathsToolsStyle) -> MathsToolsBuild {
        let gid = makeGroupID()
        let theta = degrees.clamped(to: 1...359)
        let rad = theta * .pi / 180
        let vertex: Point = (0, 0)
        let arm1: Point = (size, 0)
        let arm2: Point = (size * cos(rad), -size * sin(rad))
        var out: [JSONValue] = [
            line([arm1, vertex, arm2], closed: false, style: style, gid: gid)
        ]
        let r = max(24, size * 0.3)
        if abs(theta - 90) < 0.01 {
            out.append(rightAngleMarker(at: vertex, arm1: arm1, arm2: arm2, size: r * 0.6, style: style, gid: gid))
        } else {
            var arc: [Point] = []
            var a = 0.0
            while a < theta {
                arc.append((r * cos(a * .pi / 180), -r * sin(a * .pi / 180)))
                a += 3
            }
            arc.append((r * cos(rad), -r * sin(rad)))
            out.append(line(arc, closed: false, style: style, gid: gid, strokeWidth: max(1, style.strokeWidth - 0.5)))
        }
        if showLabel {
            let labelRadius = r * 1.55 + style.fontSize * 0.4
            let bisector = rad / 2
            let center: Point = (labelRadius * cos(bisector), -labelRadius * sin(bisector))
            out.append(text(formatDegrees(theta), center: center, style: style, gid: gid))
        }
        return MathsToolsBuild(skeletons: out, groupID: gid, title: "\(formatDegrees(theta)) angle")
    }

    // MARK: Protractor

    /// A 180° protractor of the given radius with two scales (outer 0→180
    /// left to right, inner 0→180 right to left).
    static func protractor(radius: Double, fineTicks: Bool, style: MathsToolsStyle) -> MathsToolsBuild {
        let gid = makeGroupID()
        let r = max(60, radius)
        var out: [JSONValue] = []

        // Body: outer semicircle closed along the baseline.
        var body: [Point] = []
        for a in stride(from: 180.0, through: 0.0, by: -2) {
            body.append(onCircle(r, a))
        }
        out.append(line(body, closed: true, style: style, gid: gid, background: "#dbeafe", opacity: 85))

        // Invisible counterweight below the baseline so the group's bounding box
        // is centred on the origin: Excalidraw rotates a selection about its
        // bounding-box centre, so this makes the protractor turn about the
        // bottom-centre mark instead of the middle of the semicircle.
        out.append(line([(-r, r), (r, r)], closed: false, style: style, gid: gid, strokeWidth: 1, opacity: 0))

        // Inner scale arc.
        var inner: [Point] = []
        for a in stride(from: 180.0, through: 0.0, by: -2) {
            inner.append(onCircle(r * 0.62, a))
        }
        out.append(line(inner, closed: false, style: style, gid: gid, strokeWidth: 1))

        // Centre mark.
        out.append(line([(-r * 0.08, 0), (r * 0.08, 0)], closed: false, style: style, gid: gid, strokeWidth: 1))
        out.append(line([(0, 0), (0, -r * 0.12)], closed: false, style: style, gid: gid, strokeWidth: 1))

        // Ticks.
        let step = fineTicks ? 1 : 5
        for d in stride(from: 0, through: 180, by: step) {
            let a = Double(d)
            let length: Double
            if d % 10 == 0 {
                length = r * 0.12
            } else if d % 5 == 0 {
                length = r * 0.08
            } else {
                length = r * 0.045
            }
            out.append(
                line([onCircle(r, a), onCircle(r - length, a)],
                     closed: false, style: style, gid: gid,
                     strokeWidth: d % 10 == 0 ? 1.5 : 1)
            )
        }

        // Labels every 10°.
        let outerFont = max(9, (r * 0.075).rounded())
        let innerFont = max(8, (r * 0.06).rounded())
        for d in stride(from: 0, through: 180, by: 10) {
            let a = Double(d)
            var outerStyle = style
            outerStyle.fontSize = outerFont
            out.append(text("\(180 - d)", center: onCircle(r * 0.80, a), style: outerStyle, gid: gid))
            var innerStyle = style
            innerStyle.fontSize = innerFont
            out.append(text("\(d)", center: onCircle(r * 0.70, a), style: innerStyle, gid: gid))
        }

        return MathsToolsBuild(skeletons: out, groupID: gid, title: "protractor")
    }

    // MARK: Compass

    /// A compass arc of `radius`, swept anticlockwise from `startDegrees`
    /// through `sweepDegrees`, with a small centre mark where the point sat.
    static func compassArc(
        radius: Double, startDegrees: Double, sweepDegrees: Double,
        showCentre: Bool, style: MathsToolsStyle
    ) -> MathsToolsBuild {
        let gid = makeGroupID()
        let r = max(10, radius)
        let sweep = sweepDegrees.clamped(to: 1...360)
        var out: [JSONValue] = []
        var arc: [Point] = []
        var a = 0.0
        while a < sweep {
            arc.append(onCircle(r, startDegrees + a))
            a += 2
        }
        arc.append(onCircle(r, startDegrees + sweep))
        out.append(line(arc, closed: false, style: style, gid: gid))
        if showCentre {
            out += centreMark(size: max(6, r * 0.05), style: style, gid: gid)
        }
        return MathsToolsBuild(skeletons: out, groupID: gid, title: "compass arc")
    }

    /// A full circle of `radius` with a centre mark.
    static func compassCircle(radius: Double, showCentre: Bool, style: MathsToolsStyle) -> MathsToolsBuild {
        let gid = makeGroupID()
        let r = max(10, radius)
        var out: [JSONValue] = [
            .object([
                "type": .string("ellipse"),
                "x": .number(-r),
                "y": .number(-r),
                "width": .number(2 * r),
                "height": .number(2 * r),
                "strokeColor": .string(style.strokeColor),
                "backgroundColor": .string("transparent"),
                "fillStyle": .string("solid"),
                "strokeWidth": .number(style.strokeWidth),
                "strokeStyle": .string("solid"),
                "roughness": .number(style.roughness),
                "groupIds": .array([.string(gid)])
            ])
        ]
        if showCentre {
            out += centreMark(size: max(6, r * 0.05), style: style, gid: gid)
        }
        return MathsToolsBuild(skeletons: out, groupID: gid, title: "circle")
    }

    private static func centreMark(size: Double, style: MathsToolsStyle, gid: String) -> [JSONValue] {
        let w = max(1, style.strokeWidth - 0.5)
        return [
            line([(-size, 0), (size, 0)], closed: false, style: style, gid: gid, strokeWidth: w),
            line([(0, -size), (0, size)], closed: false, style: style, gid: gid, strokeWidth: w)
        ]
    }

    // MARK: - Primitives

    private static func onCircle(_ radius: Double, _ degrees: Double) -> Point {
        let rad = degrees * .pi / 180
        return (radius * cos(rad), -radius * sin(rad))
    }

    private static func makeGroupID() -> String {
        "maths-" + String(UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "").prefix(16))
    }

    private static func formatDegrees(_ value: Double) -> String {
        let rounded = value.rounded()
        if abs(value - rounded) < 0.01 {
            return "\(Int(rounded))°"
        }
        return String(format: "%.1f°", value)
    }

    private static func rightAngleMarker(
        at vertex: Point, arm1: Point, arm2: Point, size: Double,
        style: MathsToolsStyle, gid: String
    ) -> JSONValue {
        let u = unit(from: vertex, to: arm1)
        let v = unit(from: vertex, to: arm2)
        let p1: Point = (vertex.x + u.x * size, vertex.y + u.y * size)
        let p2: Point = (vertex.x + (u.x + v.x) * size, vertex.y + (u.y + v.y) * size)
        let p3: Point = (vertex.x + v.x * size, vertex.y + v.y * size)
        return line([p1, p2, p3], closed: false, style: style, gid: gid, strokeWidth: max(1, style.strokeWidth - 0.5))
    }

    /// Short perpendicular strokes across the middle of segment p–q.
    private static func tickMarks(
        on p: Point, _ q: Point, count: Int, length: Double,
        style: MathsToolsStyle, gid: String
    ) -> [JSONValue] {
        let dir = unit(from: p, to: q)
        let normal: Point = (-dir.y, dir.x)
        let mid: Point = ((p.x + q.x) / 2, (p.y + q.y) / 2)
        let spacing = length * 0.6
        return (0..<count).map { index in
            let offset = (Double(index) - Double(count - 1) / 2) * spacing
            let c: Point = (mid.x + dir.x * offset, mid.y + dir.y * offset)
            return line(
                [(c.x - normal.x * length / 2, c.y - normal.y * length / 2),
                 (c.x + normal.x * length / 2, c.y + normal.y * length / 2)],
                closed: false, style: style, gid: gid, strokeWidth: max(1, style.strokeWidth - 0.5)
            )
        }
    }

    /// Letters A, B, C… placed just outside each vertex, away from the centroid.
    private static func vertexLabels(for vertices: [Point], style: MathsToolsStyle, gid: String) -> [JSONValue] {
        let cx = vertices.map(\.x).reduce(0, +) / Double(vertices.count)
        let cy = vertices.map(\.y).reduce(0, +) / Double(vertices.count)
        let letters = ["A", "B", "C", "D", "E", "F"]
        return vertices.enumerated().map { index, v in
            let dir = unit(from: (cx, cy), to: v)
            let distance = style.fontSize * 1.1
            return text(letters[index % letters.count],
                        center: (v.x + dir.x * distance, v.y + dir.y * distance),
                        style: style, gid: gid)
        }
    }

    private static func unit(from a: Point, to b: Point) -> Point {
        let dx = b.x - a.x, dy = b.y - a.y
        let len = max(1e-9, (dx * dx + dy * dy).squareRoot())
        return (dx / len, dy / len)
    }

    private static func line(
        _ points: [Point], closed: Bool, style: MathsToolsStyle, gid: String,
        strokeWidth: Double? = nil, background: String = "transparent", opacity: Double = 100
    ) -> JSONValue {
        var pts = points
        if closed, let first = points.first {
            pts.append(first)
        }
        let origin = pts[0]
        let rel = pts.map { (x: $0.x - origin.x, y: $0.y - origin.y) }
        let minX = rel.map(\.x).min() ?? 0, maxX = rel.map(\.x).max() ?? 0
        let minY = rel.map(\.y).min() ?? 0, maxY = rel.map(\.y).max() ?? 0
        return .object([
            "type": .string("line"),
            "x": .number(origin.x),
            "y": .number(origin.y),
            "width": .number(maxX - minX),
            "height": .number(maxY - minY),
            "points": .array(rel.map { .array([.number($0.x), .number($0.y)]) }),
            "strokeColor": .string(style.strokeColor),
            "backgroundColor": .string(background),
            "fillStyle": .string("solid"),
            "strokeWidth": .number(strokeWidth ?? style.strokeWidth),
            "strokeStyle": .string("solid"),
            "roughness": .number(style.roughness),
            "opacity": .number(opacity),
            "roundness": .null,
            "groupIds": .array([.string(gid)])
        ])
    }

    private static func text(_ string: String, center: Point, style: MathsToolsStyle, gid: String) -> JSONValue {
        let approxWidth = Double(string.count) * style.fontSize * 0.58
        let approxHeight = style.fontSize * 1.25
        return .object([
            "type": .string("text"),
            "x": .number(center.x - approxWidth / 2),
            "y": .number(center.y - approxHeight / 2),
            "text": .string(string),
            "fontSize": .number(style.fontSize),
            "fontFamily": .number(Double(style.fontFamily)),
            "textAlign": .string("center"),
            "verticalAlign": .string("middle"),
            "strokeColor": .string(style.strokeColor),
            "roughness": .number(style.roughness),
            "groupIds": .array([.string(gid)])
        ])
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
