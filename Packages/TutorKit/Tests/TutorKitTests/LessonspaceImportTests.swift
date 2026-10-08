import XCTest
@testable import LessonspaceImport

final class LessonspaceImportTests: XCTestCase {
    // A real v3 stroke from a Room Export ("Whiteboard 10" tab, 2026-10-07).
    static let v3Bytes: [UInt8] = [3, 0, 5, 228, 134, 115, 243, 176, 9, 72, 13, 147, 160, 28, 177, 11, 214, 147, 97, 33, 37, 41, 152, 2, 27, 204, 57, 146, 30, 0, 252, 6, 10, 176, 1, 48, 146, 1, 182, 1, 178, 2, 112, 146, 1, 120, 128, 1, 114, 86, 120, 52, 156, 1, 28, 228, 1, 2, 166, 3, 119, 168, 4, 249, 1, 180, 4, 169, 2, 172, 5, 139, 3, 154, 1, 109, 86, 93, 26, 111, 37, 179, 1, 157, 1, 131, 2, 157, 2, 195, 2, 245, 2, 201, 2, 161, 3, 149, 2, 233, 2, 171, 1, 131, 2, 81, 209, 1, 45, 243, 1, 31]

    // A real v1 stroke (serialised Fabric path, M/Q/L) from the "Lessonspace Games" tab.
    static let v1Bytes: [UInt8] = [1, 0, 241, 88, 230, 90, 105, 163, 72, 35, 180, 217, 212, 208, 168, 108, 97, 236, 0, 0, 0, 0, 206, 0, 0, 0, 211, 17, 0, 0, 119, 2, 0, 0, 33, 37, 41, 255, 2, 33, 37, 41, 255, 0, 0, 0, 0, 0, 0, 181, 166, 145, 63, 181, 166, 145, 63, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0, 2, 77, 145, 89, 105, 69, 205, 236, 55, 197, 4, 81, 154, 89, 105, 69, 205, 236, 55, 197, 154, 89, 105, 69, 0, 120, 49, 197, 2, 76, 162, 89, 105, 69, 51, 3, 43, 197]

    func testV3BufferDecodesToPolyline() throws {
        XCTAssertEqual(LessonspaceStrokeDecoder.version(of: Self.v3Bytes), 3)
        let stroke = try XCTUnwrap(LessonspaceStrokeDecoder.decode(Self.v3Bytes))
        XCTAssertEqual(stroke.points.count, 27)
        XCTAssertEqual(stroke.points[0].x, 368.6, accuracy: 0.001)
        XCTAssertEqual(stroke.points[0].y, 192.9, accuracy: 0.001)
        XCTAssertEqual(stroke.points.last!.x, 430.0, accuracy: 0.001)
        XCTAssertEqual(stroke.points.last!.y, 136.8, accuracy: 0.001)
        let box = stroke.boundingBox
        XCTAssertEqual(box.width, 178.9, accuracy: 0.05)
        XCTAssertEqual(box.height, 154.2, accuracy: 0.05)
        XCTAssertEqual(stroke.strokeWidth, 5)
        XCTAssertEqual(stroke.colorHex, "#212529")
    }

    func testV1BufferParsesSegments() throws {
        XCTAssertEqual(LessonspaceStrokeDecoder.version(of: Self.v1Bytes), 1)
        let path = try XCTUnwrap(LessonspaceStrokeDecoder.parseV1(Self.v1Bytes))
        XCTAssertEqual(path.width, 0)
        XCTAssertEqual(path.height, 206)
        XCTAssertEqual(path.left, 4563)
        XCTAssertEqual(path.top, 631)
        XCTAssertEqual(path.strokeRGBA, [33, 37, 41, 255])
        XCTAssertEqual(path.strokeWidth, 2)
        XCTAssertEqual(path.scaleX, 1.1379, accuracy: 0.0001)
        XCTAssertEqual(path.segments.count, 3)
        guard case .move(let m) = path.segments[0],
              case .quad(let control, let end) = path.segments[1],
              case .line(let l) = path.segments[2]
        else { return XCTFail("expected M, Q, L; got \(path.segments)") }
        XCTAssertEqual(m.x, 3733.5979, accuracy: 0.001)
        XCTAssertEqual(m.y, -2942.8, accuracy: 0.001)
        XCTAssertEqual(control.y, -2942.8, accuracy: 0.001)
        XCTAssertEqual(end.y, -2839.5, accuracy: 0.001)
        XCTAssertEqual(l.y, -2736.2, accuracy: 0.001)

        // Flattened into canvas space: the path is placed at left + w·sx/2 and spans ~235 px vertically.
        let stroke = try XCTUnwrap(LessonspaceStrokeDecoder.decode(Self.v1Bytes))
        XCTAssertEqual(stroke.points.count, 6)
        XCTAssertEqual(stroke.points[0].x, 4563.0, accuracy: 0.01)
        XCTAssertEqual(stroke.points[0].y, 630.66, accuracy: 0.01)
        XCTAssertEqual(stroke.points.last!.y, 865.75, accuracy: 0.01)
        XCTAssertEqual(stroke.colorHex, "#212529")
    }

    func testUnknownVersionIsRejected() {
        XCTAssertNil(LessonspaceStrokeDecoder.decode([9, 0, 1, 2, 3]))
        XCTAssertNil(LessonspaceStrokeDecoder.decode([]))
        XCTAssertNil(LessonspaceStrokeDecoder.decode(Array(Self.v3Bytes.prefix(10))))
    }

    func testColourParsing() {
        XCTAssertEqual(LessonspaceSceneBuilder.hexColor("rgba(59,201,219,1)", default: "#000000"), "#3bc9db")
        XCTAssertEqual(LessonspaceSceneBuilder.hexColor("rgba(0,0,0,0)", default: "#000000"), "transparent")
        XCTAssertEqual(LessonspaceSceneBuilder.hexColor("#ABC", default: "#000000"), "#aabbcc")
        XCTAssertEqual(LessonspaceSceneBuilder.hexColor("white", default: "#000000"), "#ffffff")
        XCTAssertEqual(LessonspaceSceneBuilder.hexColor("", default: "#123456"), "#123456")
    }

    func testFabricObjectsBecomeItems() {
        let tab = LessonspaceTab(id: "t", name: "Whiteboard 1", position: 0, width: 1280, height: 720, objects: [
            ["type": "rect", "left": 10.0, "top": 20.0, "width": 100.0, "height": 50.0, "scaleX": 2.0, "scaleY": 1.0,
             "fill": "rgba(0,0,0,0)", "stroke": "rgba(33,37,41,1)", "strokeWidth": 6],
            ["type": "i-text", "left": 0.0, "top": 0.0, "width": 100.0, "height": 27.12, "fontSize": 24, "scaleX": 2.0, "scaleY": 2.0,
             "fill": "rgba(48,125,226,1)", "text": "Hello", "fontFamily": "Inter"],
            ["type": "i-text", "left": 0.0, "top": 0.0, "width": 10.0, "height": 10.0, "text": "hidden", "visible": false],
            ["type": "image", "left": 500.0, "top": 300.0, "originX": "center", "originY": "center", "width": 40.0, "height": 20.0, "src": "missing"],
            ["type": "arrow-line", "left": 82.0, "top": 93.0, "width": 72.0, "height": 40.0, "stroke": "rgba(55,178,77,1)", "strokeWidth": 6,
             "path": [["M", 82.0, 93.0], ["L", 154.0, 133.0], ["M", 134.0, 130.0], ["L", 154.0, 133.0]]],
            ["type": "Buffer", "data": Self.v3Bytes.map { Int($0) }],
            ["type": "mystery"],
        ])
        let scene = LessonspaceSceneBuilder.scene(for: tab, assets: [:])
        XCTAssertEqual(scene.items.count, 4)
        XCTAssertEqual(scene.skippedTypes, ["mystery"])

        guard case .shape(let kind, let frame, _, let stroke, let fill, let strokeWidth, _) = scene.items[0] else { return XCTFail() }
        XCTAssertEqual(kind, .rectangle)
        XCTAssertEqual(frame, CGRect(x: 10, y: 20, width: 200, height: 50))
        XCTAssertEqual(stroke, "#212529"); XCTAssertEqual(fill, "transparent"); XCTAssertEqual(strokeWidth, 12)

        guard case .text(let text, let textFrame, let fontSize, let color, _, _, _) = scene.items[1] else { return XCTFail() }
        XCTAssertEqual(text, "Hello"); XCTAssertEqual(fontSize, 48); XCTAssertEqual(color, "#307de2")
        XCTAssertEqual(textFrame.width, 200)

        guard case .line(let points, let arrow, _, _, _, _) = scene.items[2] else { return XCTFail() }
        XCTAssertTrue(arrow); XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points[1], CGPoint(x: 154, y: 133))

        guard case .stroke(let s) = scene.items[3] else { return XCTFail() }
        XCTAssertEqual(s.points.count, 27)
    }

    func testZipRoundTrip() throws {
        // Build a tiny stored ZIP by hand: one tab JSON and one asset.
        let tabJSON = try JSONSerialization.data(withJSONObject: [
            "meta": ["id": "tab1", "module": "Whiteboard", "meta": ["name": "Blank Lesson Plan", "position": 1]],
            "data": [["type": "Buffer", "data": Self.v3Bytes.map { Int($0) }]],
        ])
        let tab2JSON = try JSONSerialization.data(withJSONObject: [
            "meta": ["id": "tab0", "module": "Whiteboard", "meta": ["name": "Maths", "position": 0]],
            "data": [["type": "image", "left": 0, "top": 0, "width": 2, "height": 2, "src": "asset1"]],
        ])
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEElEQVR4nGP4z8DwHwyBNAAo0QX5tDcW3QAAAABJRU5ErkJggg==")!
        let zip = Self.storedZip([
            ("room.sh-abc/tab1", tabJSON),
            ("room.sh-abc/tab0", tab2JSON),
            ("room.sh-abc/files/asset1", png),
            (".room_exported", Data("x".utf8)),
        ])
        let export = try LessonspaceRoomExport(zipData: zip)
        XCTAssertEqual(export.tabs.map(\.name), ["Maths", "Blank Lesson Plan"])
        XCTAssertEqual(export.tabs(includingTemplates: false).map(\.name), ["Maths"])
        XCTAssertEqual(export.assets["asset1"], png)

        let scene = LessonspaceSceneBuilder.scene(for: export.tabs[0], assets: export.assets)
        guard case .image(let asset, let frame, _, _, _) = scene.items.first else { return XCTFail() }
        XCTAssertEqual(asset.mimeType, "image/png")
        XCTAssertEqual(asset.id, "asset1")
        XCTAssertEqual(frame.size, CGSize(width: 2, height: 2))
        XCTAssertEqual(LessonspaceSceneBuilder.pixelSize(of: png), CGSize(width: 2, height: 2))
    }

    /// Minimal ZIP writer (method 0) for tests.
    static func storedZip(_ files: [(String, Data)]) -> Data {
        var out = Data(); var central = Data()
        func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)] }
        func le32(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)] }
        for (name, data) in files {
            let nameBytes = Array(name.utf8)
            let offset = out.count
            out += [0x50, 0x4b, 0x03, 0x04] + le16(20) + le16(0) + le16(0) + le16(0) + le16(0) + le32(0)
            out += le32(data.count) + le32(data.count) + le16(nameBytes.count) + le16(0) + nameBytes
            out += data
            central += [0x50, 0x4b, 0x01, 0x02] + le16(20) + le16(20) + le16(0) + le16(0) + le16(0) + le16(0) + le32(0)
            central += le32(data.count) + le32(data.count) + le16(nameBytes.count) + le16(0) + le16(0) + le16(0) + le16(0) + le32(0)
            central += le32(offset) + nameBytes
        }
        let centralOffset = out.count
        out += central
        out += [0x50, 0x4b, 0x05, 0x06] + le16(0) + le16(0) + le16(files.count) + le16(files.count) + le32(central.count) + le32(centralOffset) + le16(0)
        return out
    }
}

extension LessonspaceImportTests {
    /// Uses a real Room Export when one is present in ~/Downloads; skipped otherwise.
    func testRealRoomExportIfPresent() throws {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)
        guard let url = downloads.lazy.compactMap({ LessonspaceRoomExport.roomExportZIPs(in: $0).first }).first else {
            throw XCTSkip("No Room Export ZIP in Downloads")
        }
        let export = try LessonspaceRoomExport(zipURL: url)
        XCTAssertFalse(export.tabs.isEmpty)
        XCTAssertFalse(export.assets.isEmpty)
        var strokes = 0, images = 0, texts = 0
        for tab in export.tabs {
            let scene = LessonspaceSceneBuilder.scene(for: tab, assets: export.assets)
            for item in scene.items {
                switch item {
                    case .stroke: strokes += 1
                    case .image(let asset, _, _, _, _):
                        images += 1
                        XCTAssertEqual(asset.mimeType, "image/png")
                        XCTAssertNotNil(LessonspaceSceneBuilder.pixelSize(of: asset.data))
                    case .text: texts += 1
                    default: break
                }
            }
            XCTAssertTrue(scene.skippedTypes.isEmpty, "unhandled fabric types in \(tab.name): \(scene.skippedTypes)")
        }
        XCTAssertGreaterThan(strokes, 0)
        XCTAssertGreaterThan(images, 0)
        // Every page of every PDF asset is rendered.
        for (_, data) in export.assets where data.starts(with: [0x25, 0x50, 0x44, 0x46]) {
            let pages = LessonspaceSceneBuilder.renderPDFPages(data)
            XCTAssertGreaterThan(pages.count, 0)
        }
    }
}
