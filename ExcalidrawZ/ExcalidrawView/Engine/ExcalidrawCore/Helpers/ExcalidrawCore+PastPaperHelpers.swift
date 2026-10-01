//
//  ExcalidrawCore+PastPaperHelpers.swift
//  ExcalidrawZ
//
//  Created by Claude on 2026/10/01.
//

import CryptoKit
import Foundation
import WebKit

extension ExcalidrawCore {
    /// Layout of the imported question frames: a vertical column of
    /// fixed-size frames, each holding one question image scaled to fit.
    struct PastPaperLayout: Hashable {
        var frameWidth: Double = 960
        var frameAspectRatio: Double = 16.0 / 9.0
        var gap: Double = 80
        var padding: Double = 24

        var frameHeight: Double { frameWidth / frameAspectRatio }
    }

    struct PastPaperImportResult: Hashable {
        var frameIds: [String]
    }

    /// Inserts rendered past-paper questions as one named frame per question.
    ///
    /// Files are registered through the live Excalidraw API, elements are built
    /// from skeletons with `createElements` and appended with `addElements`, so
    /// no web-bundle change is required.
    @MainActor
    func importPastPaper(
        _ questions: [PastPaperRenderedQuestion],
        layout: PastPaperLayout = PastPaperLayout()
    ) async throws -> PastPaperImportResult {
        guard !webView.isLoading else { throw InvalidJavaScriptResult() }
        guard !questions.isEmpty else { return PastPaperImportResult(frameIds: []) }

        // 1. Register the PNGs as Excalidraw binary files.
        let files: [[String: Any]] = questions.map { question in
            [
                "id": Self.pastPaperFileId(for: question.pngData),
                "dataURL": "data:image/png;base64," + question.pngData.base64EncodedString(),
                "mimeType": "image/png",
                "created": Int(Date().timeIntervalSince1970 * 1000)
            ]
        }
        let filesData = try JSONSerialization.data(withJSONObject: files)
        guard let filesJSON = String(data: filesData, encoding: .utf8) else { throw JSONEncodingFailed() }
        let originRaw = try await webView.callAsyncJavaScript(
            makeJavaScriptHelperCall(Self.addFilesAndSuggestOriginScript),
            arguments: ["filesJSON": filesJSON],
            contentWorld: .page
        )
        let origin = try decodeJavaScriptHelperResult(originRaw, as: SceneOrigin.self)

        // 2. Build frame + image skeletons laid out as a column.
        var skeletons: [JSONValue] = []
        var frameIds: [String] = []
        for (index, question) in questions.enumerated() {
            let frameId = ExcalidrawNanoID.make()
            let imageId = ExcalidrawNanoID.make()
            frameIds.append(frameId)

            let frameX = origin.x
            let frameY = origin.y + Double(index) * (layout.frameHeight + layout.gap)
            let innerWidth = layout.frameWidth - layout.padding * 2
            let innerHeight = layout.frameHeight - layout.padding * 2
            let scale = min(
                innerWidth / Double(question.pointSize.width),
                innerHeight / Double(question.pointSize.height)
            )
            let imageWidth = Double(question.pointSize.width) * scale
            let imageHeight = Double(question.pointSize.height) * scale

            skeletons.append(.object([
                "type": .string("image"),
                "id": .string(imageId),
                "fileId": .string(files[index]["id"] as? String ?? ""),
                "x": .number(frameX + (layout.frameWidth - imageWidth) / 2),
                "y": .number(frameY + layout.padding),
                "width": .number(imageWidth),
                "height": .number(imageHeight),
                "status": .string("saved")
            ]))
            skeletons.append(.object([
                "type": .string("frame"),
                "id": .string(frameId),
                "name": .string(question.question.label),
                "x": .number(frameX),
                "y": .number(frameY),
                "width": .number(layout.frameWidth),
                "height": .number(layout.frameHeight),
                "children": .array([.string(imageId)])
            ]))
        }

        // 3. Convert and append.
        let elements = try await createElements(.array(skeletons), options: .init(regenerateIds: false))
        try await addElements(rawElementsJSON: try encodeJSON(elements))
        try? await zoomToFitElements(ids: frameIds)
        return PastPaperImportResult(frameIds: frameIds)
    }

    /// Registers the files with the live API and returns a free spot for the
    /// column: right of existing content, or the top-left of the viewport.
    private static let addFilesAndSuggestOriginScript = """
    (async () => {
        const api = window.excalidrawZHelper._api;
        if (!api) { throw new Error("Excalidraw API is not ready"); }
        api.addFiles(JSON.parse(filesJSON));
        const elements = api.getSceneElements();
        if (elements.length > 0) {
            let maxX = -Infinity;
            let minY = Infinity;
            for (const element of elements) {
                maxX = Math.max(maxX, element.x + element.width);
                minY = Math.min(minY, element.y);
            }
            return { x: maxX + 100, y: minY };
        }
        const appState = api.getAppState();
        return { x: -appState.scrollX + 100, y: -appState.scrollY + 100 };
    })()
    """

    private struct SceneOrigin: Decodable {
        var x: Double
        var y: Double
    }

    /// Excalidraw convention: the file id is the SHA-1 hex digest of the bytes.
    static func pastPaperFileId(for data: Data) -> String {
        Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
