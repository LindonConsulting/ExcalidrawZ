//
//  AIProposalSandbox.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/06/01.
//

import Foundation
import CoreGraphics

enum AIProposalSandbox {
    @MainActor private static var offscreenCore: ExcalidrawCore?

    enum ReadinessError: LocalizedError {
        case notReady

        var errorDescription: String? {
            switch self {
                case .notReady:
                    "AI proposal canvas is still loading. Please try again."
            }
        }
    }

    static func blankFile() -> ExcalidrawFile {
        ExcalidrawFile(
            source: "https://excalidraw.com",
            files: [:],
            version: 2,
            elements: [],
            appState: .init(),
            type: "excalidraw"
        )
    }

    static func blankFileData() -> Data? {
        try? JSONEncoder().encode(blankFile())
    }

    @MainActor
    static func waitForReadyCoordinator(
        timeoutNanoseconds: UInt64 = 2_000_000_000
    ) async -> ExcalidrawCanvasView.Coordinator? {
        try? await readyCoordinator(timeoutNanoseconds: timeoutNanoseconds)
    }

    @MainActor
    static func readyCoordinator(
        timeoutNanoseconds: UInt64 = 5_000_000_000
    ) async throws -> ExcalidrawCanvasView.Coordinator {
        let core = ensureOffscreenCore()
        if let readyCore = try await waitForReadyCore(
            core,
            timeoutNanoseconds: timeoutNanoseconds
        ) {
            return readyCore
        }

        let recreatedCore = recreateOffscreenCore()
        if let readyCore = try await waitForReadyCore(
            recreatedCore,
            timeoutNanoseconds: timeoutNanoseconds
        ) {
            return readyCore
        }

        throw ReadinessError.notReady
    }

    @MainActor
    private static func waitForReadyCore(
        _ core: ExcalidrawCore,
        timeoutNanoseconds: UInt64
    ) async throws -> ExcalidrawCore? {
        let stepNanoseconds: UInt64 = 50_000_000
        var waitedNanoseconds: UInt64 = 0

        while waitedNanoseconds < timeoutNanoseconds {
            try Task.checkCancellation()
            if core.isDocumentLoaded, !core.isLoading {
                return core
            }

            try await Task.sleep(nanoseconds: stepNanoseconds)
            waitedNanoseconds += stepNanoseconds
        }

        if core.isDocumentLoaded {
            return core
        }

        return nil
    }

    @MainActor
    private static func ensureOffscreenCore() -> ExcalidrawCore {
        if let offscreenCore {
            if offscreenCore.webView.url == nil {
                loadLocalExcalidrawPage(in: offscreenCore)
            }
            return offscreenCore
        }

        return makeOffscreenCore()
    }

    @MainActor
    private static func recreateOffscreenCore() -> ExcalidrawCore {
        makeOffscreenCore()
    }

    @MainActor
    private static func makeOffscreenCore() -> ExcalidrawCore {
        let core = ExcalidrawCore()
        core.webView.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        offscreenCore = core
        loadLocalExcalidrawPage(in: core)
        return core
    }

    @MainActor
    private static func loadLocalExcalidrawPage(in core: ExcalidrawCore) {
        let url: URL
        #if DEBUG
        url = URL(string: "http://127.0.0.1:8486/index.html")!
        #else
        url = URL(string: "http://127.0.0.1:8487/index.html")!
        #endif
        core.webView.load(URLRequest(url: url))
    }

    @MainActor
    static func resetCanvasIfAvailable() async {
        do {
            let coordinator = try await readyCoordinator()
            try await coordinator.replaceAllElements([])
        } catch {
            offscreenCore = nil
            return
        }
    }
}
