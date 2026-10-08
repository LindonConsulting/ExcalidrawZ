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
        let queue = try DatabaseQueue(path: directory.appendingPathComponent(Self.databaseFileName).path, configuration: Self.configuration)
        try self.init(writer: queue, mediaDirectory: directory.appendingPathComponent("media", isDirectory: true))
    }

    /// In-memory database for tests.
    public static func inMemory(mediaDirectory: URL) throws -> TutorDatabase {
        try TutorDatabase(writer: try DatabaseQueue(configuration: configuration), mediaDirectory: mediaDirectory)
    }

    public init(writer: any DatabaseWriter, mediaDirectory: URL) throws {
        self.writer = writer
        self.media = QuestionMediaStore(directory: mediaDirectory)
        try Self.migrator.migrate(writer)
    }

    static var configuration: Configuration {
        var config = Configuration()
        config.foreignKeysEnabled = true
        return config
    }

    /// Identifiers of every migration, oldest first. Tests use it to build fixtures at an older version.
    public static var migrationIdentifiers: [String] { migrator.migrations }

    /// Migrates the database file at `directory` up to (and including) `identifier`
    /// without opening a `TutorDatabase`. Intended for tests that build old-version fixtures.
    public static func migrate(directory: URL, upTo identifier: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let queue = try DatabaseQueue(path: directory.appendingPathComponent(databaseFileName).path, configuration: configuration)
        try migrator.migrate(queue, upTo: identifier)
    }

    // MARK: - Schema

    /// GRDB date format, so SQL-side timestamps match Codable ones.
    static let sqlNow = "strftime('%Y-%m-%d %H:%M:%f', 'now')"

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
        migrator.registerMigration("v3-remote-profile") { db in
            try db.alter(table: "student") { t in
                t.add(column: "remoteID", .blob)
                t.add(column: "yearGroup", .text).notNull().defaults(to: "")
                t.add(column: "management", .text).notNull().defaults(to: "")
                t.add(column: "parentName", .text).notNull().defaults(to: "")
                t.add(column: "parentContact", .text).notNull().defaults(to: "")
                t.add(column: "rapportNotes", .text).notNull().defaults(to: "")
                t.add(column: "remoteSyncedAt", .datetime)
            }
            try db.create(index: "student_remote", on: "student", columns: ["remoteID"])
        }
        migrator.registerMigration("v4-multi-spec") { db in
            try db.alter(table: "student") { t in
                t.add(column: "specificationIDs", .text).notNull().defaults(to: "[]")
            }
        }

        // MARK: v5 – enrolments replace the flat subject/level/board/tier/spec columns on student.
        migrator.registerMigration("v5-enrolments") { db in
            try db.execute(sql: """
            CREATE TABLE course (
                id TEXT PRIMARY KEY NOT NULL,
                subject TEXT NOT NULL,
                level TEXT NOT NULL,
                displayName TEXT NOT NULL,
                active INTEGER NOT NULL DEFAULT 1
            );
            CREATE TABLE enrolment (
                id BLOB PRIMARY KEY NOT NULL,
                studentID BLOB NOT NULL REFERENCES student(id) ON DELETE CASCADE,
                courseID TEXT REFERENCES course(id) ON DELETE SET NULL,
                specificationID BLOB REFERENCES specification(id) ON DELETE SET NULL,
                subject TEXT NOT NULL,
                level TEXT NOT NULL,
                board TEXT,
                tier TEXT,
                targetGrade TEXT NOT NULL DEFAULT '',
                startedAt DATETIME,
                endedAt DATETIME,
                isPrimary INTEGER NOT NULL DEFAULT 0,
                notes TEXT NOT NULL DEFAULT '',
                remoteID BLOB,
                createdAt DATETIME NOT NULL,
                updatedAt DATETIME NOT NULL,
                deletedAt DATETIME
            );
            CREATE INDEX enrolment_student ON enrolment(studentID);
            CREATE UNIQUE INDEX enrolment_unique ON enrolment(studentID, subject, level) WHERE deletedAt IS NULL;
            """)
            // One primary enrolment per student from the flat columns.
            try db.execute(sql: """
            INSERT INTO enrolment (id, studentID, specificationID, subject, level, board, tier, targetGrade, isPrimary, createdAt, updatedAt)
            SELECT randomblob(16), id, specificationID, subject, level, board, tier, targetGrade, 1, createdAt, \(sqlNow)
            FROM student
            """)
            // One more per extra specification the student was linked to (subject/level/board from the spec).
            try db.execute(sql: """
            INSERT OR IGNORE INTO enrolment (id, studentID, specificationID, subject, level, board, tier, targetGrade, isPrimary, createdAt, updatedAt)
            SELECT randomblob(16), s.id, sp.id, sp.subject, sp.level, sp.board,
                   CASE WHEN sp.level = 'GCSE' THEN s.tier ELSE NULL END, '', 0, s.createdAt, \(sqlNow)
            FROM student s, json_each(s.specificationIDs) j
            JOIN specification sp ON hex(sp.id) = replace(upper(j.value), '-', '')
            WHERE s.specificationID IS NULL OR sp.id <> s.specificationID
            """)
        }

        // MARK: v6 – lesson replaces lessonSession; outcomes point at lessons and students by id.
        migrator.registerMigration("v6-lessons") { db in
            try db.execute(sql: """
            CREATE TABLE lesson (
                id BLOB PRIMARY KEY NOT NULL,
                studentID BLOB NOT NULL REFERENCES student(id) ON DELETE CASCADE,
                enrolmentID BLOB REFERENCES enrolment(id) ON DELETE SET NULL,
                fileID TEXT,
                calendarEventID TEXT,
                startAt DATETIME NOT NULL,
                endAt DATETIME,
                durationMinutes INTEGER,
                status TEXT NOT NULL DEFAULT 'planned',
                subjectLine TEXT NOT NULL DEFAULT '',
                plan TEXT NOT NULL DEFAULT '',
                recap TEXT,
                recapJSON TEXT,
                homeworkSet TEXT NOT NULL DEFAULT '',
                nextPlan TEXT NOT NULL DEFAULT '',
                transcriptPath TEXT,
                billable INTEGER NOT NULL DEFAULT 1,
                remoteID BLOB,
                createdAt DATETIME NOT NULL,
                updatedAt DATETIME NOT NULL,
                deletedAt DATETIME
            );
            CREATE INDEX lesson_student_date ON lesson(studentID, startAt);
            CREATE UNIQUE INDEX lesson_file ON lesson(fileID) WHERE fileID IS NOT NULL;
            CREATE TABLE lessonTopic (
                lessonID BLOB NOT NULL REFERENCES lesson(id) ON DELETE CASCADE,
                topicID TEXT NOT NULL REFERENCES topic(id) ON DELETE CASCADE,
                minutes INTEGER,
                note TEXT NOT NULL DEFAULT '',
                PRIMARY KEY (lessonID, topicID)
            );
            INSERT OR IGNORE INTO lesson (id, studentID, enrolmentID, fileID, startAt, status, subjectLine, recap, createdAt, updatedAt)
            SELECT ls.id, ls.studentID,
                   (SELECT e.id FROM enrolment e WHERE e.studentID = ls.studentID ORDER BY e.isPrimary DESC, e.createdAt LIMIT 1),
                   ls.lessonFileID, ls.date, 'done', ls.subjectLine, ls.recap, ls.date, \(sqlNow)
            FROM lessonSession ls ORDER BY ls.date;
            """)
            try db.execute(sql: """
            CREATE TABLE outcome_new (
                id BLOB PRIMARY KEY NOT NULL,
                questionID BLOB NOT NULL REFERENCES question(id) ON DELETE CASCADE,
                studentID BLOB REFERENCES student(id) ON DELETE SET NULL,
                lessonID BLOB REFERENCES lesson(id) ON DELETE SET NULL,
                shownAt DATETIME NOT NULL,
                result TEXT NOT NULL DEFAULT 'unknown',
                marksAwarded INTEGER,
                perceivedDifficulty INTEGER,
                timeSeconds INTEGER,
                note TEXT NOT NULL DEFAULT '',
                remoteID BLOB,
                createdAt DATETIME NOT NULL,
                updatedAt DATETIME NOT NULL,
                deletedAt DATETIME
            );
            INSERT INTO outcome_new (id, questionID, studentID, lessonID, shownAt, result, perceivedDifficulty, note, createdAt, updatedAt)
            SELECT o.id, o.questionID,
                   COALESCE(o.studentID, (SELECT s.id FROM student s WHERE lower(s.name) = lower(trim(o.studentName)) LIMIT 1)),
                   (SELECT l.id FROM lesson l WHERE l.fileID = o.lessonFileID LIMIT 1),
                   o.shownAt, o.result, o.perceivedDifficulty, o.note, o.shownAt, \(sqlNow)
            FROM outcome o;
            DROP TABLE outcome;
            ALTER TABLE outcome_new RENAME TO outcome;
            CREATE INDEX outcome_question ON outcome(questionID);
            CREATE INDEX outcome_student ON outcome(studentID, shownAt);
            CREATE INDEX outcome_lesson ON outcome(lessonID);
            DROP TABLE lessonSession;
            """)
        }

        // MARK: v7 – topic progress (focus topics), coverage marks, parent contacts.
        migrator.registerMigration("v7-progress-contacts") { db in
            try db.execute(sql: """
            CREATE TABLE topicProgress (
                studentID BLOB NOT NULL REFERENCES student(id) ON DELETE CASCADE,
                topicID TEXT NOT NULL REFERENCES topic(id) ON DELETE CASCADE,
                understanding INTEGER,
                isFocus INTEGER NOT NULL DEFAULT 0,
                startedAt DATETIME,
                lastRevisedAt DATETIME,
                notes TEXT NOT NULL DEFAULT '',
                remoteID BLOB,
                updatedAt DATETIME NOT NULL,
                PRIMARY KEY (studentID, topicID)
            );
            INSERT OR IGNORE INTO topic (id, parentID, subject, level, name, aliases, sortOrder)
            SELECT DISTINCT j.value, NULL, s.subject, NULL, j.value, '[]', 999
            FROM student s, json_each(s.focusTopicIDs) j
            WHERE NOT EXISTS (SELECT 1 FROM topic t WHERE t.id = j.value);
            INSERT OR IGNORE INTO topicProgress (studentID, topicID, isFocus, updatedAt)
            SELECT s.id, j.value, 1, \(sqlNow) FROM student s, json_each(s.focusTopicIDs) j;
            CREATE TABLE coverageMark (
                studentID BLOB NOT NULL REFERENCES student(id) ON DELETE CASCADE,
                specPointID BLOB NOT NULL REFERENCES specPoint(id) ON DELETE CASCADE,
                status TEXT NOT NULL,
                markedAt DATETIME NOT NULL,
                lessonID BLOB REFERENCES lesson(id) ON DELETE SET NULL,
                note TEXT NOT NULL DEFAULT '',
                PRIMARY KEY (studentID, specPointID)
            );
            CREATE TABLE studentContact (
                id BLOB PRIMARY KEY NOT NULL,
                studentID BLOB NOT NULL REFERENCES student(id) ON DELETE CASCADE,
                name TEXT NOT NULL DEFAULT '',
                relationship TEXT NOT NULL DEFAULT '',
                phone TEXT NOT NULL DEFAULT '',
                email TEXT NOT NULL DEFAULT '',
                preferredMethod TEXT NOT NULL DEFAULT '',
                isPrimary INTEGER NOT NULL DEFAULT 0
            );
            CREATE INDEX studentContact_student ON studentContact(studentID);
            """)
            // parentContact was "phone · email" (either part optional); split it.
            let rows = try Row.fetchAll(db, sql: "SELECT id, parentName, parentContact FROM student WHERE parentName <> '' OR parentContact <> ''")
            for row in rows {
                let name: String = row["parentName"]
                let contact: String = row["parentContact"]
                var phone = "", email = ""
                for part in contact.components(separatedBy: "·").map({ $0.trimmingCharacters(in: .whitespaces) }) where !part.isEmpty {
                    if part.contains("@") { email = part } else { phone = part }
                }
                try db.execute(sql: """
                INSERT INTO studentContact (id, studentID, name, relationship, phone, email, preferredMethod, isPrimary)
                VALUES (randomblob(16), ?, ?, 'parent', ?, ?, '', 1)
                """, arguments: [row["id"] as Data, name, phone, email])
            }
        }

        // MARK: v8 – question topics become a join table; question gains soft delete and answer fields.
        migrator.registerMigration("v8-question-joins") { db in
            try db.execute(sql: """
            CREATE TABLE questionTopic (
                questionID BLOB NOT NULL REFERENCES question(id) ON DELETE CASCADE,
                topicID TEXT NOT NULL REFERENCES topic(id) ON DELETE CASCADE,
                PRIMARY KEY (questionID, topicID)
            );
            CREATE INDEX questionTopic_topic ON questionTopic(topicID);
            CREATE TABLE specPointTopic (
                specPointID BLOB NOT NULL REFERENCES specPoint(id) ON DELETE CASCADE,
                topicID TEXT NOT NULL REFERENCES topic(id) ON DELETE CASCADE,
                PRIMARY KEY (specPointID, topicID)
            );
            INSERT OR IGNORE INTO topic (id, parentID, subject, level, name, aliases, sortOrder)
            SELECT DISTINCT j.value, NULL, q.subject, NULL, j.value, '[]', 999
            FROM question q, json_each(q.topicIDs) j
            WHERE NOT EXISTS (SELECT 1 FROM topic t WHERE t.id = j.value);
            INSERT OR IGNORE INTO questionTopic (questionID, topicID)
            SELECT q.id, j.value FROM question q, json_each(q.topicIDs) j;
            CREATE TABLE question_new (
                id BLOB PRIMARY KEY NOT NULL,
                title TEXT NOT NULL,
                source TEXT NOT NULL DEFAULT '',
                subject TEXT NOT NULL,
                level TEXT,
                board TEXT,
                tier TEXT,
                marks INTEGER,
                difficulty INTEGER,
                notes TEXT NOT NULL DEFAULT '',
                answer TEXT NOT NULL DEFAULT '',
                workedSolution TEXT NOT NULL DEFAULT '',
                freeTags TEXT NOT NULL DEFAULT '[]',
                imageHash TEXT,
                remoteID BLOB,
                createdAt DATETIME NOT NULL,
                updatedAt DATETIME NOT NULL,
                deletedAt DATETIME
            );
            INSERT INTO question_new (id, title, source, subject, level, board, tier, marks, difficulty, notes, freeTags, imageHash, createdAt, updatedAt, deletedAt)
            SELECT id, title, source, subject, level, board, tier, marks, difficulty, notes, freeTags, imageHash, createdAt, \(sqlNow), archivedAt
            FROM question;
            DROP TABLE question;
            ALTER TABLE question_new RENAME TO question;
            CREATE INDEX question_imageHash ON question(imageHash);
            """)
        }

        // MARK: v9 – student keeps only who-they-are columns; archivedAt becomes deletedAt.
        migrator.registerMigration("v9-student-cleanup") { db in
            try db.execute(sql: """
            CREATE TABLE student_new (
                id BLOB PRIMARY KEY NOT NULL,
                name TEXT NOT NULL,
                yearGroup TEXT NOT NULL DEFAULT '',
                school TEXT NOT NULL DEFAULT '',
                management TEXT NOT NULL DEFAULT '',
                notes TEXT NOT NULL DEFAULT '',
                rapportNotes TEXT NOT NULL DEFAULT '',
                hobbies TEXT NOT NULL DEFAULT '',
                interests TEXT NOT NULL DEFAULT '',
                calendarIdentifier TEXT,
                remoteID BLOB,
                remoteSyncedAt DATETIME,
                createdAt DATETIME NOT NULL,
                updatedAt DATETIME NOT NULL,
                deletedAt DATETIME
            );
            INSERT INTO student_new (id, name, yearGroup, management, notes, rapportNotes, remoteID, remoteSyncedAt, createdAt, updatedAt, deletedAt)
            SELECT id, name, yearGroup, management, notes, rapportNotes, remoteID, remoteSyncedAt, createdAt, \(sqlNow), archivedAt
            FROM student;
            DROP TABLE student;
            ALTER TABLE student_new RENAME TO student;
            CREATE INDEX student_name ON student(name);
            CREATE INDEX student_remote ON student(remoteID);
            CREATE TABLE meta (key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL);
            """)
        }
        return migrator
    }
}

// MARK: - GRDB conformances

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
extension Student: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "student"
}
extension StudentContact: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "studentContact"
}
extension Enrolment: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "enrolment"
}
extension Course: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "course"
}
extension Topic: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "topic"
}
extension TopicProgress: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "topicProgress"
}
extension CoverageMark: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "coverageMark"
}
extension Outcome: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "outcome"
}
extension Lesson: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "lesson"
}
extension LessonTopic: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "lessonTopic"
}

/// `question` row without the join-table column; `Question.topicIDs` is attached by the store.
struct QuestionRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "question"

    var id: UUID
    var title: String
    var source: String
    var subject: Subject
    var level: QualificationLevel?
    var board: ExamBoard?
    var tier: Tier?
    var marks: Int?
    var difficulty: Int?
    var notes: String
    var answer: String
    var workedSolution: String
    var freeTags: [String]
    var imageHash: String?
    var remoteID: UUID?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(_ q: Question) {
        id = q.id; title = q.title; source = q.source; subject = q.subject; level = q.level; board = q.board; tier = q.tier
        marks = q.marks; difficulty = q.difficulty; notes = q.notes; answer = q.answer; workedSolution = q.workedSolution
        freeTags = q.freeTags; imageHash = q.imageHash; remoteID = q.remoteID
        createdAt = q.createdAt; updatedAt = q.updatedAt; deletedAt = q.deletedAt
    }

    func question(topicIDs: [String]) -> Question {
        Question(id: id, title: title, source: source, subject: subject, level: level, board: board, tier: tier, marks: marks,
                 difficulty: difficulty, notes: notes, answer: answer, workedSolution: workedSolution, topicIDs: topicIDs,
                 freeTags: freeTags, imageHash: imageHash, remoteID: remoteID, createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt)
    }
}

struct QuestionTopic: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "questionTopic"
    var questionID: UUID
    var topicID: String
}
