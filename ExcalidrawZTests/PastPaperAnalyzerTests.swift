//
//  PastPaperAnalyzerTests.swift
//  ExcalidrawZTests
//
//  Created by Claude on 2026/10/01.
//

import XCTest
import PDFKit
@testable import ExcalidrawZ

/// Exercises the past-paper splitter against a synthetic paper, plus the
/// local exam-paper library when it exists on the machine running the tests.
final class PastPaperAnalyzerTests: XCTestCase {

    func testSyntheticPaperSplitsIntoNumberedQuestions() throws {
        let document = try makeSyntheticPaper(questionsPerPage: [3, 2])
        let analysis = PastPaperAnalyzer.analyze(document)

        XCTAssertEqual(analysis.source, .textLayer)
        XCTAssertEqual(analysis.questions.map(\.label), ["Q1", "Q2", "Q3", "Q4", "Q5"])
        XCTAssertEqual(analysis.questions.map { $0.segments.first?.pageIndex }, [0, 0, 0, 1, 1])
        for question in analysis.questions {
            XCTAssertEqual(question.segments.count, 1, question.label)
            XCTAssertGreaterThan(question.segments[0].rect.height, 10, question.label)
        }
    }

    func testPaperWithoutTextLayerFallsBackToPages() throws {
        let document = try makeImageOnlyPaper(pageCount: 2)
        let analysis = PastPaperAnalyzer.analyze(document)

        XCTAssertEqual(analysis.source, .pagesFallback)
        XCTAssertEqual(analysis.questions.map(\.label), ["Page 1", "Page 2"])
    }

    func testRendererProducesPNGOfExpectedAspect() throws {
        let document = try makeSyntheticPaper(questionsPerPage: [2])
        let analysis = PastPaperAnalyzer.analyze(document)
        let question = try XCTUnwrap(analysis.questions.first)

        let rendered = try PastPaperRenderer.render(question, in: document, scale: 2, compression: nil)
        XCTAssertGreaterThan(rendered.pngData.count, 100)
        XCTAssertEqual(rendered.pointSize.width, question.segments[0].rect.width, accuracy: 1)
        XCTAssertEqual(rendered.pointSize.height, question.segments[0].rect.height, accuracy: 1)
        XCTAssertEqual(Array(rendered.pngData.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
    }

    /// Real WJEC / Edexcel papers from the local library; skipped elsewhere.
    func testLocalLibraryPapersDetectEveryQuestion() throws {
        let library = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("platform/papers")
        let samples: [(String, Int)] = [
            ("wjec_gcse/Unit-1H/June 2024 QP.pdf", 18),
            ("wjec_alevel/Unit-3/QP/June 2024 QP - Unit 3 WJEC Maths A-level.pdf", 15),
            ("edexcel_alevel/Paper-1/QP/June 2024 QP.pdf", 15),
            ("edexcel_gcse/Paper-2H/QP/June 2024 QP.pdf", 22),
            ("edexcel_gcse/Paper-2H/QP/Nov 2024 QP.pdf", 22),
        ]
        for (path, expectedCount) in samples {
            let url = library.appendingPathComponent(path)
            guard let document = PDFDocument(url: url) else {
                throw XCTSkip("Sample paper not available: \(path)")
            }
            let analysis = PastPaperAnalyzer.analyze(document)
            XCTAssertEqual(analysis.source, .textLayer, path)
            XCTAssertEqual(analysis.questions.count, expectedCount, path)
            XCTAssertEqual(analysis.questions.map(\.number), Array(1...expectedCount), path)
        }
    }

    // MARK: - Fixtures

    private func makeSyntheticPaper(questionsPerPage: [Int]) throws -> PDFDocument {
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data),
              var mediaBox = Optional(pageRect),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw XCTSkip("Could not create PDF context")
        }
        var number = 1
        for count in questionsPerPage {
            context.beginPDFPage(nil)
            var y = pageRect.height - 80
            for _ in 0..<count {
                draw("\(number). Work out the value of x when 3x + 2 = 11.", at: CGPoint(x: 57, y: y), in: context)
                draw("Give your answer as a decimal. [2]", at: CGPoint(x: 80, y: y - 20), in: context)
                y -= 220
                number += 1
            }
            draw("\(questionsPerPage.count)", at: CGPoint(x: 295, y: 30), in: context)
            context.endPDFPage()
        }
        context.closePDF()
        return try XCTUnwrap(PDFDocument(data: data as Data))
    }

    private func makeImageOnlyPaper(pageCount: Int) throws -> PDFDocument {
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data),
              var mediaBox = Optional(pageRect),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw XCTSkip("Could not create PDF context")
        }
        for _ in 0..<pageCount {
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(CGRect(x: 60, y: 600, width: 200, height: 4))
            context.endPDFPage()
        }
        context.closePDF()
        return try XCTUnwrap(PDFDocument(data: data as Data))
    }

    private func draw(_ text: String, at point: CGPoint, in context: CGContext) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        context.textPosition = point
        CTLineDraw(line, context)
    }
}
