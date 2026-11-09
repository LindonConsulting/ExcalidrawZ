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
            if let expressions = request.expressions {
                try await replaceTextWithInlineSegments(request, expressions: expressions)
                return
            }
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

    /// Mixed prose + math: render every span, then let the web bundle lay the
    /// pieces out in place of the text element. Any failing span aborts so the
    /// text stays editable.
    @MainActor
    private func replaceTextWithInlineSegments(
        _ request: InlineMathRenderRequest,
        expressions: [String]
    ) async throws {
        var renders: [MathImageParams] = []
        for latex in expressions {
            let rendered = try await MathRenderService.shared.renderLatex(
                latex,
                foregroundColor: request.strokeColor
            )
            renders.append(rendered.mathImageParams)
        }
        let paramsJSON = try encodeJSON(InlineSegmentsParams(
            originalText: request.originalText,
            renders: renders
        ))
        let elementIdJSON = try encodeJSON(request.textElementId)
        _ = try await webView.callAsyncJavaScript(
            makeJavaScriptHelperCall(
                "window.excalidrawZHelper.replaceTextWithInlineSegments(\(elementIdJSON), \(paramsJSON))"
            ),
            arguments: [:],
            contentWorld: .page
        )
        documentSyncController.scheduleProgrammaticMutationCommit(reason: "replaceTextWithInlineSegments")
    }

    private struct InlineSegmentsParams: Codable {
        var originalText: String?
        var renders: [MathImageParams]
    }
}
