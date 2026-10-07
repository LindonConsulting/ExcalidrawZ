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
    /// ConwyMaths Supabase `students.id`, once matched.
    public var remoteID: UUID?
    public var yearGroup: String
    /// "private", "mytutor", …
    public var management: String
    public var parentName: String
    public var parentContact: String
    public var rapportNotes: String
    public var remoteSyncedAt: Date?
    public var createdAt: Date
    public var archivedAt: Date?

    public init(id: UUID = UUID(), name: String, subject: Subject = .maths, level: QualificationLevel = .gcse,
                board: ExamBoard? = nil, tier: Tier? = nil, targetGrade: String = "", notes: String = "",
                focusTopicIDs: [String] = [], specificationID: UUID? = nil, remoteID: UUID? = nil, yearGroup: String = "",
                management: String = "", parentName: String = "", parentContact: String = "", rapportNotes: String = "",
                remoteSyncedAt: Date? = nil, createdAt: Date = .now, archivedAt: Date? = nil) {
        self.id = id; self.name = name; self.subject = subject; self.level = level; self.board = board
        self.tier = tier; self.targetGrade = targetGrade; self.notes = notes; self.focusTopicIDs = focusTopicIDs
        self.specificationID = specificationID
        self.remoteID = remoteID; self.yearGroup = yearGroup; self.management = management
        self.parentName = parentName; self.parentContact = parentContact; self.rapportNotes = rapportNotes
        self.remoteSyncedAt = remoteSyncedAt
        self.createdAt = createdAt; self.archivedAt = archivedAt
    }
}
