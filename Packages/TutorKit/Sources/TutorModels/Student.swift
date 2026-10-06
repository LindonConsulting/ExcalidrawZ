import Foundation

public struct Student: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    /// Display name; also the ExcalidrawZ group name used by Lesson Draw.
    public var name: String
    public var subject: Subject
    public var level: QualificationLevel
    public var board: ExamBoard?
    public var tier: Tier?
    public var targetGrade: String
    public var notes: String
    /// Topic ids the tutor has flagged as weak.
    public var focusTopicIDs: [String]
    /// Specification this student is being taught to (Phase 3).
    public var specificationID: UUID?
    public var createdAt: Date
    public var archivedAt: Date?

    public init(id: UUID = UUID(), name: String, subject: Subject = .maths, level: QualificationLevel = .gcse,
                board: ExamBoard? = nil, tier: Tier? = nil, targetGrade: String = "", notes: String = "",
                focusTopicIDs: [String] = [], specificationID: UUID? = nil, createdAt: Date = .now, archivedAt: Date? = nil) {
        self.id = id; self.name = name; self.subject = subject; self.level = level; self.board = board
        self.tier = tier; self.targetGrade = targetGrade; self.notes = notes; self.focusTopicIDs = focusTopicIDs
        self.specificationID = specificationID
        self.createdAt = createdAt; self.archivedAt = archivedAt
    }
}
