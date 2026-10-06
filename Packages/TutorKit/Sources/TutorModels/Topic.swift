import Foundation

/// A node in the topic taxonomy: strand › topic › sub-topic. `parentID == nil` is a strand.
public struct Topic: Codable, Hashable, Identifiable, Sendable {
    public var id: String                 // stable slug, e.g. "maths.algebra.quadratics"
    public var parentID: String?
    public var subject: Subject
    public var level: QualificationLevel?  // nil = applies to all levels of the subject
    public var name: String
    public var aliases: [String]
    public var sortOrder: Int

    public init(id: String, parentID: String? = nil, subject: Subject, level: QualificationLevel? = nil,
                name: String, aliases: [String] = [], sortOrder: Int = 0) {
        self.id = id; self.parentID = parentID; self.subject = subject; self.level = level
        self.name = name; self.aliases = aliases; self.sortOrder = sortOrder
    }

    public func matches(_ text: String) -> Bool {
        let needle = text.trimmingCharacters(in: .whitespaces).lowercased()
        return name.lowercased() == needle || aliases.contains { $0.lowercased() == needle } || id == needle
    }
}
