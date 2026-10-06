//
//  QuestionBankCaptureModifier.swift
//  ExcalidrawZ
//
//  Listens for the "add selection to question bank" command in the key
//  window, captures the selection and presents the metadata sheet.
//

import SwiftUI
import ChocofordUI
import os

private let qbLogger = os.Logger(subsystem: "com.lindon.questionbank", category: "capture")

struct QuestionBankCaptureModifier: ViewModifier {
    @Environment(\.alertToast) private var alertToast
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var fileState: FileState

    @State private var draft: QuestionBankCaptureDraft?
    @State private var isCapturing = false
    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .shouldCaptureQuestionBankSelection)) { _ in
                qbLogger.info("capture requested; isTargetWindow=\(isTargetWindow) isCapturing=\(isCapturing) hasWindow=\(activeCanvasCoordinator?.webView.window != nil)")
                guard isTargetWindow, !isCapturing else { return }
                Task { await capture() }
            }
            .sheet(item: $draft) { draft in
                QuestionBankEntrySheet(draft: draft, defaultSpecificationID: TutorKitContainer.shared.specificationID(forStudentNamed: currentStudentName))
            }
    }

    /// The key window normally; when the app is inactive (e.g. driven from
    /// the menu bar by automation) fall back to the front-most document window.
    private var isTargetWindow: Bool {
#if canImport(AppKit)
        // The window hosting this FileState's canvas (FileState is per window).
        guard let window = activeCanvasCoordinator?.webView.window else { return false }
        if window.isKeyWindow { return true }
        guard NSApp.keyWindow == nil else { return false }
        return NSApp.orderedWindows.first { $0.isVisible && !$0.isSheet && $0.contentView != nil } === window
#else
        return activeCanvasCoordinator?.webView.window?.isKeyWindow == true
#endif
    }

    private var currentStudentName: String? {
        if case .file(let file) = fileState.currentActiveFile { return file.group?.name }
        return nil
    }

    private var activeCanvasCoordinator: ExcalidrawCanvasView.Coordinator? {
        switch fileState.currentActiveFile {
            case .collaborationFile: fileState.excalidrawCollaborationWebCoordinator
            case .file, .localFile, .temporaryFile, .cloudStorageFile: fileState.excalidrawWebCoordinator
            case nil: nil
        }
    }

    private func capture() async {
        isCapturing = true
        defer { isCapturing = false }
        do {
            guard let coordinator = activeCanvasCoordinator else { throw QuestionBankCaptureError.canvasNotReady }
            qbLogger.info("selected ids: \(coordinator.selectedElementIDs.count)")
            draft = try await QuestionBankCanvasBridge.captureSelection(from: coordinator, colorScheme: colorScheme)
            qbLogger.info("captured \(draft?.elementCount ?? 0) elements")
        } catch {
            qbLogger.error("capture failed: \(error.localizedDescription)")
            alertToast(error)
        }
    }
}
