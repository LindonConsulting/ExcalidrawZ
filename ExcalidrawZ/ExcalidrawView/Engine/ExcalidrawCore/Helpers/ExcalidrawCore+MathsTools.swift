//
//  ExcalidrawCore+MathsTools.swift
//  ExcalidrawZ
//
//  Bridge to the interactive maths tools (drag-to-draw triangles, compass)
//  implemented in excalidraw-app/excalidrawZ/mathsTools.js.
//

import Foundation

extension ExcalidrawCore {
    @MainActor
    func startMathsTool(_ spec: JSONValue) async throws {
        guard !webView.isLoading else { throw InvalidJavaScriptResult() }
        let specJSON = try encodeJSON(spec)
        let result = try await webView.callAsyncJavaScript(
            makeJavaScriptHelperCall("window.excalidrawZHelper.startMathsTool(\(specJSON))"),
            arguments: [:],
            contentWorld: .page
        )
        let state = try decodeJavaScriptHelperResult(result, as: MathsToolState.self)
        mathsToolState = state
    }

    @MainActor
    func stopMathsTool() async throws {
        guard !webView.isLoading else { return }
        _ = try await webView.callAsyncJavaScript(
            makeJavaScriptHelperCall("window.excalidrawZHelper.stopMathsTool()"),
            arguments: [:],
            contentWorld: .page
        )
        mathsToolState = MathsToolState(active: false)
    }

    @MainActor
    func setMathsToolOptions(_ options: JSONValue) async throws {
        guard !webView.isLoading else { return }
        let optionsJSON = try encodeJSON(options)
        _ = try await webView.callAsyncJavaScript(
            makeJavaScriptHelperCall("window.excalidrawZHelper.setMathsToolOptions(\(optionsJSON))"),
            arguments: [:],
            contentWorld: .page
        )
    }
}
