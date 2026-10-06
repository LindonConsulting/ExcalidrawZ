import Foundation
import GRDB
import TutorModels

public extension TutorDatabase {
    // MARK: Students

    func students(includeArchived: Bool = false) throws -> [Student] {
        try writer.read { db in
            var request = Student.order(Column("name"))
            if !includeArchived { request = request.filter(Column("archivedAt") == nil) }
            return try request.fetchAll(db)
        }
    }

    func student(named name: String) throws -> Student? {
        let needle = name.trimmingCharacters(in: .whitespaces).lowercased()
        return try writer.read { db in
            try Student.filter(sql: "lower(name) = ?", arguments: [needle]).fetchOne(db)
        }
    }

    func student(id: UUID) throws -> Student? {
        try writer.read { db in try Student.fetchOne(db, key: id) }
    }

    @discardableResult
    func save(_ student: Student) throws -> Student {
        try writer.write { db in try student.save(db) }
        return student
    }

    func deleteStudent(id: UUID) throws {
        _ = try writer.write { db in try Student.deleteOne(db, key: id) }
    }

    // MARK: Topics

    func topics(subject: Subject? = nil) throws -> [Topic] {
        try writer.read { db in
            var request = Topic.order(Column("sortOrder"), Column("name"))
            if let subject { request = request.filter(Column("subject") == subject.rawValue) }
            return try request.fetchAll(db)
        }
    }

    func replaceTopics(_ topics: [Topic]) throws {
        try writer.write { db in
            try Topic.deleteAll(db)
            for topic in topics { try topic.insert(db) }
        }
    }

    func upsertTopics(_ topics: [Topic]) throws {
        try writer.write { db in
            for topic in topics { try topic.save(db) }
        }
    }

    // MARK: Questions

    func questions(includeArchived: Bool = false) throws -> [Question] {
        try writer.read { db in
            var request = Question.order(Column("createdAt").desc)
            if !includeArchived { request = request.filter(Column("archivedAt") == nil) }
            return try request.fetchAll(db)
        }
    }

    func question(id: UUID) throws -> Question? {
        try writer.read { db in try Question.fetchOne(db, key: id) }
    }

    /// Saves the record and its payload together.
    func add(_ question: Question, payload: QuestionPayload) throws {
        try media.save(payload, for: question.id)
        try writer.write { db in try question.insert(db) }
    }

    func update(_ question: Question) throws {
        try writer.write { db in try question.update(db) }
    }

    func deleteQuestion(id: UUID) throws {
        _ = try writer.write { db in try Question.deleteOne(db, key: id) }
        media.delete(for: id)
    }

    func questions(withImageHashNear hash: String, threshold: Int, excluding id: UUID? = nil) throws -> [Question] {
        try questions(includeArchived: true).filter { question in
            guard question.id != id, let other = question.imageHash else { return false }
            return ImageHashDistance.hamming(hash, other) <= threshold
        }
    }

    // MARK: Outcomes

    func outcomes(forQuestion id: UUID) throws -> [Outcome] {
        try writer.read { db in
            try Outcome.filter(Column("questionID") == id).order(Column("shownAt").desc).fetchAll(db)
        }
    }

    func outcomes(forStudent id: UUID) throws -> [Outcome] {
        try writer.read { db in
            try Outcome.filter(Column("studentID") == id).order(Column("shownAt").desc).fetchAll(db)
        }
    }

    /// All outcomes keyed by question id, for list screens.
    func outcomesByQuestion() throws -> [UUID: [Outcome]] {
        let all = try writer.read { db in try Outcome.order(Column("shownAt").desc).fetchAll(db) }
        return Dictionary(grouping: all, by: \.questionID)
    }

    @discardableResult
    func record(_ outcome: Outcome) throws -> Outcome {
        try writer.write { db in try outcome.save(db) }
        return outcome
    }

    func deleteOutcome(id: UUID) throws {
        _ = try writer.write { db in try Outcome.deleteOne(db, key: id) }
    }

    // MARK: Lesson sessions

    @discardableResult
    func record(_ session: LessonSession) throws -> LessonSession {
        try writer.write { db in try session.save(db) }
        return session
    }

    func lessonSession(forFile fileID: String) throws -> LessonSession? {
        try writer.read { db in try LessonSession.filter(Column("lessonFileID") == fileID).fetchOne(db) }
    }

    func lessonSessions(forStudent id: UUID) throws -> [LessonSession] {
        try writer.read { db in
            try LessonSession.filter(Column("studentID") == id).order(Column("date").desc).fetchAll(db)
        }
    }
}

public enum ImageHashDistance {
    public static let duplicateThreshold = 10

    public static func hamming(_ a: String, _ b: String) -> Int {
        guard let x = UInt64(a, radix: 16), let y = UInt64(b, radix: 16) else { return Int.max }
        return (x ^ y).nonzeroBitCount
    }
}
