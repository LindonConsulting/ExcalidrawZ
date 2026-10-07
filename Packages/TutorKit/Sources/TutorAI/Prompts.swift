import Foundation
import TutorModels

/// Prompt text for the two current AI jobs, kept together so they are easy to tune.
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

    // MARK: Question tagging

    public struct TagSuggestion: Decodable, Sendable {
        public var title: String?
        public var topics: [String]?
        public var subject: String?
        public var level: String?
        public var board: String?
        public var tier: String?
        public var marks: Int?
        public var difficulty: Int?
        public var source: String?
        /// Spec point codes from the supplied specification, when one was given.
        public var specPoints: [String]?
    }

    /// Stable, cacheable context for tagging: the topic list and the specification points.
    public static func taggingContext(topics: [Topic], specPoints: [(code: String, text: String)]) -> String {
        var text = "Topic ids available (id (name)):\n" + topics.filter { $0.parentID != nil }.map { "\($0.id) (\($0.name))" }.joined(separator: "; ")
        if !specPoints.isEmpty {
            text += "\n\nSpecification points (code: statement):\n" + specPoints.map { "\($0.code): \($0.text)" }.joined(separator: "\n")
        }
        return text
    }

    /// Per-question prompt; expects `taggingContext` to be sent as a cached system block.
    public static func taggingUser(texts: [String], hasSpecPoints: Bool) -> String {
        var prompt = "Classify this tutoring question (GCSE or A-Level Maths or Computer Science) for a question bank, using the topic ids and specification points given in the system context."
        if !texts.isEmpty {
            prompt += "\n\nText on the canvas:\n" + texts.map { "- \($0)" }.joined(separator: "\n")
        }
        prompt += """


        Reply with JSON only, no prose, with these keys:
        {"title": short descriptive title (max 60 chars),
         "topics": 1-3 topic ids from the list,
         "subject": "Maths" or "Computer Science",
         "level": one of \(QualificationLevel.allCases.map(\.rawValue).joined(separator: ", ")) or "" if unknown,
         "board": one of \(ExamBoard.allCases.map(\.rawValue).joined(separator: ", ")) or "" if unknown,
         "tier": "Foundation", "Higher" or "" if unknown or not GCSE,
         "marks": integer total marks if printed on the question, else null,
         "difficulty": integer 1 (easy) to 5 (hard),
         "source": paper/year/question reference if visible, else "",
         "specPoints": \(hasSpecPoints ? "1-4 matching codes from the specification list" : "[]")}
        """
        return prompt
    }

    /// Legacy single-prompt form (no caching). Kept for callers that pass everything in one user turn.
    public static func taggingUser(texts: [String], topics: [Topic], specPoints: [(code: String, text: String)] = []) -> String {
        var prompt = "Classify this tutoring question (GCSE or A-Level Maths or Computer Science) for a question bank."
        if !texts.isEmpty {
            prompt += "\n\nText on the canvas:\n" + texts.map { "- \($0)" }.joined(separator: "\n")
        }
        let topicList = topics.filter { $0.parentID != nil }.map { "\($0.id) (\($0.name))" }.joined(separator: "; ")
        prompt += """


        Reply with JSON only, no prose, with these keys:
        {"title": short descriptive title (max 60 chars),
         "topics": 1-3 topic ids chosen from this list: \(topicList),
         "subject": "Maths" or "Computer Science",
         "level": one of \(QualificationLevel.allCases.map(\.rawValue).joined(separator: ", ")) or "" if unknown,
         "board": one of \(ExamBoard.allCases.map(\.rawValue).joined(separator: ", ")) or "" if unknown,
         "tier": "Foundation", "Higher" or "" if unknown or not GCSE,
         "marks": integer total marks if printed on the question, else null,
         "difficulty": integer 1 (easy) to 5 (hard),
         "source": paper/year/question reference if visible, else "",
         "specPoints": \(specPoints.isEmpty ? "[]" : "1-4 matching codes from the specification list below")}
        """
        if !specPoints.isEmpty {
            prompt += "\n\nSpecification points (code: statement):\n" + specPoints.map { "\($0.code): \($0.text)" }.joined(separator: "\n")
        }
        return prompt
    }
}
