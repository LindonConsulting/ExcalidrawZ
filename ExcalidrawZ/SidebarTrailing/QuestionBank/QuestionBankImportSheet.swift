//
//  QuestionBankImportSheet.swift
//  ExcalidrawZ
//
//  Crop questions out of a PDF or image: pick a page, drag a rectangle,
//  "Add as question" opens the metadata sheet. Stays open so several
//  questions can be cropped from one paper.
//

import SwiftUI
import ChocofordUI

struct QuestionBankImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.alertToast) private var alertToast

    let document: QuestionBankImportDocument
    private let renderScale: CGFloat = 2

    @State private var pageIndex = 0
    @State private var page: CGImage?
    @State private var cropStart: CGPoint?
    @State private var cropRect: CGRect = .zero   // in view points of the displayed image
    @State private var draft: QuestionBankCaptureDraft?
    @State private var addedCount = 0
    @State private var sourceLabel = ""
    @State private var displayedWidth: CGFloat = 1

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Import questions from “\(document.name)”").font(.title3.bold())
                Spacer()
                if document.pageCount > 1 {
                    Stepper("Page \(pageIndex + 1) of \(document.pageCount)", value: $pageIndex, in: 0...(document.pageCount - 1))
                }
            }
            TextField("Source label for these questions (e.g. Edexcel 1MA1/1H June 2023)", text: $sourceLabel)
                .textFieldStyle(.roundedBorder)

            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    Color(white: 0.95)
                    if let page {
                        let fit = fittedSize(for: page, in: proxy.size)
                        Image(decorative: page, scale: 1)
                            .resizable()
                            .frame(width: fit.width, height: fit.height)
                            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                            .overlay(alignment: .topLeading) {
                                if cropRect.width > 2 {
                                    Rectangle()
                                        .fill(Color.accentColor.opacity(0.15))
                                        .overlay(Rectangle().stroke(Color.accentColor, lineWidth: 2))
                                        .frame(width: cropRect.width, height: cropRect.height)
                                        .offset(x: cropRect.minX, y: cropRect.minY)
                                        .allowsHitTesting(false)
                                }
                            }
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 2, coordinateSpace: .named("page"))
                                    .onChanged { value in
                                        let origin = CGPoint(x: (proxy.size.width - fit.width) / 2, y: (proxy.size.height - fit.height) / 2)
                                        let start = cropStart ?? CGPoint(x: value.startLocation.x - origin.x, y: value.startLocation.y - origin.y)
                                        cropStart = start
                                        displayedWidth = fit.width
                                        let current = CGPoint(x: value.location.x - origin.x, y: value.location.y - origin.y)
                                        cropRect = CGRect(
                                            x: min(start.x, current.x), y: min(start.y, current.y),
                                            width: abs(current.x - start.x), height: abs(current.y - start.y)
                                        ).intersection(CGRect(origin: .zero, size: fit))
                                    }
                                    .onEnded { _ in cropStart = nil }
                            )
                            .coordinateSpace(name: "page")
                    } else {
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .clipped()
                .onChange(of: pageIndex) { _ in loadPage() }
                .onAppear { if page == nil { loadPage() } }
                .onChange(of: proxy.size) { _ in cropRect = .zero }
            }
            .frame(minHeight: 420)

            HStack {
                Text(addedCount == 0 ? "Drag a rectangle around a question." : "\(addedCount) question\(addedCount == 1 ? "" : "s") added.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                Spacer()
                Button("Clear") { cropRect = .zero }.disabled(cropRect.width < 2)
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add as question…") { addCrop() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(cropRect.width < 8 || cropRect.height < 8 || page == nil)
            }
        }
        .padding(20)
        .frame(minWidth: 760, minHeight: 600)
        .sheet(item: $draft, onDismiss: { cropRect = .zero }) { draft in
            QuestionBankEntrySheet(draft: draft, defaultSource: sourceLabel) { addedCount += 1 }
        }
    }

    private func fittedSize(for image: CGImage, in container: CGSize) -> CGSize {
        let scale = min(container.width / CGFloat(image.width), container.height / CGFloat(image.height), 1)
        return CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
    }

    private func loadPage() {
        cropRect = .zero
        page = nil
        let index = pageIndex
        let document = self.document
        let scale = renderScale
        Task.detached {
            let rendered = document.renderPage(index, scale: scale)
            await MainActor.run { if index == pageIndex { page = rendered } }
        }
    }

    private func addCrop() {
        guard let page else { return }
        // cropRect is in displayed points; convert to page pixels.
        let displayScale = CGFloat(page.width) / max(displayedWidth, 1)
        let pixelRect = CGRect(
            x: cropRect.minX * displayScale, y: cropRect.minY * displayScale,
            width: cropRect.width * displayScale, height: cropRect.height * displayScale
        )
        do {
            draft = try QuestionBankImportDocument.makeDraft(from: page, crop: pixelRect, pixelsPerPoint: renderScale)
        } catch {
            alertToast(error)
        }
    }

}
