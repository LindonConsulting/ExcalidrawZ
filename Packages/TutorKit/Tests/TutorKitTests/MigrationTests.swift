import XCTest
import GRDB
import TutorModels
import TutorStore

/// Builds a database at the v4 schema with the kind of data the live app had,
/// opens it with the current migrator, and checks every row landed in its new home.
final class MigrationTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("migration-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testV4DataSurvivesTheV9Schema() throws {
        try TutorDatabase.migrate(directory: dir, upTo: "v4-multi-spec")
        let queue = try DatabaseQueue(path: dir.appendingPathComponent(TutorDatabase.databaseFileName).path)

        let frankie = UUID(), george = UUID()
        let mathsSpec = UUID(), physicsSpec = UUID()
        let q1 = UUID(), q2 = UUID()
        let session = UUID()
        let t = "2026-10-01 10:00:00.000"
        try queue.write { db in
            try db.execute(sql: "INSERT INTO topic (id, parentID, subject, level, name, aliases, sortOrder) VALUES ('maths.algebra', NULL, 'Maths', NULL, 'Algebra', '[]', 1)")
            try db.execute(sql: "INSERT INTO topic (id, parentID, subject, level, name, aliases, sortOrder) VALUES ('maths.algebra.quadratics', 'maths.algebra', 'Maths', NULL, 'Quadratics', '[]', 2)")
            for (id, subject, level, board) in [(mathsSpec, "Maths", "GCSE", "Edexcel"), (physicsSpec, "Physics", "GCSE", "Edexcel")] {
                try db.execute(sql: "INSERT INTO specification (id, subject, level, board, title, code, sourceFileName, importedAt) VALUES (?, ?, ?, ?, ?, '', '', ?)",
                               arguments: [id, subject, level, board, "\(board) \(level) \(subject)", t])
            }
            try db.execute(sql: """
            INSERT INTO student (id, name, subject, level, board, tier, targetGrade, notes, focusTopicIDs, createdAt, archivedAt, specificationID,
                                 remoteID, yearGroup, management, parentName, parentContact, rapportNotes, remoteSyncedAt, specificationIDs)
            VALUES (?, 'Frankie', 'Maths', 'GCSE', 'Edexcel', 'Higher', '7', 'keen', '["maths.algebra.quadratics","maths.unknown.topic"]', ?, NULL, ?,
                    NULL, 'Year 11', 'private', 'Pat Jones', '07700 900000 · pat@example.com', 'likes chess', NULL, ?)
            """, arguments: [frankie, t, mathsSpec, "[\"\(physicsSpec.uuidString)\",\"\(mathsSpec.uuidString)\"]"])
            try db.execute(sql: """
            INSERT INTO student (id, name, subject, level, board, tier, targetGrade, notes, focusTopicIDs, createdAt, archivedAt, specificationID,
                                 remoteID, yearGroup, management, parentName, parentContact, rapportNotes, remoteSyncedAt, specificationIDs)
            VALUES (?, 'George', 'Computer Science', 'A-Level', 'OCR', NULL, '', '', '[]', ?, ?, NULL, NULL, '', '', '', '', '', NULL, '[]')
            """, arguments: [george, t, t])
            for (id, title, topics) in [(q1, "Solve x²=4", "[\"maths.algebra.quadratics\"]"), (q2, "Untagged", "[]")] {
                try db.execute(sql: """
                INSERT INTO question (id, title, source, subject, level, board, tier, marks, difficulty, notes, topicIDs, freeTags, imageHash, createdAt, archivedAt)
                VALUES (?, ?, '', 'Maths', 'GCSE', NULL, NULL, NULL, NULL, '', ?, '["misc"]', NULL, ?, NULL)
                """, arguments: [id, title, topics, t])
            }
            try db.execute(sql: "INSERT INTO lessonSession (id, studentID, lessonFileID, date, subjectLine, recap) VALUES (?, ?, 'file-1', ?, 'Maths', 'Did quadratics')",
                           arguments: [session, frankie, t])
            // One outcome with an id, one legacy row that only knew the name.
            try db.execute(sql: "INSERT INTO outcome (id, questionID, studentID, studentName, lessonFileID, shownAt, result, perceivedDifficulty, note) VALUES (?, ?, ?, 'Frankie', 'file-1', ?, 'wrong', 4, '')",
                           arguments: [UUID(), q1, frankie, t])
            try db.execute(sql: "INSERT INTO outcome (id, questionID, studentID, studentName, lessonFileID, shownAt, result, perceivedDifficulty, note) VALUES (?, ?, NULL, 'frankie', NULL, ?, 'unknown', NULL, '')",
                           arguments: [UUID(), q2, t])
        }

        let db = try TutorDatabase(directory: dir)

        // Students: George was archived → deletedAt; flat columns gone.
        XCTAssertEqual(try db.students().map(\.name), ["Frankie"])
        XCTAssertEqual(try db.students(includeDeleted: true).count, 2)
        let f = try XCTUnwrap(db.student(id: frankie))
        XCTAssertEqual(f.yearGroup, "Year 11"); XCTAssertEqual(f.rapportNotes, "likes chess"); XCTAssertNil(f.deletedAt)
        XCTAssertNotNil(try db.student(id: george)?.deletedAt)

        // Enrolments: primary from the flat columns, physics from specificationIDs, maths spec not duplicated.
        let enrolments = try db.enrolments(forStudent: frankie)
        XCTAssertEqual(enrolments.count, 2)
        let primary = try XCTUnwrap(enrolments.first)
        XCTAssertTrue(primary.isPrimary)
        XCTAssertEqual(primary.subject, .maths); XCTAssertEqual(primary.level, .gcse); XCTAssertEqual(primary.board, .edexcel)
        XCTAssertEqual(primary.tier, .higher); XCTAssertEqual(primary.targetGrade, "7"); XCTAssertEqual(primary.specificationID, mathsSpec)
        let physics = try XCTUnwrap(enrolments.last)
        XCTAssertFalse(physics.isPrimary); XCTAssertEqual(physics.subject, .physics); XCTAssertEqual(physics.specificationID, physicsSpec)
        XCTAssertEqual(physics.tier, .higher)
        XCTAssertEqual(try db.enrolments(forStudent: george).first?.subject, .computerScience)

        // Contacts split from "phone · email".
        let contact = try XCTUnwrap(db.contacts(forStudent: frankie).first)
        XCTAssertEqual(contact.name, "Pat Jones"); XCTAssertEqual(contact.phone, "07700 900000"); XCTAssertEqual(contact.email, "pat@example.com")
        XCTAssertTrue(try db.contacts(forStudent: george).isEmpty)

        // Focus topics → topicProgress, unknown ids get a placeholder topic.
        XCTAssertEqual(try db.focusTopicIDs(forStudent: frankie), ["maths.algebra.quadratics", "maths.unknown.topic"])
        XCTAssertNotNil(try db.topics().first { $0.id == "maths.unknown.topic" })

        // Questions keep their topics through the join table; archived → deleted.
        let questions = try db.questions()
        XCTAssertEqual(questions.count, 2)
        XCTAssertEqual(try db.question(id: q1)?.topicIDs, ["maths.algebra.quadratics"])
        XCTAssertEqual(try db.question(id: q1)?.freeTags, ["misc"])
        XCTAssertEqual(try db.questionIDs(forTopic: "maths.algebra.quadratics"), [q1])

        // Lesson from lessonSession, linked to the primary enrolment.
        let lesson = try XCTUnwrap(db.lesson(forFile: "file-1"))
        XCTAssertEqual(lesson.id, session); XCTAssertEqual(lesson.studentID, frankie); XCTAssertEqual(lesson.status, .done)
        XCTAssertEqual(lesson.enrolmentID, primary.id); XCTAssertEqual(lesson.recap, "Did quadratics")
        XCTAssertEqual(try db.lessons(forStudent: frankie).count, 1)

        // Outcomes: lessonID resolved from the file, the name-only row resolved to Frankie.
        let outcomes = try db.outcomes(forStudent: frankie)
        XCTAssertEqual(outcomes.count, 2)
        XCTAssertEqual(outcomes.first { $0.questionID == q1 }?.lessonID, lesson.id)
        XCTAssertEqual(outcomes.first { $0.questionID == q1 }?.result, .wrong)
        XCTAssertNil(outcomes.first { $0.questionID == q2 }?.lessonID)
        XCTAssertEqual(try db.coverage(specificationID: mathsSpec, studentID: frankie).count, 0)   // no spec points linked, just no crash

        // Round trip on the new schema and idempotent reopen.
        try db.update(Question(id: q1, title: "Solve x²=4", topicIDs: ["maths.algebra"], createdAt: .now))
        XCTAssertEqual(try db.question(id: q1)?.topicIDs, ["maths.algebra"])
        try db.setFocusTopics(["maths.algebra"], forStudent: frankie)
        XCTAssertEqual(try db.focusTopicIDs(forStudent: frankie), ["maths.algebra"])
        _ = try TutorDatabase(directory: dir)
        XCTAssertEqual(TutorDatabase.migrationIdentifiers.last, "v9-student-cleanup")
    }

    func testFreshDatabaseHasNoLegacyColumns() throws {
        let db = try TutorDatabase(directory: dir)
        let studentColumns = try db.writer.read { db in try db.columns(in: "student").map(\.name) }
        XCTAssertFalse(studentColumns.contains("subject"))
        XCTAssertTrue(studentColumns.contains("deletedAt"))
        let questionColumns = try db.writer.read { db in try db.columns(in: "question").map(\.name) }
        XCTAssertFalse(questionColumns.contains("topicIDs"))
        XCTAssertFalse(try db.writer.read { db in try db.tableExists("lessonSession") })
    }
}
