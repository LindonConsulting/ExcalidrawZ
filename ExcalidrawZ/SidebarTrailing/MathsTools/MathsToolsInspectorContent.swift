//
//  MathsToolsInspectorContent.swift
//  ExcalidrawZ
//
//  Trailing-sidebar panel with maths teaching tools. Triangles and the
//  compass are interactive (drawn on the canvas with the pointer, see
//  mathsTools.js in the web fork); the angle and protractor are inserted
//  ready-made at the viewport centre.
//

import SwiftUI
import ChocofordUI
import SFSafeSymbols
import SwiftyAlert

struct MathsToolsInspectorContent: View {
    @Environment(\.alertToast) private var alertToast
    @EnvironmentObject private var fileState: FileState

    @AppStorage("MathsToolsSize") private var size: Double = 240
    @AppStorage("MathsToolsHandDrawn") private var handDrawn = false
    @AppStorage("MathsToolsLabelVertices") private var labelVertices = false
    @AppStorage("MathsToolsAngleDegrees") private var angleDegrees: Double = 45
    @AppStorage("MathsToolsAngleLabel") private var showAngleLabel = true
    @AppStorage("MathsToolsProtractorFine") private var fineTicks = false
    @AppStorage("MathsToolsCompassRadius") private var compassRadius: Double = 120
    @AppStorage("MathsToolsCompassCentre") private var compassCentre = false

    @State private var isInserting = false
    @State private var angleText = ""

    private let quickAngles: [Double] = [30, 45, 60, 90, 120, 135]

    private var style: MathsToolsStyle {
        MathsToolsStyle(
            roughness: handDrawn ? 1 : 0,
            fontSize: max(14, (size * 0.085).rounded()),
            labelVertices: labelVertices
        )
    }

    private var activeCanvasCoordinator: ExcalidrawCanvasView.Coordinator? {
        switch fileState.currentActiveFile {
            case .collaborationFile: fileState.excalidrawCollaborationWebCoordinator
            case .file, .localFile, .temporaryFile, .cloudStorageFile: fileState.excalidrawWebCoordinator
            case nil: nil
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let coordinator = activeCanvasCoordinator {
                    MathsToolStatusBanner(core: coordinator)
                }
                trianglesSection
                Divider()
                compassSection
                Divider()
                angleSection
                Divider()
                protractorSection
                Divider()
                styleSection
            }
            .padding(16)
        }
        .disabled(isInserting)
        .onAppear { angleText = formatted(angleDegrees) }
        .onChange(of: compassRadius) { _ in
            updateToolOptions(.object(["radius": .number(compassRadius)]))
        }
        .onChange(of: compassCentre) { _ in
            updateToolOptions(.object(["centreMark": .bool(compassCentre)]))
        }
        .onChange(of: labelVertices) { _ in
            updateToolOptions(.object(["labels": .bool(labelVertices)]))
        }
    }

    // MARK: Sections

    private var trianglesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Triangles")
            HStack(spacing: 8) {
                toolButton(title: "Right-angled", preview: .rightAngled) {
                    startTool(.object([
                        "kind": .string("triangle"), "variant": .string("right"),
                        "labels": .bool(labelVertices)
                    ]))
                }
                toolButton(title: "Equilateral", preview: .equilateral) {
                    startTool(.object([
                        "kind": .string("triangle"), "variant": .string("equilateral"),
                        "labels": .bool(labelVertices)
                    ]))
                }
                toolButton(title: "Isosceles", preview: .isosceles(apex: 40)) {
                    startTool(.object([
                        "kind": .string("triangle"), "variant": .string("isosceles"),
                        "labels": .bool(labelVertices)
                    ]))
                }
            }
            Text("Drag on the canvas like the rectangle tool. The point you press is the right angle, or the apex for isosceles and equilateral.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var compassSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Compass")
            HStack {
                Text("Radius").foregroundStyle(.secondary)
                Slider(value: $compassRadius, in: 20...400, step: 5)
                Text("\(Int(compassRadius))")
                    .monospacedDigit()
                    .frame(width: 36, alignment: .trailing)
            }
            .font(.callout)
            Toggle("Mark the pin point", isOn: $compassCentre)
                .font(.callout)
            HStack(spacing: 8) {
                MathsToolPreview(kind: .compassArc(start: 20, sweep: 110))
                    .frame(width: 44, height: 44)
                Button {
                    startTool(.object([
                        "kind": .string("compass"),
                        "radius": .number(compassRadius),
                        "centreMark": .bool(compassCentre)
                    ]))
                } label: {
                    Label("Compass", systemSymbol: .scope)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button {
                    insert(MathsToolsElementFactory.compassCircle(
                        radius: compassRadius, showCentre: compassCentre, style: style
                    ))
                } label: {
                    Label("Circle", systemSymbol: .plus)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .help("Insert a full circle of this radius at the viewport centre")
            }
            Text("Click to place the pin, then drag to swing the pencil around it. Click elsewhere to move the pin; Esc lifts it, Esc again puts the compass away.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var angleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Angle")
            HStack(spacing: 10) {
                Slider(value: $angleDegrees, in: 1...359, step: 1) { _ in
                    angleText = formatted(angleDegrees)
                }
                TextField("°", text: $angleText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 56)
                    .multilineTextAlignment(.trailing)
                    .onSubmit(commitAngleText)
                Text("°").foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                ForEach(quickAngles, id: \.self) { value in
                    Button("\(Int(value))°") {
                        angleDegrees = value
                        angleText = formatted(value)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(angleDegrees == value ? .accentColor : nil)
                }
            }
            Toggle("Show degree label", isOn: $showAngleLabel)
                .font(.callout)
            HStack {
                MathsToolPreview(kind: .angle(degrees: angleDegrees))
                    .frame(width: 44, height: 44)
                Button {
                    commitAngleText()
                    insert(MathsToolsElementFactory.angle(
                        degrees: angleDegrees, size: size, showLabel: showAngleLabel, style: style
                    ))
                } label: {
                    Label("Insert \(formatted(angleDegrees))° angle", systemSymbol: .plus)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var protractorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Protractor")
            Toggle("Fine 1° marks", isOn: $fineTicks)
                .font(.callout)
            HStack {
                MathsToolPreview(kind: .protractor)
                    .frame(width: 44, height: 44)
                Button {
                    insert(MathsToolsElementFactory.protractor(
                        radius: size * 0.75, fineTicks: fineTicks, style: style
                    ))
                } label: {
                    Label("Insert protractor", systemSymbol: .plus)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            Text("Drag the protractor so its centre mark sits on the vertex, then turn it with the rotation handle; it pivots about the centre mark.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var styleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Style")
            HStack {
                Text("Size").foregroundStyle(.secondary)
                Slider(value: $size, in: 120...600, step: 10)
                Text("\(Int(size))")
                    .monospacedDigit()
                    .frame(width: 36, alignment: .trailing)
            }
            .font(.callout)
            Toggle("Hand-drawn angle and protractor", isOn: $handDrawn)
                .font(.callout)
            Toggle("Label triangle vertices", isOn: $labelVertices)
                .font(.callout)
            Text("Triangles and compass arcs use the current stroke colour, width and sloppiness from the toolbar.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Pieces

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.headline)
    }

    private func toolButton(
        title: String,
        preview: MathsToolPreview.Kind,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                MathsToolPreview(kind: preview)
                    .frame(width: 44, height: 40)
                Text(title)
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.bordered)
        .help("Draw \(title.lowercased()) triangle")
    }

    private func formatted(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
    }

    private func commitAngleText() {
        let cleaned = angleText.replacingOccurrences(of: "°", with: "").trimmingCharacters(in: .whitespaces)
        if let value = Double(cleaned), value >= 1, value <= 359 {
            angleDegrees = value
        }
        angleText = formatted(angleDegrees)
    }

    private func startTool(_ spec: ExcalidrawCore.JSONValue) {
        guard let coordinator = activeCanvasCoordinator else {
            alertToast(.init(displayMode: .hud, type: .error(.red), title: "Open a canvas first."))
            return
        }
        Task { @MainActor in
            do {
                try await coordinator.startMathsTool(spec)
            } catch {
                alertToast(error)
            }
        }
    }

    private func updateToolOptions(_ options: ExcalidrawCore.JSONValue) {
        guard let coordinator = activeCanvasCoordinator, coordinator.mathsToolState.active else { return }
        Task { @MainActor in
            try? await coordinator.setMathsToolOptions(options)
        }
    }

    private func insert(_ build: MathsToolsBuild) {
        guard let coordinator = activeCanvasCoordinator else {
            alertToast(.init(displayMode: .hud, type: .error(.red), title: "Open a canvas first."))
            return
        }
        isInserting = true
        Task { @MainActor in
            defer { isInserting = false }
            do {
                try await MathsToolsCanvasBridge.insert(build, into: coordinator)
            } catch {
                alertToast(error)
            }
        }
    }
}

/// Shows which interactive tool is running on the canvas, with a Stop button.
private struct MathsToolStatusBanner: View {
    @ObservedObject var core: ExcalidrawCore

    private var message: String? {
        let state = core.mathsToolState
        guard state.active else { return nil }
        switch state.kind {
            case "triangle":
                let name: String
                switch state.variant {
                    case "equilateral": name = "equilateral"
                    case "isosceles": name = "isosceles"
                    default: name = "right-angled"
                }
                return "Drag on the canvas to draw a \(name) triangle."
            case "compass":
                return state.hasPin == true
                    ? "Drag to draw an arc. Click to move the pin."
                    : "Click on the canvas to place the compass pin."
            default:
                return "Maths tool active."
        }
    }

    var body: some View {
        if let message {
            HStack(spacing: 10) {
                Image(systemSymbol: .scope)
                    .foregroundStyle(Color.accentColor)
                Text(message)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("Stop") {
                    Task { @MainActor in try? await core.stopMathsTool() }
                }
                .controlSize(.small)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
            )
        }
    }
}

/// Small vector previews for the tool buttons.
struct MathsToolPreview: View {
    enum Kind {
        case rightAngled
        case equilateral
        case isosceles(apex: Double)
        case angle(degrees: Double)
        case protractor
        case compassArc(start: Double, sweep: Double)
    }

    let kind: Kind

    var body: some View {
        Canvas { context, size in
            let inset: CGFloat = 4
            let w = size.width - inset * 2
            let h = size.height - inset * 2
            let origin = CGPoint(x: inset, y: inset)
            var path = Path()
            var marker = Path()

            switch kind {
                case .rightAngled:
                    let a = CGPoint(x: origin.x, y: origin.y + h)
                    let b = CGPoint(x: origin.x, y: origin.y)
                    let c = CGPoint(x: origin.x + w, y: origin.y + h)
                    path.move(to: b); path.addLine(to: a); path.addLine(to: c); path.closeSubpath()
                    let m: CGFloat = 7
                    marker.move(to: CGPoint(x: a.x, y: a.y - m))
                    marker.addLine(to: CGPoint(x: a.x + m, y: a.y - m))
                    marker.addLine(to: CGPoint(x: a.x + m, y: a.y))
                case .equilateral:
                    let side = min(w, h / 0.866)
                    let th = side * 0.866
                    let left = origin.x + (w - side) / 2
                    let top = origin.y + (h - th) / 2
                    path.move(to: CGPoint(x: left + side / 2, y: top))
                    path.addLine(to: CGPoint(x: left, y: top + th))
                    path.addLine(to: CGPoint(x: left + side, y: top + th))
                    path.closeSubpath()
                case .isosceles(let apex):
                    let half = CGFloat(apex.clampedPreview / 2 * .pi / 180)
                    var leg = h / cos(half)
                    if leg * sin(half) * 2 > w { leg = w / (2 * sin(half)) }
                    let th = leg * cos(half)
                    let hb = leg * sin(half)
                    let cx = origin.x + w / 2
                    let top = origin.y + (h - th) / 2
                    path.move(to: CGPoint(x: cx, y: top))
                    path.addLine(to: CGPoint(x: cx - hb, y: top + th))
                    path.addLine(to: CGPoint(x: cx + hb, y: top + th))
                    path.closeSubpath()
                case .angle(let degrees):
                    let theta = CGFloat(degrees.clampedPreview * .pi / 180)
                    let r = min(w, h) * 0.9
                    let v = CGPoint(x: origin.x + w * 0.15, y: origin.y + h * 0.85)
                    path.move(to: CGPoint(x: v.x + r, y: v.y))
                    path.addLine(to: v)
                    path.addLine(to: CGPoint(x: v.x + r * cos(theta), y: v.y - r * sin(theta)))
                    marker.addArc(center: v, radius: r * 0.35, startAngle: .zero, endAngle: .radians(-theta), clockwise: true)
                case .compassArc(let start, let sweep):
                    let r = min(w, h) * 0.42
                    let c = CGPoint(x: origin.x + w / 2, y: origin.y + h / 2)
                    let s = start * .pi / 180
                    let e = (start + sweep.clampedPreview) * .pi / 180
                    path.addArc(center: c, radius: r, startAngle: .radians(-s), endAngle: .radians(-e), clockwise: true)
                    marker.move(to: CGPoint(x: c.x - 3, y: c.y)); marker.addLine(to: CGPoint(x: c.x + 3, y: c.y))
                    marker.move(to: CGPoint(x: c.x, y: c.y - 3)); marker.addLine(to: CGPoint(x: c.x, y: c.y + 3))
                case .protractor:
                    let r = min(w / 2, h * 0.9)
                    let c = CGPoint(x: origin.x + w / 2, y: origin.y + h * 0.9)
                    path.addArc(center: c, radius: r, startAngle: .degrees(180), endAngle: .zero, clockwise: false)
                    path.closeSubpath()
                    for d in stride(from: 0, through: 180, by: 30) {
                        let rad = CGFloat(d) * .pi / 180
                        marker.move(to: CGPoint(x: c.x + r * cos(rad), y: c.y - r * sin(rad)))
                        marker.addLine(to: CGPoint(x: c.x + r * 0.75 * cos(rad), y: c.y - r * 0.75 * sin(rad)))
                    }
            }
            context.stroke(path, with: .color(.primary), lineWidth: 1.5)
            context.stroke(marker, with: .color(.primary), lineWidth: 1)
        }
    }
}

private extension Double {
    var clampedPreview: Double { Swift.min(Swift.max(self, 1), 359) }
}
