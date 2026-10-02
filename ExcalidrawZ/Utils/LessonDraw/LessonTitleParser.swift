//
//  LessonTitleParser.swift
//  ExcalidrawZ
//
//  Extracts the student (and optional subject) from a calendar event title
//  using a user-configurable regular expression.
//

import Foundation

struct LessonTitleMatch: Equatable, Sendable {
    /// Student name with any trailing parenthetical removed (`Frankie`).
    var student: String
    /// The full first capture group (`Frankie (CMT)`), kept for display.
    var studentPrefix: String
    /// Second capture group when the pattern has one (`Maths GCSE`).
    var subject: String?
}

struct LessonTitleParser {
    enum ParseError: LocalizedError {
        case invalidPattern(String)

        var errorDescription: String? {
            switch self {
                case .invalidPattern(let message):
                    return "The lesson title pattern is not a valid regular expression: \(message)"
            }
        }
    }

    let pattern: String

    init(pattern: String) {
        self.pattern = pattern
    }

    func parse(_ title: String) throws -> LessonTitleMatch? {
        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: pattern, options: [])
        } catch {
            throw ParseError.invalidPattern(error.localizedDescription)
        }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard let match = regex.firstMatch(in: trimmed, options: [], range: range),
              match.numberOfRanges >= 2,
              let prefixRange = Range(match.range(at: 1), in: trimmed)
        else { return nil }

        let prefix = trimmed[prefixRange].trimmingCharacters(in: .whitespaces)
        guard !prefix.isEmpty else { return nil }

        var subject: String?
        if match.numberOfRanges >= 3, let subjectRange = Range(match.range(at: 2), in: trimmed) {
            let value = trimmed[subjectRange].trimmingCharacters(in: .whitespaces)
            subject = value.isEmpty ? nil : value
        }
        return LessonTitleMatch(
            student: Self.strippingTrailingParenthetical(prefix),
            studentPrefix: prefix,
            subject: subject
        )
    }

    static func strippingTrailingParenthetical(_ value: String) -> String {
        guard value.hasSuffix(")"), let open = value.lastIndex(of: "(") else { return value }
        let stripped = value[..<open].trimmingCharacters(in: .whitespaces)
        return stripped.isEmpty ? value : stripped
    }
}
