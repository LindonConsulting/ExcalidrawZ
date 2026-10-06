import Foundation
import GRDB
import TutorModels

/// SQLite database for TutorKit. Media (question payloads) live beside it in `media/`.
public final class TutorDatabase: Sendable {
    public let writer: any DatabaseWriter
    public let media: QuestionMediaStore

    public static let databaseFileName = "tutor.sqlite"

    /// Opens (or creates) the database inside `directory` and runs migrations.
    public convenience init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var config = Configuration()
        config.foreignKeysEnabled = true
        let queue = try DatabaseQueue(path: directory.appendingPathComponent(Self.databaseFileName).path, configuration: config)
        try self.init(writer: queue, mediaDirectory: directory.appendingPathComponent("media", isDirectory: true))
    }

    /// In-memory database for tests.
    public static func inMemory(mediaDirectory: URL) throws -> TutorDatabase {
        var config = Configuration()
        config.foreignKeysEnabled = true
        return try TutorDatabase(writer: try DatabaseQueue(configuration: config), mediaDirectory: mediaDirectory)
    }

    public init(writer: any DatabaseWriter, mediaDirectory: URL) throws {
        self.writer = writer
        self.media = QuestionMediaStore(directory: mediaDirectory)
        try Self.migrator.migrate(writer)
    }

    // MARK: - Schema

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "student") { t in
                t.primaryKey("id", .blob)
                t.column("name", .text).notNull()
                t.column("subject", .text).notNull()
                t.column("level", .text).notNull()
                t.column("board", .text)
                t.column("tier", .text)
                t.column("targetGrade", .text).notNull().defaults(to: "")
                t.column("notes", .text).notNull().defaults(to: "")
                t.column("focusTopicIDs", .text).notNull().defaults(to: "[]")
                t.column("createdAt", .datetime).notNull()
                t.column("archivedAt", .datetime)
            }
            try db.create(index: "student_name", on: "student", columns: ["name"])

            try db.create(table: "topic") { t in
                t.primaryKey("id", .blob)
                t.column("parentID", .text).references("topic", onDelete: .cascade)
                t.column("subject", .text).notNull()
                t.column("level", .text)
                t.column("name", .text).notNull()
                t.column("aliases", .text).notNull().defaults(to: "[]")
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
            }

            try db.create(table: "question") { t in
                t.primaryKey("id", .blob)
                t.column("title", .text).notNull()
                t.column("source", .text).notNull().defaults(to: "")
                t.column("subject", .text).notNull()
                t.column("level", .text)
                t.column("board", .text)
                t.column("tier", .text)
                t.column("marks", .integer)
                t.column("difficulty", .integer)
                t.column("notes", .text).notNull().defaults(to: "")
                t.column("topicIDs", .text).notNull().defaults(to: "[]")
                t.column("freeTags", .text).notNull().defaults(to: "[]")
                t.column("imageHash", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("archivedAt", .datetime)
            }
            try db.create(index: "question_imageHash", on: "question", columns: ["imageHash"])

            try db.create(table: "outcome") { t in
                t.primaryKey("id", .blob)
                t.column("questionID", .blob).notNull().references("question", onDelete: .cascade)
                t.column("studentID", .blob).references("student", onDelete: .setNull)
                t.column("studentName", .text).notNull().defaults(to: "")
                t.column("lessonFileID", .text)
                t.column("shownAt", .datetime).notNull()
                t.column("result", .text).notNull().defaults(to: "unknown")
                t.column("perceivedDifficulty", .integer)
                t.column("note", .text).notNull().defaults(to: "")
            }
            try db.create(index: "outcome_question", on: "outcome", columns: ["questionID"])
            try db.create(index: "outcome_student", on: "outcome", columns: ["studentID", "shownAt"])

            try db.create(table: "lessonSession") { t in
                t.primaryKey("id", .blob)
                t.column("studentID", .blob).notNull().references("student", onDelete: .cascade)
                t.column("lessonFileID", .text).notNull()
                t.column("date", .datetime).notNull()
                t.column("subjectLine", .text).notNull().defaults(to: "")
                t.column("recap", .text)
            }
            try db.create(index: "lessonSession_file", on: "lessonSession", columns: ["lessonFileID"])
        }
        migrator.registerMigration("v2-specifications") { db in
            try db.create(table: "specification") { t in
                t.primaryKey("id", .blob)
                t.column("subject", .text).notNull()
                t.column("level", .text).notNull()
                t.column("board", .text).notNull()
                t.column("title", .text).notNull()
                t.column("code", .text).notNull().defaults(to: "")
                t.column("sourceFileName", .text).notNull().defaults(to: "")
                t.column("importedAt", .datetime).notNull()
            }
            try db.create(table: "specSection") { t in
                t.primaryKey("id", .blob)
                t.column("specificationID", .blob).notNull().references("specification", onDelete: .cascade)
                t.column("code", .text).notNull().defaults(to: "")
                t.column("title", .text).notNull()
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
            }
            try db.create(table: "specPoint") { t in
                t.primaryKey("id", .blob)
                t.column("specificationID", .blob).notNull().references("specification", onDelete: .cascade)
                t.column("sectionID", .blob).notNull().references("specSection", onDelete: .cascade)
                t.column("code", .text).notNull().defaults(to: "")
                t.column("text", .text).notNull()
                t.column("tier", .text)
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
            }
            try db.create(index: "specPoint_spec", on: "specPoint", columns: ["specificationID", "sortOrder"])
            try db.create(table: "questionSpecPoint") { t in
                t.column("questionID", .blob).notNull().references("question", onDelete: .cascade)
                t.column("specPointID", .blob).notNull().references("specPoint", onDelete: .cascade)
                t.primaryKey(["questionID", "specPointID"])
            }
            try db.alter(table: "student") { t in
                t.add(column: "specificationID", .blob).references("specification", onDelete: .setNull)
            }
        }
        return migrator
    }
}

extension Specification: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "specification"
}
extension SpecSection: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "specSection"
}
extension SpecPoint: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "specPoint"
}
extension QuestionSpecPoint: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "questionSpecPoint"
}

// MARK: - GRDB conformances

extension Student: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "student"
}
extension Topic: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "topic"
}
extension Question: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "question"
}
extension Outcome: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "outcome"
}
extension LessonSession: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "lessonSession"
}
