//
//  PDFInsertSheetViewModifier.swift
//  ExcalidrawZ
//
//  Created by Claude on 2025/11/20.
//

import SwiftUI

#if canImport(PDFKit)
import PDFKit
#endif

struct PDFInsertSheetViewModifier: ViewModifier {
    @Environment(\.alertToast) private var alertToast
    @EnvironmentObject private var toolState: ToolState

    @Binding var isPresented: Bool

    @State private var sheetItem: PDFDropInfo?

    func body(content: Content) -> some View {
        content
            .sheet(item: $sheetItem) { item in
                PDFInsertSheet(
                    pdfInfo: item,
                    onInsert: { pdfData, mode, direction, itemsPerLine, frameWidth in
                        try await handlePDFInsert(
                            pdfData: pdfData,
                            mode: mode,
                            direction: direction,
                            itemsPerLine: itemsPerLine,
                            frameWidth: frameWidth,
                            sceneX: item.sceneX,
                            sceneY: item.sceneY
                        )
                    }
                )
            }
            .sheet(isPresented: $isPresented) {
                PDFInsertSheet(
                    onInsert: { pdfData, mode, direction, itemsPerLine, frameWidth in
                        try await handlePDFInsert(
                            pdfData: pdfData,
                            mode: mode,
                            direction: direction,
                            itemsPerLine: itemsPerLine,
                            frameWidth: frameWidth,
                            sceneX: 0,
                            sceneY: 0
                        )
                    }
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: .showPDFInsertSheet)) { notification in
                if let dropInfo = notification.object as? PDFDropInfo {
                    self.sheetItem = dropInfo
                }
            }
    }

    private func handlePDFInsert(
        pdfData: Data,
        mode: PDFInsertMode,
        direction: String,
        itemsPerLine: Int?,
        frameWidth: Double,
        sceneX: Double?,
        sceneY: Double?
    ) async throws {
        switch mode {
        case .viewer:
            // Insert as PDF viewer element
            _ = try await toolState.excalidrawWebCoordinator?.loadPDF(
                pdfData: pdfData,
                x: sceneX ?? 100,
                y: sceneY ?? 100,
                width: 600,
                height: 800
            )

        case .tiled:
            // Insert as tiled images with user-configured layout
            _ = try await toolState.excalidrawWebCoordinator?.loadPDFAsTiledImages(
                pdfData: pdfData,
                imageWidth: 400,
                direction: direction,
                itemsPerLine: itemsPerLine
            )

        case .pastPaper:
#if canImport(PDFKit)
            // Analyse and rasterise off the main thread, then insert.
            let rendered = try await Task.detached(priority: .userInitiated) { () throws -> [PastPaperRenderedQuestion] in
                guard let document = PDFDocument(data: pdfData) else {
                    throw PastPaperImportError.invalidPDF
                }
                let analysis = PastPaperAnalyzer.analyze(document)
                return try analysis.questions.map { try PastPaperRenderer.render($0, in: document) }
            }.value
            _ = try await toolState.excalidrawWebCoordinator?.importPastPaper(
                rendered,
                layout: .init(frameWidth: frameWidth)
            )
#else
            throw PastPaperImportError.unsupportedPlatform
#endif
        }
    }

    private enum PastPaperImportError: LocalizedError {
        case invalidPDF
        case unsupportedPlatform

        var errorDescription: String? {
            switch self {
                case .invalidPDF: return "The file is not a readable PDF."
                case .unsupportedPlatform: return "Past paper import needs PDFKit."
            }
        }
    }
}
