import Foundation
import GRDB
import TutorModels

public extension TutorDatabase {
    // MARK: Students

    func students(includeDeleted: Bool = false) throws -> [Student] {
        try writer.read { db in
            var request = Student.order(Column("name"))
            if !includeDeleted { request = request.filter(Column("deletedAt") == nil) }
            return try request.fetchAll(db)
        }
    }

    /// Case-insensitive name match among non-deleted students.
    func student(named name: String) throws -> Student? {
        let needle = name.trimmingCharacters(in: .whitespaces).lowercased()
        return try writer.read { db in
            try Student.filter(sql: "lower(name) = ? AND deletedAt IS NULL", arguments: [needle]).fetchOne(db)
        }
    }

    func student(id: UUID) throws -> Student? {
        try writer.read { db in try Student.fetchOne(db, key: id) }
    }

    @discardableResult
    func save(_ student: Student) throws -> Student {
        var student = student
        student.updatedAt = .now
        try writer.write { db in try student.save(db) }
        return student
    }

    /// Hard delete; enrolments, lessons, progress and contacts cascade, outcomes keep the question.
    func deleteStudent(id: UUID) throws {
        _ = try writer.write { db in try Student.deleteOne(db, key: id) }
    }

    // MARK: Enrolments

    func enrolments(forStudent id: UUID, includeDeleted: Bool = false) throws -> [Enrolment] {
        try writer.read { db in
            var request = Enrolment.filter(Column("studentID") == id).order(Column("isPrimary").desc, Column("createdAt"))
            if !includeDeleted { request = request.filter(Column("deletedAt") == nil) }
            return try request.fetchAll(db)
        }
    }

    /// Every live enrolment, keyed by student id (primary first).
    func enrolmentsByStudent() throws -> [UUID: [Enrolment]] {
        let all = try writer.read { db in
            try Enrolment.filter(Column("deletedAt") == nil).order(Column("isPrimary").desc, Column("createdAt")).fetchAll(db)
        }
        return Dictionary(grouping: all, by: \.studentID)
    }

    func enrolment(id: UUID) throws -> Enrolment? {
        try writer.read { db in try Enrolment.fetchOne(db, key: id) }
    }

    /// Saves the enrolment. When `isPrimary` is set, every other enrolment of the student is demoted.
    @discardableResult
    func save(_ enrolment: Enrolment) throws -> Enrolment {
        var enrolment = enrolment
        enrolment.updatedAt = .now
        try writer.write { db in
            if enrolment.isPrimary {
                try db.execute(sql: "UPDATE enrolment SET isPrimary = 0, updatedAt = ? WHERE studentID = ? AND id <> ?",
                               arguments: [enrolment.updatedAt, enrolment.studentID, enrolment.id])
            }
            try enrolment.save(db)
        }
        return enrolment
    }

    /// Soft-deletes the enrolment and promotes another one if it was primary.
    func deleteEnrolment(id: UUID) throws {
        try writer.write { db in
            guard var enrolment = try Enrolment.fetchOne(db, key: id) else { return }
            enrolment.deletedAt = .now
            enrolment.updatedAt = enrolment.deletedAt!
            enrolment.isPrimary = false
            try enrolment.update(db)
            let remaining = try Enrolment.filter(Column("studentID") == enrolment.studentID && Column("deletedAt") == nil)
                .order(Column("createdAt")).fetchAll(db)
            if !remaining.isEmpty, !remaining.contains(where: \.isPrimary), var first = remaining.first {
                first.isPrimary = true
                first.updatedAt = .now
                try first.update(db)
            }
        }
    }

    func courses() throws -> [Course] {
        try writer.read { db in try Course.order(Column("displayName")).fetchAll(db) }
    }

    func upsertCourses(_ courses: [Course]) throws {
        try writer.write { db in for course in courses { try course.save(db) } }
    }

    // MARK: Contacts

    func contacts(forStudent id: UUID) throws -> [StudentContact] {
        try writer.read { db in
            try StudentContact.filter(Column("studentID") == id).order(Column("isPrimary").desc, Column("name")).fetchAll(db)
        }
    }

    func contactsByStudent() throws -> [UUID: [StudentContact]] {
        let all = try writer.read { db in try StudentContact.order(Column("isPrimary").desc, Column("name")).fetchAll(db) }
        return Dictionary(grouping: all, by: \.studentID)
    }

    @discardableResult
    func save(_ contact: StudentContact) throws -> StudentContact {
        try writer.write { db in try contact.save(db) }
        return contact
    }

    func deleteContact(id: UUID) throws {
        _ = try writer.write { db in try StudentContact.deleteOne(db, key: id) }
    }

    /// Replaces the student's contacts in one go (used by sync).
    func replaceContacts(_ contacts: [StudentContact], forStudent id: UUID) throws {
        try writer.write { db in
            _ = try StudentContact.filter(Column("studentID") == id).deleteAll(db)
            for contact in contacts where contact.studentID == id { try contact.insert(db) }
        }
    }

    // MARK: Topic progress

    func topicProgress(forStudent id: UUID) throws -> [TopicProgress] {
        try writer.read { db in try TopicProgress.filter(Column("studentID") == id).fetchAll(db) }
    }

    func focusTopicIDs(forStudent id: UUID) throws -> [String] {
        try writer.read { db in
            try String.fetchAll(db, sql: "SELECT topicID FROM topicProgress WHERE studentID = ? AND isFocus = 1 ORDER BY topicID", arguments: [id])
        }
    }

    /// Focus topic ids for every student.
    func focusTopicIDsByStudent() throws -> [UUID: [String]] {
        let rows = try writer.read { db in
            try Row.fetchAll(db, sql: "SELECT studentID, topicID FROM topicProgress WHERE isFocus = 1 ORDER BY topicID")
        }
        var result: [UUID: [String]] = [:]
        for row in rows { result[row["studentID"], default: []].append(row["topicID"]) }
        return result
    }

    @discardableResult
    func save(_ progress: TopicProgress) throws -> TopicProgress {
        var progress = progress
        progress.updatedAt = .now
        try writer.write { db in try progress.save(db) }
        return progress
    }

    /// Sets exactly these topics as the student's focus topics, keeping other progress rows.
    func setFocusTopics(_ topicIDs: [String], forStudent id: UUID) throws {
        let wanted = Set(topicIDs)
        try writer.write { db in
            let now = Date.now
            try db.execute(sql: "UPDATE topicProgress SET isFocus = 0, updatedAt = ? WHERE studentID = ? AND isFocus = 1", arguments: [now, id])
            for topicID in wanted {
                if var existing = try TopicProgress.filter(Column("studentID") == id && Column("topicID") == topicID).fetchOne(db) {
                    existing.isFocus = true
                    existing.updatedAt = now
                    try existing.update(db)
                } else {
                    try TopicProgress(studentID: id, topicID: topicID, isFocus: true, updatedAt: now).insert(db)
                }
            }
            _ = try TopicProgress.filter(Column("studentID") == id && Column("isFocus") == false && Column("understanding") == nil && Column("notes") == "").deleteAll(db)
        }
    }

    // MARK: Coverage marks

    func coverageMarks(forStudent id: UUID) throws -> [CoverageMark] {
        try writer.read { db in try CoverageMark.filter(Column("studentID") == id).fetchAll(db) }
    }

    @discardableResult
    func save(_ mark: CoverageMark) throws -> CoverageMark {
        try writer.write { db in try mark.save(db) }
        return mark
    }

    func deleteCoverageMark(studentID: UUID, specPointID: UUID) throws {
        _ = try writer.write { db in
            try CoverageMark.filter(Column("studentID") == studentID && Column("specPointID") == specPointID).deleteAll(db)
        }
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

    func questions(includeDeleted: Bool = false) throws -> [Question] {
        try writer.read { db in
            var request = QuestionRow.order(Column("createdAt").desc)
            if !includeDeleted { request = request.filter(Column("deletedAt") == nil) }
            let rows = try request.fetchAll(db)
            let topics = try Self.topicIDsByQuestion(db)
            return rows.map { $0.question(topicIDs: topics[$0.id] ?? []) }
        }
    }

    func question(id: UUID) throws -> Question? {
        try writer.read { db in
            guard let row = try QuestionRow.fetchOne(db, key: id) else { return nil }
            let topics = try QuestionTopic.filter(Column("questionID") == id).fetchAll(db).map(\.topicID)
            return row.question(topicIDs: topics.sorted())
        }
    }

    /// Saves the record and its payload together.
    func add(_ question: Question, payload: QuestionPayload) throws {
        try media.save(payload, for: question.id)
        try writer.write { db in
            try QuestionRow(question).insert(db)
            try Self.writeTopics(question.topicIDs, for: question.id, db)
        }
    }

    func update(_ question: Question) throws {
        var question = question
        question.updatedAt = .now
        try writer.write { db in
            try QuestionRow(question).update(db)
            try Self.writeTopics(question.topicIDs, for: question.id, db)
        }
    }

    /// Hard delete, including media.
    func deleteQuestion(id: UUID) throws {
        _ = try writer.write { db in try QuestionRow.deleteOne(db, key: id) }
        media.delete(for: id)
    }

    func questions(withImageHashNear hash: String, threshold: Int, excluding id: UUID? = nil) throws -> [Question] {
        try questions(includeDeleted: true).filter { question in
            guard question.id != id, let other = question.imageHash else { return false }
            return ImageHashDistance.hamming(hash, other) <= threshold
        }
    }

    /// Question ids tagged with the topic.
    func questionIDs(forTopic topicID: String) throws -> [UUID] {
        try writer.read { db in
            try UUID.fetchAll(db, sql: "SELECT questionID FROM questionTopic WHERE topicID = ?", arguments: [topicID])
        }
    }

    private static func topicIDsByQuestion(_ db: Database) throws -> [UUID: [String]] {
        let links = try QuestionTopic.order(Column("topicID")).fetchAll(db)
        return Dictionary(grouping: links, by: \.questionID).mapValues { $0.map(\.topicID) }
    }

    private static func writeTopics(_ topicIDs: [String], for questionID: UUID, _ db: Database) throws {
        _ = try QuestionTopic.filter(Column("questionID") == questionID).deleteAll(db)
        for topicID in Set(topicIDs) {
            // Unknown ids get a placeholder topic so the link survives; the taxonomy upsert fixes names later.
            if try Topic.fetchOne(db, key: topicID) == nil {
                try Topic(id: topicID, subject: .maths, name: topicID, sortOrder: 999).insert(db)
            }
            try QuestionTopic(questionID: questionID, topicID: topicID).insert(db)
        }
    }

    // MARK: Outcomes

    func outcomes(forQuestion id: UUID) throws -> [Outcome] {
        try writer.read { db in
            try Outcome.filter(Column("questionID") == id && Column("deletedAt") == nil).order(Column("shownAt").desc).fetchAll(db)
        }
    }

    func outcomes(forStudent id: UUID) throws -> [Outcome] {
        try writer.read { db in
            try Outcome.filter(Column("studentID") == id && Column("deletedAt") == nil).order(Column("shownAt").desc).fetchAll(db)
        }
    }

    func outcomes(forLesson id: UUID) throws -> [Outcome] {
        try writer.read { db in
            try Outcome.filter(Column("lessonID") == id && Column("deletedAt") == nil).order(Column("shownAt").desc).fetchAll(db)
        }
    }

    /// All live outcomes keyed by question id, for list screens.
    func outcomesByQuestion() throws -> [UUID: [Outcome]] {
        let all = try writer.read { db in try Outcome.filter(Column("deletedAt") == nil).order(Column("shownAt").desc).fetchAll(db) }
        return Dictionary(grouping: all, by: \.questionID)
    }

    @discardableResult
    func record(_ outcome: Outcome) throws -> Outcome {
        var outcome = outcome
        outcome.updatedAt = .now
        try writer.write { db in try outcome.save(db) }
        return outcome
    }

    func deleteOutcome(id: UUID) throws {
        _ = try writer.write { db in try Outcome.deleteOne(db, key: id) }
    }

    // MARK: Lessons

    @discardableResult
    func save(_ lesson: Lesson) throws -> Lesson {
        var lesson = lesson
        lesson.updatedAt = .now
        try writer.write { db in try lesson.save(db) }
        return lesson
    }

    func lesson(id: UUID) throws -> Lesson? {
        try writer.read { db in try Lesson.fetchOne(db, key: id) }
    }

    func lesson(forFile fileID: String) throws -> Lesson? {
        try writer.read { db in try Lesson.filter(Column("fileID") == fileID && Column("deletedAt") == nil).fetchOne(db) }
    }

    func lessons(forStudent id: UUID) throws -> [Lesson] {
        try writer.read { db in
            try Lesson.filter(Column("studentID") == id && Column("deletedAt") == nil).order(Column("startAt").desc).fetchAll(db)
        }
    }

    /// Every live lesson keyed by student id, newest first.
    func lessonsByStudent() throws -> [UUID: [Lesson]] {
        let all = try writer.read { db in try Lesson.filter(Column("deletedAt") == nil).order(Column("startAt").desc).fetchAll(db) }
        return Dictionary(grouping: all, by: \.studentID)
    }

    func deleteLesson(id: UUID) throws {
        _ = try writer.write { db in try Lesson.deleteOne(db, key: id) }
    }

    func lessonTopics(forLesson id: UUID) throws -> [LessonTopic] {
        try writer.read { db in try LessonTopic.filter(Column("lessonID") == id).fetchAll(db) }
    }

    func setLessonTopics(_ topics: [LessonTopic], forLesson id: UUID) throws {
        try writer.write { db in
            _ = try LessonTopic.filter(Column("lessonID") == id).deleteAll(db)
            for topic in topics where topic.lessonID == id { try topic.save(db) }
        }
    }

    // MARK: Meta

    func meta(_ key: String) throws -> String? {
        try writer.read { db in try String.fetchOne(db, sql: "SELECT value FROM meta WHERE key = ?", arguments: [key]) }
    }

    func setMeta(_ key: String, _ value: String) throws {
        try writer.write { db in
            try db.execute(sql: "INSERT INTO meta (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value", arguments: [key, value])
        }
    }
}

public enum ImageHashDistance {
    public static let duplicateThreshold = 4

    public static func hamming(_ a: String, _ b: String) -> Int {
        guard let x = UInt64(a, radix: 16), let y = UInt64(b, radix: 16) else { return Int.max }
        return (x ^ y).nonzeroBitCount
    }
}
