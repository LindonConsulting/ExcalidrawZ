//
//  PastPaperRenderer.swift
//  ExcalidrawZ
//
//  Created by Claude on 2026/10/01.
//

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

#if canImport(PDFKit)
import PDFKit
#endif

/// A rendered question image ready for the canvas.
struct PastPaperRenderedQuestion {
    var question: PastPaperQuestion
    var pngData: Data
    /// Size in PDF points (the renderer's logical size, before any canvas scaling).
    var pointSize: CGSize
}

#if canImport(PDFKit)
/// Rasterises question segments into one PNG per question, stacking multi-page
/// segments top to bottom.
enum PastPaperRenderer {
    struct RenderError: LocalizedError {
        var label: String
        var errorDescription: String? { "Failed to render \(label)" }
    }

    /// - Parameters:
    ///   - scale: Pixels per PDF point. 2 gives crisp text at typical canvas zooms.
    ///   - segmentGap: Vertical gap (points) between stacked page segments.
    struct CompressionOptions {
        /// Vertical runs of ink-free rows longer than this (points) are shortened.
        var minimumRun: CGFloat = 36
        /// Length (points) a collapsed run is shortened to.
        var collapsedRun: CGFloat = 18
        /// Horizontal margin (points) ignored when looking for ink, so printed margin rules do not count.
        var ignoredMargin: CGFloat = 12

        init() {}
    }

    static func render(
        _ question: PastPaperQuestion,
        in document: PDFDocument,
        scale: CGFloat = 2,
        segmentGap: CGFloat = 6,
        compression: CompressionOptions? = CompressionOptions()
    ) throws -> PastPaperRenderedQuestion {
        let segments = question.segments
        guard !segments.isEmpty else { throw RenderError(label: question.label) }

        let width = segments.map(\.rect.width).max() ?? 0
        let height = segments.map(\.rect.height).reduce(0, +) + segmentGap * CGFloat(segments.count - 1)
        let pixelWidth = Int((width * scale).rounded(.up))
        let pixelHeight = Int((height * scale).rounded(.up))
        guard pixelWidth > 0, pixelHeight > 0,
              let context = CGContext(
                data: nil,
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            throw RenderError(label: question.label)
        }

        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        context.interpolationQuality = .high
        context.scaleBy(x: scale, y: scale)

        // Bottom-left origin: lay segments out from the top down.
        var cursorTop = height
        for segment in segments {
            guard let page = document.page(at: segment.pageIndex) else { continue }
            let destinationY = cursorTop - segment.rect.height
            context.saveGState()
            context.translateBy(x: 0, y: destinationY)
            context.clip(to: CGRect(x: 0, y: 0, width: segment.rect.width, height: segment.rect.height))
            context.translateBy(x: -segment.rect.minX, y: -segment.rect.minY)
            page.draw(with: .mediaBox, to: context)
            context.restoreGState()
            cursorTop = destinationY - segmentGap
        }

        guard var image = context.makeImage() else {
            throw RenderError(label: question.label)
        }
        if let compression {
            image = compressBlankRuns(in: image, context: context, scale: scale, options: compression) ?? image
        }
        guard let data = pngData(from: image) else {
            throw RenderError(label: question.label)
        }
        return PastPaperRenderedQuestion(
            question: question,
            pngData: data,
            pointSize: CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        )
    }

    /// Shortens long runs of rows that are ink-free or hold only a dotted
    /// answer line, so blank working space does not dominate the crop. Any
    /// other ink (text, axes, boxes, faint diagram lines) keeps its rows.
    static func compressBlankRuns(
        in image: CGImage,
        context: CGContext,
        scale: CGFloat,
        options: CompressionOptions
    ) -> CGImage? {
        guard let base = context.data else { return nil }
        let width = context.width
        let height = context.height
        let bytesPerRow = context.bytesPerRow
        let margin = Int(options.ignoredMargin * scale)
        guard width > margin * 2 + 1 else { return nil }
        let pixels = base.assumingMemoryBound(to: UInt8.self)

        // Context rows are stored top to bottom.
        // A row "has ink" unless it is blank or looks like a dotted answer
        // line: many very short dark runs and nothing longer.
        var rowHasInk = [Bool](repeating: false, count: height)
        let maxDotRun = max(2, Int(2 * scale))
        for row in 0..<height {
            let rowStart = row * bytesPerRow
            var ink = 0
            var runs = 0
            var currentRun = 0
            var longestRun = 0
            for column in margin..<(width - margin) {
                let offset = rowStart + column * 4
                let luminance = (Int(pixels[offset]) * 299 + Int(pixels[offset + 1]) * 587 + Int(pixels[offset + 2]) * 114) / 1000
                if luminance < 200 {
                    ink += 1
                    currentRun += 1
                    longestRun = max(longestRun, currentRun)
                } else if currentRun > 0 {
                    runs += 1
                    currentRun = 0
                }
            }
            if currentRun > 0 { runs += 1 }
            let isBlank = ink <= 1
            let isDotted = runs >= 20 && longestRun <= maxDotRun
            rowHasInk[row] = !(isBlank || isDotted)
        }

        let minimumRun = Int(options.minimumRun * scale)
        let collapsedRun = Int(options.collapsedRun * scale)
        var keptRanges: [Range<Int>] = []
        var row = 0
        var removed = 0
        while row < height {
            if rowHasInk[row] {
                let start = row
                while row < height, rowHasInk[row] { row += 1 }
                keptRanges.append(start..<row)
            } else {
                let start = row
                while row < height, !rowHasInk[row] { row += 1 }
                let length = row - start
                if length >= minimumRun {
                    keptRanges.append(start..<(start + collapsedRun))
                    removed += length - collapsedRun
                } else {
                    keptRanges.append(start..<row)
                }
            }
        }
        guard removed > 0 else { return nil }

        let newHeight = height - removed
        guard let output = CGContext(
            data: nil,
            width: width,
            height: newHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: context.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: context.bitmapInfo.rawValue
        ) else { return nil }
        output.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        output.fill(CGRect(x: 0, y: 0, width: width, height: newHeight))

        // Copy kept bands, converting between top-down row indices and the
        // bottom-left drawing origin.
        var destinationTop = 0
        for range in keptRanges {
            let bandHeight = range.count
            guard let band = image.cropping(to: CGRect(x: 0, y: range.lowerBound, width: width, height: bandHeight)) else { continue }
            let destinationY = newHeight - destinationTop - bandHeight
            output.draw(band, in: CGRect(x: 0, y: destinationY, width: width, height: bandHeight))
            destinationTop += bandHeight
        }
        return output.makeImage()
    }

    private static func pngData(from image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
#endif
