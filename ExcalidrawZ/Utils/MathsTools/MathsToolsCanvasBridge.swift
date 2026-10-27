//
//  MathsToolsCanvasBridge.swift
//  ExcalidrawZ
//
//  Inserts a maths-tool build at the viewport centre and selects the
//  resulting group so it can be moved or rotated straight away.
//

import Foundation

enum MathsToolsCanvasBridge {
    @MainActor
    static func insert(
        _ build: MathsToolsBuild,
        into coordinator: ExcalidrawCanvasView.Coordinator
    ) async throws {
        let result = try await coordinator.insertFromSkeleton(
            .array(build.skeletons),
            options: .init(position: .viewportCenter)
        )
        guard !result.elementIds.isEmpty else { return }
        let idsData = try JSONSerialization.data(withJSONObject: result.elementIds)
        guard let idsJSON = String(data: idsData, encoding: .utf8) else { return }
        _ = try await coordinator.webView.callAsyncJavaScript(
            """
            const api = window.excalidrawZHelper._api;
            if (!api) { throw new Error("Excalidraw API is not ready"); }
            const ids = JSON.parse(idsJSON);
            const selectedElementIds = {};
            for (const id of ids) { selectedElementIds[id] = true; }
            const selectedGroupIds = {};
            selectedGroupIds[groupId] = true;
            api.updateScene({
              appState: { selectedElementIds, selectedGroupIds, editingGroupId: null },
              captureUpdate: "NEVER",
            });
            return true;
            """,
            arguments: ["idsJSON": idsJSON, "groupId": build.groupID],
            contentWorld: .page
        )
    }
}
