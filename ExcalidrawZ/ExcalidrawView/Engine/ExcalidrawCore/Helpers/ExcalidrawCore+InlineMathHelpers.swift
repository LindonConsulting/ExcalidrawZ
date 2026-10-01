//
//  ExcalidrawCore+InlineMathHelpers.swift
//  ExcalidrawZ
//
//  Created by Claude on 2026/10/01.
//

import Foundation

extension ExcalidrawCore {
    @MainActor
    func setInlineLatexEnabled(_ enabled: Bool) async throws {
        _ = try await webView.callAsyncJavaScript(
            "window.excalidrawZHelper.setInlineLatexEnabled(enabled);",
            arguments: ["enabled": enabled],
            contentWorld: .page
        )
    }

    /// Render the LaTeX from an inline text element natively and hand the SVG
    /// back to the web bundle, which swaps the text element for a math image.
    /// A render failure (invalid LaTeX) leaves the text element untouched.
    @MainActor
    func handleInlineMathRenderRequest(_ request: InlineMathRenderRequest) async {
        guard !webView.isLoading else { return }
        do {
            let rendered = try await MathRenderService.shared.renderLatex(
                request.latex,
                foregroundColor: request.strokeColor
            )
            var params = rendered.mathImageParams
            params.originalText = request.originalText
            let elementIdJSON = try encodeJSON(request.textElementId)
            let paramsJSON = try encodeJSON(params)
            _ = try await webView.callAsyncJavaScript(
                makeJavaScriptHelperCall(
                    "window.excalidrawZHelper.replaceTextWithMathImage(\(elementIdJSON), \(paramsJSON))"
                ),
                arguments: [:],
                contentWorld: .page
            )
            documentSyncController.scheduleProgrammaticMutationCommit(reason: "replaceTextWithMathImage")
        } catch {
            logger.warning("Inline LaTeX render failed for \(request.textElementId): \(error)")
        }
    }
}
