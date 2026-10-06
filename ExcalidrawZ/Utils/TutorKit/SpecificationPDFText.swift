//
//  SpecificationPDFText.swift
//  ExcalidrawZ
//
//  Extracts page text from a specification PDF for the TutorAI importer.
//

import Foundation
import PDFKit

enum SpecificationPDFText {
    enum ExtractError: LocalizedError {
        case unreadable, noText
        var errorDescription: String? {
            switch self {
                case .unreadable: return "The PDF could not be opened."
                case .noText: return "The PDF has no extractable text (it may be a scan). Try a text-based copy of the specification."
            }
        }
    }

    static func pages(from url: URL) throws -> [String] {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard let document = PDFDocument(url: url) else { throw ExtractError.unreadable }
        var pages: [String] = []
        for index in 0..<document.pageCount {
            pages.append(document.page(at: index)?.string ?? "")
        }
        guard pages.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).count > 50 }) else { throw ExtractError.noText }
        return pages
    }
}
