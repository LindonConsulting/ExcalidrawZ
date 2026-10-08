import Foundation

/// Who the student is. What they study lives in `Enrolment`; parents in
/// `StudentContact`; weak topics in `TopicProgress`.
public struct Student: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    /// Display name; also the ExcalidrawZ group name used by Lesson Draw.
    public var name: String
    public var yearGroup: String
    public var school: String
    /// "private", "mytutor", …
    public var management: String
    public var notes: String
    public var rapportNotes: String
    public var hobbies: String
    public var interests: String
    /// EventKit calendar identifier or attendee match, when known.
    public var calendarIdentifier: String?
    /// Remote `students.id`, once matched.
    public var remoteID: UUID?
    public var remoteSyncedAt: Date?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID = UUID(), name: String, yearGroup: String = "", school: String = "", management: String = "",
                notes: String = "", rapportNotes: String = "", hobbies: String = "", interests: String = "",
                calendarIdentifier: String? = nil, remoteID: UUID? = nil, remoteSyncedAt: Date? = nil,
                createdAt: Date = .now, updatedAt: Date = .now, deletedAt: Date? = nil) {
        self.id = id; self.name = name; self.yearGroup = yearGroup; self.school = school; self.management = management
        self.notes = notes; self.rapportNotes = rapportNotes; self.hobbies = hobbies; self.interests = interests
        self.calendarIdentifier = calendarIdentifier; self.remoteID = remoteID; self.remoteSyncedAt = remoteSyncedAt
        self.createdAt = createdAt; self.updatedAt = updatedAt; self.deletedAt = deletedAt
    }
}

/// A parent or guardian.
public struct StudentContact: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var studentID: UUID
    public var name: String
    public var relationship: String
    public var phone: String
    public var email: String
    public var preferredMethod: String
    public var isPrimary: Bool

    public init(id: UUID = UUID(), studentID: UUID, name: String = "", relationship: String = "", phone: String = "",
                email: String = "", preferredMethod: String = "", isPrimary: Bool = false) {
        self.id = id; self.studentID = studentID; self.name = name; self.relationship = relationship
        self.phone = phone; self.email = email; self.preferredMethod = preferredMethod; self.isPrimary = isPrimary
    }

    /// "Name · phone · email", skipping blanks.
    public var summary: String {
        [name, phone, email].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
