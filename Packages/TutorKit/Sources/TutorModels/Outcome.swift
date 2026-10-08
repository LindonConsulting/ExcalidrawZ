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
    /// The lesson it was shown in, when it came from a lesson file.
    public var lessonID: UUID?
    public var shownAt: Date
    public var result: OutcomeResult
    public var marksAwarded: Int?
    /// How hard it felt for this student, 1–5, if recorded.
    public var perceivedDifficulty: Int?
    public var timeSeconds: Int?
    public var note: String
    public var remoteID: UUID?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID = UUID(), questionID: UUID, studentID: UUID? = nil, lessonID: UUID? = nil,
                shownAt: Date = .now, result: OutcomeResult = .unknown, marksAwarded: Int? = nil,
                perceivedDifficulty: Int? = nil, timeSeconds: Int? = nil, note: String = "", remoteID: UUID? = nil,
                createdAt: Date = .now, updatedAt: Date = .now, deletedAt: Date? = nil) {
        self.id = id; self.questionID = questionID; self.studentID = studentID; self.lessonID = lessonID
        self.shownAt = shownAt; self.result = result; self.marksAwarded = marksAwarded
        self.perceivedDifficulty = perceivedDifficulty; self.timeSeconds = timeSeconds; self.note = note
        self.remoteID = remoteID; self.createdAt = createdAt; self.updatedAt = updatedAt; self.deletedAt = deletedAt
    }
}

public enum LessonStatus: String, Codable, CaseIterable, Sendable {
    case planned, done, cancelled
    case noShow = "no-show"
}

/// A lesson (replaces LessonSession): optionally tied to a Lesson Draw file,
/// a calendar event and the enrolment it was for.
public struct Lesson: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var studentID: UUID
    public var enrolmentID: UUID?
    /// ExcalidrawZ file id (Core Data `File.id`), when the lesson has a board.
    public var fileID: String?
    public var calendarEventID: String?
    public var startAt: Date
    public var endAt: Date?
    public var durationMinutes: Int?
    public var status: LessonStatus
    public var subjectLine: String
    public var plan: String
    /// AI or tutor summary of what happened.
    public var recap: String?
    /// Structured recap payload (topics, homework) when generated.
    public var recapJSON: String?
    public var homeworkSet: String
    public var nextPlan: String
    public var transcriptPath: String?
    public var billable: Bool
    public var remoteID: UUID?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID = UUID(), studentID: UUID, enrolmentID: UUID? = nil, fileID: String? = nil, calendarEventID: String? = nil,
                startAt: Date = .now, endAt: Date? = nil, durationMinutes: Int? = nil, status: LessonStatus = .done,
                subjectLine: String = "", plan: String = "", recap: String? = nil, recapJSON: String? = nil,
                homeworkSet: String = "", nextPlan: String = "", transcriptPath: String? = nil, billable: Bool = true,
                remoteID: UUID? = nil, createdAt: Date = .now, updatedAt: Date = .now, deletedAt: Date? = nil) {
        self.id = id; self.studentID = studentID; self.enrolmentID = enrolmentID; self.fileID = fileID
        self.calendarEventID = calendarEventID; self.startAt = startAt; self.endAt = endAt; self.durationMinutes = durationMinutes
        self.status = status; self.subjectLine = subjectLine; self.plan = plan; self.recap = recap; self.recapJSON = recapJSON
        self.homeworkSet = homeworkSet; self.nextPlan = nextPlan; self.transcriptPath = transcriptPath; self.billable = billable
        self.remoteID = remoteID; self.createdAt = createdAt; self.updatedAt = updatedAt; self.deletedAt = deletedAt
    }
}

/// A topic taught in a lesson.
public struct LessonTopic: Codable, Hashable, Sendable {
    public var lessonID: UUID
    public var topicID: String
    public var minutes: Int?
    public var note: String

    public init(lessonID: UUID, topicID: String, minutes: Int? = nil, note: String = "") {
        self.lessonID = lessonID; self.topicID = topicID; self.minutes = minutes; self.note = note
    }
}
