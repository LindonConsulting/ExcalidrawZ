//
//  PastPaperAnalyzer.swift
//  ExcalidrawZ
//
//  Created by Claude on 2026/10/01.
//

import Foundation
import CoreGraphics

#if canImport(PDFKit)
import PDFKit
#endif

/// A region of one PDF page, in PDF points (origin bottom-left, as PDFKit reports bounds).
struct PastPaperSegment: Hashable {
    var pageIndex: Int
    var rect: CGRect
}

/// One exam question, possibly spanning several pages.
struct PastPaperQuestion: Hashable, Identifiable {
    var id: String { label }
    /// Question number, or page number for the page-per-frame fallback.
    var number: Int
    /// Frame name, e.g. "Q1" or "Page 1".
    var label: String
    /// Ordered page regions that make up the question.
    var segments: [PastPaperSegment]
}

struct PastPaperAnalysis: Hashable {
    enum Source: Hashable {
        /// Question anchors were found in the PDF text layer.
        case textLayer
        /// No usable text layer or anchors; every page became one item.
        case pagesFallback
    }

    var questions: [PastPaperQuestion]
    var source: Source
}

#if canImport(PDFKit)
/// Splits an exam paper into questions using PDFKit's text layer.
///
/// Anchors are left-margin lines that begin with the next expected question
/// number ("1.", "2", "12)"). Each question runs from its anchor to the next
/// one; trailing answer lines, "Total for Question" lines, page chrome and the
/// examiner column are excluded so the crop hugs the printed question.
enum PastPaperAnalyzer {
    struct Options {
        /// Padding (points) added around detected content.
        var padding: CGFloat = 10
        /// Fraction of the page height treated as header/footer chrome.
        var chromeFraction: CGFloat = 0.06
        /// Lines starting beyond this fraction of the page width are the examiner column.
        var rightColumnFraction: CGFloat = 0.9
        /// Crops never extend beyond this fraction of the page width.
        var cropRightFraction: CGFloat = 0.91
        /// Runs of answer lines at least this tall (points) are cut out of the crop.
        var minimumCollapsibleGap: CGFloat = 14
        /// Lines starting before this fraction of the width are edge chrome (rotated margin text).
        var leftEdgeFraction: CGFloat = 0.05
        /// Anchors must start before this fraction of the page width.
        var anchorMaxXFraction: CGFloat = 0.2

        init() {}
    }

    static func analyze(_ document: PDFDocument, options: Options = Options()) -> PastPaperAnalysis {
        let pages = (0..<document.pageCount).map { index -> PageLines in
            PageLines(index: index, page: document.page(at: index), options: options)
        }

        let anchors = findAnchors(in: pages, options: options)
        guard anchors.count >= 2 else {
            return PastPaperAnalysis(questions: pagesFallback(document), source: .pagesFallback)
        }

        var questions: [PastPaperQuestion] = []
        for (position, anchor) in anchors.enumerated() {
            let next = position + 1 < anchors.count ? anchors[position + 1] : nil
            let segments = buildSegments(
                from: anchor,
                to: next,
                pages: pages,
                options: options
            )
            guard !segments.isEmpty else { continue }
            questions.append(
                PastPaperQuestion(number: anchor.number, label: "Q\(anchor.number)", segments: segments)
            )
        }

        guard !questions.isEmpty else {
            return PastPaperAnalysis(questions: pagesFallback(document), source: .pagesFallback)
        }
        return PastPaperAnalysis(questions: questions, source: .textLayer)
    }

    // MARK: - Page model

    struct Line {
        enum Kind {
            case content
            case chrome
            case answerLine
            case totalLine
            case endOfPaper
        }

        var text: String
        var rect: CGRect
        var kind: Kind
    }

    struct PageLines {
        var index: Int
        var bounds: CGRect
        /// Sorted top to bottom (descending maxY).
        var lines: [Line]

        init(index: Int, page: PDFPage?, options: Options) {
            self.index = index
            guard let page else {
                bounds = .zero
                lines = []
                return
            }
            let bounds = page.bounds(for: .mediaBox)
            self.bounds = bounds
            guard let selection = page.selection(for: bounds) else {
                lines = []
                return
            }
            lines = selection.selectionsByLine().compactMap { lineSelection -> Line? in
                let text = (lineSelection.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                let rect = lineSelection.bounds(for: page)
                guard rect.width > 0, rect.height > 0 else { return nil }
                return Line(text: text, rect: rect, kind: PastPaperAnalyzer.classify(text: text, rect: rect, bounds: bounds, options: options))
            }
            .sorted { $0.rect.maxY > $1.rect.maxY }
        }

        var contentLines: [Line] { lines.filter { $0.kind == .content } }
        var endsPaper: Bool { lines.contains { $0.kind == .endOfPaper } }
    }

    struct Anchor {
        var number: Int
        var pageIndex: Int
        var rect: CGRect
    }

    // MARK: - Classification

    private static let anchorRegex = try! NSRegularExpression(pattern: #"^(\d{1,2})[.)]?(\s|$)"#)
    private static let answerLineRegex = try! NSRegularExpression(pattern: #"^[\s_.…\-]{5,}$"#)
    private static let totalLineRegex = try! NSRegularExpression(
        pattern: #"^\(?\s*total for question"#, options: .caseInsensitive
    )
    private static let endOfPaperRegex = try! NSRegularExpression(
        pattern: #"^(end of (paper|questions|test|examination)|total for paper)"#, options: .caseInsensitive
    )
    private static let chromeTextRegex = try! NSRegularExpression(
        pattern: #"^(turn over|pmt$|do not write|leave\s*$|blank\s*$|blank page|examiner|only$|\*p\d|question \d+ continued)"#,
        options: .caseInsensitive
    )

    private static let pageNumberRegex = try! NSRegularExpression(pattern: #"^\d{1,3}$"#)

    private static func matches(_ regex: NSRegularExpression, _ text: String) -> Bool {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    static func anchorNumber(in text: String) -> Int? {
        guard let match = anchorRegex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return Int(text[range])
    }

    static func classify(text: String, rect: CGRect, bounds: CGRect, options: Options) -> Line.Kind {
        if matches(endOfPaperRegex, text) { return .endOfPaper }
        let chromeBand = bounds.height * options.chromeFraction
        if rect.minY < bounds.minY + chromeBand || rect.maxY > bounds.maxY - chromeBand {
            return .chrome
        }
        if rect.minX > bounds.minX + bounds.width * options.rightColumnFraction { return .chrome }
        if rect.minX < bounds.minX + bounds.width * options.leftEdgeFraction { return .chrome }
        if matches(chromeTextRegex, text) { return .chrome }
        // Page numbers: a lone small number in the outer bands of the page.
        // The top band is kept narrow so a question number printed on its own
        // line at the top of a page is not mistaken for a page number.
        if rect.width < 24, matches(pageNumberRegex, text),
           rect.minY < bounds.minY + bounds.height * 0.12 || rect.maxY > bounds.maxY - bounds.height * 0.08 {
            return .chrome
        }
        if matches(totalLineRegex, text) { return .totalLine }
        if matches(answerLineRegex, text) { return .answerLine }
        // "£ ........" / "cm ......" style answer boxes: strip the leader and see what remains.
        let stripped = text.filter { !"_.… -".contains($0) }
        if text.count >= 8, stripped.count <= 3 { return .answerLine }
        return .content
    }

    // MARK: - Anchors

    static func findAnchors(in pages: [PageLines], options: Options) -> [Anchor] {
        var candidates: [Anchor] = []
        for page in pages {
            let maxX = page.bounds.minX + page.bounds.width * options.anchorMaxXFraction
            for line in page.lines where line.kind == .content {
                guard line.rect.minX < maxX, line.rect.height < 40,
                      let number = anchorNumber(in: line.text) else { continue }
                candidates.append(Anchor(number: number, pageIndex: page.index, rect: line.rect))
            }
        }

        // Consume candidates in reading order, taking the next expected number.
        // When the expected number is missing, look ahead one number so a single
        // unreadable anchor does not truncate the paper.
        var anchors: [Anchor] = []
        var expected = 1
        var cursor = 0
        while cursor < candidates.count {
            if let hit = candidates[cursor...].firstIndex(where: { $0.number == expected }) {
                anchors.append(candidates[hit])
                cursor = hit + 1
                expected += 1
            } else if candidates[cursor...].contains(where: { $0.number == expected + 1 }) {
                expected += 1
            } else {
                break
            }
        }
        return anchors
    }

    // MARK: - Segments

    static func buildSegments(
        from anchor: Anchor,
        to next: Anchor?,
        pages: [PageLines],
        options: Options
    ) -> [PastPaperSegment] {
        let pad = options.padding
        var segments: [PastPaperSegment] = []
        let lastPageIndex = next?.pageIndex ?? (pages.count - 1)

        for pageIndex in anchor.pageIndex...lastPageIndex {
            let page = pages[pageIndex]
            let topLimit: CGFloat = pageIndex == anchor.pageIndex ? anchor.rect.maxY : page.bounds.maxY
            let bottomLimit: CGFloat = (next != nil && pageIndex == next!.pageIndex) ? next!.rect.maxY : page.bounds.minY

            // Content on this page between the limits.
            let content = page.contentLines.filter {
                $0.rect.maxY <= topLimit + 1 && $0.rect.minY >= bottomLimit - 1
            }
            var includeAnchorLine = pageIndex == anchor.pageIndex
            if pageIndex == anchor.pageIndex && content.isEmpty {
                includeAnchorLine = true
            }
            guard !content.isEmpty || includeAnchorLine else {
                if next == nil && page.endsPaper { break }
                continue
            }

            var minX = CGFloat.greatestFiniteMagnitude
            var maxX = -CGFloat.greatestFiniteMagnitude
            var minY = CGFloat.greatestFiniteMagnitude
            var maxY = -CGFloat.greatestFiniteMagnitude
            for line in content {
                minX = min(minX, line.rect.minX)
                maxX = max(maxX, line.rect.maxX)
                minY = min(minY, line.rect.minY)
                maxY = max(maxY, line.rect.maxY)
            }
            if includeAnchorLine {
                minX = min(minX, anchor.rect.minX)
                maxX = max(maxX, anchor.rect.maxX)
                minY = min(minY, anchor.rect.minY)
                maxY = max(maxY, anchor.rect.maxY)
            }

            let chromeBand = page.bounds.height * options.chromeFraction
            let top = min(maxY + pad, page.bounds.maxY - chromeBand)
            var bottom = max(minY - pad * 2, page.bounds.minY + chromeBand)
            // Never reach into the answer lines / "Total for Question" line below the content.
            if let markerBelow = page.lines
                .filter({ ($0.kind == .answerLine || $0.kind == .totalLine) && $0.rect.maxY <= minY && $0.rect.maxY >= bottomLimit })
                .map(\.rect.maxY).max() {
                bottom = max(bottom, markerBelow + 2)
            }
            let left = max(minX - pad, page.bounds.minX)
            let right = min(maxX + pad, page.bounds.minX + page.bounds.width * options.cropRightFraction)
            if top > bottom, right > left {
                let rect = CGRect(x: left, y: bottom, width: right - left, height: top - bottom)
                for piece in collapseAnswerRuns(in: rect, page: page, options: options) {
                    segments.append(PastPaperSegment(pageIndex: pageIndex, rect: piece))
                }
            }

            // The last question stops at the end-of-paper marker.
            if next == nil && page.endsPaper { break }
        }

        // Use one horizontal extent for the whole question so stacked segments line up.
        guard let unionLeft = segments.map(\.rect.minX).min(),
              let unionRight = segments.map(\.rect.maxX).max() else {
            return segments
        }
        return segments.map {
            var segment = $0
            segment.rect.origin.x = unionLeft
            segment.rect.size.width = unionRight - unionLeft
            return segment
        }
    }

    /// Removes vertical bands occupied by answer lines ("........", "______")
    /// and "Total for Question" lines from `rect`, returning the remaining
    /// pieces top to bottom. Blank space without such markers is kept because
    /// vector diagrams are invisible to the text layer.
    static func collapseAnswerRuns(in rect: CGRect, page: PageLines, options: Options) -> [CGRect] {
        let markers = page.lines
            .filter { ($0.kind == .answerLine || $0.kind == .totalLine) && $0.rect.minY >= rect.minY && $0.rect.maxY <= rect.maxY }
            .map(\.rect)
            .sorted { $0.maxY > $1.maxY }
        guard !markers.isEmpty else { return [rect] }

        // Merge nearby marker rects into bands.
        var bands: [CGRect] = []
        for marker in markers {
            if var last = bands.last, marker.maxY >= last.minY - 12 {
                last = last.union(marker)
                bands[bands.count - 1] = last
            } else {
                bands.append(marker)
            }
        }
        bands = bands.filter { $0.height >= options.minimumCollapsibleGap }
        guard !bands.isEmpty else { return [rect] }

        var pieces: [CGRect] = []
        var top = rect.maxY
        for band in bands {
            let pieceBottom = band.maxY + 2
            if top - pieceBottom > 4 {
                pieces.append(CGRect(x: rect.minX, y: pieceBottom, width: rect.width, height: top - pieceBottom))
            }
            top = band.minY - 2
        }
        if top - rect.minY > 4 {
            pieces.append(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: top - rect.minY))
        }
        return pieces.isEmpty ? [rect] : pieces
    }

    // MARK: - Fallback

    static func pagesFallback(_ document: PDFDocument) -> [PastPaperQuestion] {
        (0..<document.pageCount).compactMap { index in
            guard let page = document.page(at: index) else { return nil }
            let bounds = page.bounds(for: .mediaBox)
            let inset = min(bounds.width, bounds.height) * 0.03
            return PastPaperQuestion(
                number: index + 1,
                label: "Page \(index + 1)",
                segments: [PastPaperSegment(pageIndex: index, rect: bounds.insetBy(dx: inset, dy: inset))]
            )
        }
    }
}
#endif
