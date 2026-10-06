import Foundation

public enum OutcomeResult: String, Codable, CaseIterable, Sendable, Identifiable {
    case unknown, right, partial, wrong, skipped
    public var id: String { rawValue }

    public var title: String {
        switch self {
            case .unknown: return "Not recorded"
            case .right: return "Right"
            case .partial: return "Partly"
            case .wrong: return "Wrong"
            case .skipped: return "Skipped"
        }
    }
}

/// One showing of a question to a student, and how it went.
public struct Outcome: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var questionID: UUID
    public var studentID: UUID?
    /// Kept for legacy rows that predate student records.
    public var studentName: String
    public var lessonFileID: String?
    public var shownAt: Date
    public var result: OutcomeResult
    /// How hard it felt for this student, 1–5, if recorded.
    public var perceivedDifficulty: Int?
    public var note: String

    public init(id: UUID = UUID(), questionID: UUID, studentID: UUID? = nil, studentName: String,
                lessonFileID: String? = nil, shownAt: Date = .now, result: OutcomeResult = .unknown,
                perceivedDifficulty: Int? = nil, note: String = "") {
        self.id = id; self.questionID = questionID; self.studentID = studentID; self.studentName = studentName
        self.lessonFileID = lessonFileID; self.shownAt = shownAt; self.result = result
        self.perceivedDifficulty = perceivedDifficulty; self.note = note
    }
}

/// A lesson file created by Lesson Draw, linked to a student.
public struct LessonSession: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var studentID: UUID
    public var lessonFileID: String
    public var date: Date
    public var subjectLine: String
    public var recap: String?

    public init(id: UUID = UUID(), studentID: UUID, lessonFileID: String, date: Date = .now, subjectLine: String = "", recap: String? = nil) {
        self.id = id; self.studentID = studentID; self.lessonFileID = lessonFileID; self.date = date; self.subjectLine = subjectLine; self.recap = recap
    }
}
