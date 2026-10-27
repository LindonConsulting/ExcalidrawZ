import Foundation
import TutorModels

/// Prompt text for the lesson recap, kept here so it is easy to tune.
public enum TutorPrompts {
    // MARK: Lesson recap

    public static let recapSystem = """
    You write a short recap of a tutoring lesson for the tutor to glance at when the next lesson starts. \
    You are given the text written on the previous lesson's whiteboard plus rough counts of drawn shapes. \
    Reply with plain text only, no markdown, at most 8 short lines, in exactly this shape:

    Last time: <one or two lines on what was covered>
    To revisit: <two to four bullet-like lines, each starting with "- ", on things worth checking or continuing>

    If the whiteboard text is too thin to tell, say so briefly in the "Last time" line and suggest one general check-in under "To revisit". Do not invent topics that are not supported by the text.
    """

    public struct RecapInput: Sendable {
        public var student: String
        public var subject: String?
        public var previousLessonDate: Date
        public var texts: [String]
        public var elementCounts: [String: Int]

        public init(student: String, subject: String?, previousLessonDate: Date, texts: [String], elementCounts: [String: Int]) {
            self.student = student; self.subject = subject; self.previousLessonDate = previousLessonDate
            self.texts = texts; self.elementCounts = elementCounts
        }
    }

    public static func recapUser(_ input: RecapInput) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        var lines = ["Student: \(input.student)"]
        if let subject = input.subject { lines.append("Subject: \(subject)") }
        lines.append("Previous lesson: \(formatter.string(from: input.previousLessonDate))")
        let counts = input.elementCounts.sorted { $0.key < $1.key }.map { "\($0.key)×\($0.value)" }.joined(separator: ", ")
        lines.append("Canvas elements: \(counts.isEmpty ? "none" : counts)")
        lines.append("")
        lines.append("Whiteboard text (reading order):")
        lines += input.texts.isEmpty ? ["(no text on the canvas)"] : input.texts.map { "- " + $0.replacingOccurrences(of: "\n", with: " / ") }
        return lines.joined(separator: "\n")
    }
}
