import Foundation

/// A reusable question. Canvas payload (elements/files/thumbnail) lives in the media store, keyed by `id`.
/// `topicIDs` is stored in the `questionTopic` join table; the store keeps it in step.
public struct Question: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var source: String
    public var subject: Subject
    public var level: QualificationLevel?
    public var board: ExamBoard?
    public var tier: Tier?
    public var marks: Int?
    /// Tutor's or AI's 1–5 difficulty estimate.
    public var difficulty: Int?
    public var notes: String
    public var answer: String
    public var workedSolution: String
    /// Taxonomy topic ids. Free-text tags that didn't match the taxonomy go in `freeTags`.
    public var topicIDs: [String]
    public var freeTags: [String]
    public var imageHash: String?
    public var remoteID: UUID?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID = UUID(), title: String, source: String = "", subject: Subject = .maths,
                level: QualificationLevel? = nil, board: ExamBoard? = nil, tier: Tier? = nil, marks: Int? = nil,
                difficulty: Int? = nil, notes: String = "", answer: String = "", workedSolution: String = "",
                topicIDs: [String] = [], freeTags: [String] = [], imageHash: String? = nil, remoteID: UUID? = nil,
                createdAt: Date = .now, updatedAt: Date = .now, deletedAt: Date? = nil) {
        self.id = id; self.title = title; self.source = source; self.subject = subject; self.level = level
        self.board = board; self.tier = tier; self.marks = marks; self.difficulty = difficulty; self.notes = notes
        self.answer = answer; self.workedSolution = workedSolution
        self.topicIDs = topicIDs; self.freeTags = freeTags; self.imageHash = imageHash; self.remoteID = remoteID
        self.createdAt = createdAt; self.updatedAt = updatedAt; self.deletedAt = deletedAt
    }

    public func matches(query: String, topicNames: [String: String] = [:]) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return true }
        let names = topicIDs.map { topicNames[$0] ?? $0 }
        let haystack = ([title, source, notes, board?.rawValue ?? "", tier?.rawValue ?? ""] + names + freeTags)
            .joined(separator: " ").lowercased()
        return q.split(separator: " ").allSatisfy { haystack.contains($0) }
    }
}
