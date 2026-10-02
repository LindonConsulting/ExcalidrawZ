//
//  QuestionBankCanvasBridge.swift
//  ExcalidrawZ
//
//  Canvas ↔ question bank: capture the current selection (with frame
//  children, bound text and referenced image files) and insert a stored
//  question at the viewport centre.
//

import Foundation
import SwiftUI

/// What a capture produces before the user fills in the metadata.
struct QuestionBankCaptureDraft: Identifiable {
    var id = UUID()
    var elementsJSON: Data
    var filesJSON: Data?
    var thumbnailPNG: Data?
    var elementCount: Int
    /// Text found in the selection, used as the default title and for AI tagging.
    var textContent: [String]
}

enum QuestionBankCaptureError: LocalizedError {
    case canvasNotReady
    case nothingSelected

    var errorDescription: String? {
        switch self {
            case .canvasNotReady: return "The canvas is not ready."
            case .nothingSelected: return "Select a frame or some elements on the canvas first."
        }
    }
}

enum QuestionBankCanvasBridge {
    /// Collects the selected elements from the live canvas.
    @MainActor
    static func captureSelection(
        from coordinator: ExcalidrawCanvasView.Coordinator,
        colorScheme: ColorScheme
    ) async throws -> QuestionBankCaptureDraft {
        let selected = Set(coordinator.selectedElementIDs)
        guard !selected.isEmpty else { throw QuestionBankCaptureError.nothingSelected }

        let snapshot = try await coordinator.getCurrentFileSnapshot(includeFiles: true)
        let documentData = try snapshot.documentData(includeFiles: true)
        guard let document = try JSONSerialization.jsonObject(with: documentData) as? [String: Any],
              let allElements = document["elements"] as? [[String: Any]]
        else { throw QuestionBankCaptureError.canvasNotReady }

        // Selection + frame children + bound text (containerId) of anything selected.
        var ids = selected
        var changed = true
        while changed {
            changed = false
            for element in allElements where element["isDeleted"] as? Bool != true {
                guard let id = element["id"] as? String, !ids.contains(id) else { continue }
                if let frameId = element["frameId"] as? String, ids.contains(frameId) {
                    ids.insert(id); changed = true
                } else if let containerId = element["containerId"] as? String, ids.contains(containerId) {
                    ids.insert(id); changed = true
                }
            }
        }
        let elements = allElements.filter { element in
            element["isDeleted"] as? Bool != true && ids.contains(element["id"] as? String ?? "")
        }
        guard !elements.isEmpty else { throw QuestionBankCaptureError.nothingSelected }

        // Referenced binary files.
        let fileIDs = Set(elements.compactMap { $0["fileId"] as? String })
        var filesJSON: Data?
        if !fileIDs.isEmpty, let allFiles = document["files"] as? [String: Any] {
            let subset = allFiles.filter { fileIDs.contains($0.key) }
            if !subset.isEmpty {
                filesJSON = try JSONSerialization.data(withJSONObject: subset)
            }
        }

        let elementsJSON = try JSONSerialization.data(withJSONObject: elements)
        let texts = elements
            .filter { ($0["type"] as? String) == "text" }
            .compactMap { (($0["originalText"] as? String) ?? ($0["text"] as? String))?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var thumbnail: Data?
        if let typed = try? JSONDecoder().decode([ExcalidrawElement].self, from: elementsJSON) {
            var resourceFiles: [String: ExcalidrawFile.ResourceFile]?
            if let filesJSON {
                resourceFiles = try? JSONDecoder().decode([String: ExcalidrawFile.ResourceFile].self, from: filesJSON)
            }
            thumbnail = try? await coordinator.exportElementsToPNGData(
                elements: typed,
                files: resourceFiles,
                withBackground: true,
                colorScheme: colorScheme,
                exportScale: 2
            )
        }

        return QuestionBankCaptureDraft(
            elementsJSON: elementsJSON,
            filesJSON: filesJSON,
            thumbnailPNG: thumbnail,
            elementCount: elements.count,
            textContent: texts
        )
    }

    /// Inserts a stored question at the viewport centre and returns the new element ids.
    @MainActor
    static func insert(
        _ entry: QuestionBankEntry,
        from store: QuestionBankStore,
        into coordinator: ExcalidrawCanvasView.Coordinator
    ) async throws {
        let elementsJSON = try store.elementsJSON(for: entry.id)
        if let filesJSON = store.filesJSON(for: entry.id),
           let filesDict = try JSONSerialization.jsonObject(with: filesJSON) as? [String: Any] {
            let filesArray = Array(filesDict.values)
            let filesData = try JSONSerialization.data(withJSONObject: filesArray)
            if let filesString = String(data: filesData, encoding: .utf8) {
                _ = try await coordinator.webView.callAsyncJavaScript(
                    """
                    const api = window.excalidrawZHelper._api;
                    if (!api) { throw new Error("Excalidraw API is not ready"); }
                    api.addFiles(JSON.parse(filesJSON));
                    return true;
                    """,
                    arguments: ["filesJSON": filesString],
                    contentWorld: .page
                )
            }
        }
        let center = try await coordinator.getViewportCenter()
        let elements = try LibraryItemCanvasElementPreprocessor.prepare(
            blob: elementsJSON,
            placement: .center(x: center.x, y: center.y)
        )
        try await coordinator.addElements(elements)
    }
}
