import Foundation

/// One thing a student is studying with you: subject + level (+ board/tier),
/// optionally mapped to a remote course.
public struct Enrolment: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var studentID: UUID
    /// Remote `courses.id` such as "gcse_maths", when mapped.
    public var courseID: String?
    public var subject: Subject
    public var level: QualificationLevel
    public var board: ExamBoard?
    public var tier: Tier?
    public var targetGrade: String
    public var startedAt: Date?
    public var endedAt: Date?
    /// The enrolment Lesson Draw assumes when nothing narrows it down.
    public var isPrimary: Bool
    public var notes: String
    public var remoteID: UUID?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID = UUID(), studentID: UUID, courseID: String? = nil,
                subject: Subject = .maths, level: QualificationLevel = .gcse, board: ExamBoard? = nil, tier: Tier? = nil,
                targetGrade: String = "", startedAt: Date? = nil, endedAt: Date? = nil, isPrimary: Bool = false,
                notes: String = "", remoteID: UUID? = nil, createdAt: Date = .now, updatedAt: Date = .now, deletedAt: Date? = nil) {
        self.id = id; self.studentID = studentID; self.courseID = courseID
        self.subject = subject; self.level = level; self.board = board; self.tier = tier; self.targetGrade = targetGrade
        self.startedAt = startedAt; self.endedAt = endedAt; self.isPrimary = isPrimary; self.notes = notes
        self.remoteID = remoteID; self.createdAt = createdAt; self.updatedAt = updatedAt; self.deletedAt = deletedAt
    }

    public var isActive: Bool { deletedAt == nil && endedAt == nil }

    /// "Edexcel GCSE Maths (Higher)"
    public var courseName: String {
        var parts: [String] = []
        if let board { parts.append(board.rawValue) }
        parts.append(level.rawValue)
        parts.append(subject.rawValue)
        var name = parts.joined(separator: " ")
        if let tier, tier != .notApplicable { name += " (\(tier.rawValue))" }
        return name
    }
}

/// Reference row mirroring the remote `courses` table.
public struct Course: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var subject: Subject
    public var level: QualificationLevel
    public var displayName: String
    public var active: Bool

    public init(id: String, subject: Subject, level: QualificationLevel, displayName: String, active: Bool = true) {
        self.id = id; self.subject = subject; self.level = level; self.displayName = displayName; self.active = active
    }
}

/// Tutor's current judgement of a student on a taxonomy topic.
public struct TopicProgress: Codable, Hashable, Sendable {
    public var studentID: UUID
    public var topicID: String
    /// 1–5, when recorded.
    public var understanding: Int?
    /// Flagged as a weak topic to prioritise.
    public var isFocus: Bool
    public var startedAt: Date?
    public var lastRevisedAt: Date?
    public var notes: String
    public var remoteID: UUID?
    public var updatedAt: Date

    public init(studentID: UUID, topicID: String, understanding: Int? = nil, isFocus: Bool = false, startedAt: Date? = nil,
                lastRevisedAt: Date? = nil, notes: String = "", remoteID: UUID? = nil, updatedAt: Date = .now) {
        self.studentID = studentID; self.topicID = topicID; self.understanding = understanding; self.isFocus = isFocus
        self.startedAt = startedAt; self.lastRevisedAt = lastRevisedAt; self.notes = notes; self.remoteID = remoteID
        self.updatedAt = updatedAt
    }
}
