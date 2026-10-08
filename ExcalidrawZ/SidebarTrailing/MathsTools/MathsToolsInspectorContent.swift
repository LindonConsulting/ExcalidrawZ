//
//  MathsToolsInspectorContent.swift
//  ExcalidrawZ
//
//  Trailing-sidebar panel with maths teaching tools: triangles, an angle
//  drawer and a protractor. Each tool drops a grouped, selected shape at
//  the viewport centre.
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
    @AppStorage("MathsToolsLabelVertices") private var labelVertices = true
    @AppStorage("MathsToolsIsoscelesApex") private var apexAngle: Double = 40
    @AppStorage("MathsToolsAngleDegrees") private var angleDegrees: Double = 45
    @AppStorage("MathsToolsAngleLabel") private var showAngleLabel = true
    @AppStorage("MathsToolsProtractorFine") private var fineTicks = false
    @AppStorage("MathsToolsCompassRadius") private var compassRadius: Double = 120
    @AppStorage("MathsToolsCompassSweep") private var compassSweep: Double = 60
    @AppStorage("MathsToolsCompassStart") private var compassStart: Double = 0
    @AppStorage("MathsToolsCompassCentre") private var compassCentre = true

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
                trianglesSection
                Divider()
                angleSection
                Divider()
                protractorSection
                Divider()
                compassSection
                Divider()
                styleSection
            }
            .padding(16)
        }
        .disabled(isInserting)
        .onAppear { angleText = formatted(angleDegrees) }
    }

    // MARK: Sections

    private var trianglesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Triangles")
            HStack(spacing: 8) {
                toolButton(title: "Right-angled", preview: .rightAngled) {
                    MathsToolsElementFactory.rightAngledTriangle(size: size, style: style)
                }
                toolButton(title: "Equilateral", preview: .equilateral) {
                    MathsToolsElementFactory.equilateralTriangle(size: size, style: style)
                }
                toolButton(title: "Isosceles", preview: .isosceles(apex: apexAngle)) {
                    MathsToolsElementFactory.isoscelesTriangle(size: size, apexAngle: apexAngle, style: style)
                }
            }
            HStack {
                Text("Isosceles apex")
                    .foregroundStyle(.secondary)
                Spacer()
                Stepper(value: $apexAngle, in: 10...170, step: 5) {
                    Text("\(Int(apexAngle))°")
                        .monospacedDigit()
                        .frame(minWidth: 36, alignment: .trailing)
                }
            }
            .font(.callout)
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
            Text("Select the protractor and drag its rotation handle to line it up with an angle.")
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
            HStack {
                Text("Arc sweep").foregroundStyle(.secondary)
                Slider(value: $compassSweep, in: 10...360, step: 5)
                Text("\(Int(compassSweep))°")
                    .monospacedDigit()
                    .frame(width: 40, alignment: .trailing)
            }
            .font(.callout)
            HStack {
                Text("Start angle").foregroundStyle(.secondary)
                Slider(value: $compassStart, in: 0...359, step: 5)
                Text("\(Int(compassStart))°")
                    .monospacedDigit()
                    .frame(width: 40, alignment: .trailing)
            }
            .font(.callout)
            Toggle("Mark the centre", isOn: $compassCentre)
                .font(.callout)
            HStack(spacing: 8) {
                MathsToolPreview(kind: .compassArc(start: compassStart, sweep: compassSweep))
                    .frame(width: 44, height: 44)
                Button {
                    insert(MathsToolsElementFactory.compassArc(
                        radius: compassRadius, startDegrees: compassStart, sweepDegrees: compassSweep,
                        showCentre: compassCentre, style: style
                    ))
                } label: {
                    Label("Arc", systemSymbol: .plus)
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
            }
            Text("Drag the group so the centre mark sits on the point you are constructing from; arcs of the same radius intersect exactly.")
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
            Toggle("Hand-drawn style", isOn: $handDrawn)
                .font(.callout)
            Toggle("Label triangle vertices", isOn: $labelVertices)
                .font(.callout)
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
        build: @escaping () -> MathsToolsBuild
    ) -> some View {
        Button {
            insert(build())
        } label: {
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
        .help("Insert \(title.lowercased()) triangle")
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
