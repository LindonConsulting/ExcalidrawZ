import XCTest
import TutorModels
import TutorStore
import TutorAI

final class TutorStoreTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("TutorKitTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testRoundTrips() throws {
        let db = try TutorDatabase(directory: tempDir)
        let student = try db.save(Student(name: "Frankie"))
        try db.save(Enrolment(studentID: student.id, board: .edexcel, tier: .higher, targetGrade: "7", isPrimary: true))
        XCTAssertEqual(try db.student(named: "frankie")?.id, student.id)
        XCTAssertEqual(try db.enrolments(forStudent: student.id).first?.courseName, "Edexcel GCSE Maths (Higher)")

        let lesson = try db.save(Lesson(studentID: student.id, fileID: "file-1", subjectLine: "Maths", recap: "Did quadratics"))
        XCTAssertEqual(try db.lesson(forFile: "file-1")?.id, lesson.id)
        XCTAssertEqual(try db.lessons(forStudent: student.id).count, 1)

        // Cascade: deleting the student removes enrolments and lessons.
        try db.deleteStudent(id: student.id)
        XCTAssertTrue(try db.enrolments(forStudent: student.id).isEmpty)
        XCTAssertNil(try db.lesson(forFile: "file-1"))

        // Reopen: migrations are idempotent.
        _ = try TutorDatabase(directory: tempDir)
    }

    func testJSONExtraction() throws {
        struct Reply: Decodable { var title: String; var marks: Int }
        let text = "Sure! ```json\n{\"title\":\"Hi\",\"marks\":3}\n```"
        let s = try AnthropicMessagesClient.decodeJSONObject(Reply.self, from: text)
        XCTAssertEqual(s.title, "Hi"); XCTAssertEqual(s.marks, 3)
    }
}

final class BackupTests: XCTestCase {
    func testExportAndRestore() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("backup-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let db = try TutorDatabase(directory: root.appendingPathComponent("live"))
        let sam = try db.save(Student(name: "Sam"))

        let manager = TutorBackupManager(database: db)
        let backup = try manager.exportBackup(to: root.appendingPathComponent("exports"))
        XCTAssertEqual(TutorBackupManager.manifest(of: backup)?.studentCount, 1)

        // Mutate, then restore.
        try db.deleteStudent(id: sam.id)
        try db.save(Student(name: "Extra"))
        XCTAssertEqual(try db.students().map(\.name), ["Extra"])
        try manager.restoreBackup(from: backup, safetyDirectory: root.appendingPathComponent("safety"))
        XCTAssertEqual(try db.students().map(\.name), ["Sam"])
        XCTAssertEqual(try TutorBackupManager.backups(in: root.appendingPathComponent("safety")).count, 1)

        // Automatic: once per day.
        let auto = root.appendingPathComponent("auto")
        XCTAssertNotNil(try manager.runAutomaticBackupIfDue(in: auto))
        XCTAssertNil(try manager.runAutomaticBackupIfDue(in: auto))
        XCTAssertNotNil(try manager.runAutomaticBackupIfDue(in: auto, now: .now.addingTimeInterval(86_400 * 2)))
        XCTAssertEqual(try TutorBackupManager.backups(in: auto).count, 2)
    }
}
