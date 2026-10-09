import XCTest
import GRDB
import TutorModels
import TutorSync
@testable import TutorStore

final class SyncEngineTests: XCTestCase {
    func testNameConversion() {
        XCTAssertEqual(TutorSyncEngine.snakeCase("specificationID"), "specification_id")
        XCTAssertEqual(TutorSyncEngine.snakeCase("specPointID"), "spec_point_id")
        XCTAssertEqual(TutorSyncEngine.snakeCase("recapJSON"), "recap_json")
        XCTAssertEqual(TutorSyncEngine.snakeCase("yearGroup"), "year_group")
        XCTAssertEqual(TutorSyncEngine.snakeCase("id"), "id")
        XCTAssertEqual(TutorSyncEngine.camelCase("spec_point_id"), "specPointID")
        XCTAssertEqual(TutorSyncEngine.camelCase("year_group"), "yearGroup")
        XCTAssertEqual(TutorSyncEngine.camelCase("parent_id"), "parentID")
        XCTAssertEqual(TutorSyncEngine.camelCase("recap_json"), "recapJSON")
    }

    func testDates() throws {
        let postgres = try XCTUnwrap(TutorSyncEngine.parseDate("2026-10-09T15:09:06.434457+00:00"))
        let iso = try XCTUnwrap(TutorSyncEngine.parseDate("2026-10-09T15:09:06.434Z"))
        XCTAssertEqual(postgres.timeIntervalSince1970, iso.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertNotNil(TutorSyncEngine.parseDate("2026-10-09 15:09:06.434"))
        XCTAssertNotNil(TutorSyncEngine.parseDate("2026-10-09T15:09:06+00:00"))
        XCTAssertNotNil(TutorSyncEngine.parseDate("2026-10-09T15:09:06Z"))
        let round = try XCTUnwrap(TutorSyncEngine.parseDate(TutorSyncEngine.formatDate(iso)))
        XCTAssertEqual(round.timeIntervalSince1970, iso.timeIntervalSince1970, accuracy: 0.001)
    }

    /// Wire a student + enrolment + question out of one database and apply them into another.
    func testWireRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sync-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let a = try TutorDatabase(directory: root.appendingPathComponent("a"))
        let b = try TutorDatabase(directory: root.appendingPathComponent("b"))
        let student = try a.save(Student(name: "Frankie", yearGroup: "Year 11", remoteID: UUID()))
        let enrolment = try a.save(Enrolment(studentID: student.id, board: .wjec, tier: .higher, targetGrade: "7", isPrimary: true))
        let question = Question(title: "Expand", topicIDs: ["maths.algebra"], freeTags: ["cgp"], imageHash: "00ff")
        try a.add(question, payload: QuestionPayload(elementsJSON: Data("[]".utf8)))
        try a.record(Outcome(questionID: question.id, studentID: student.id, result: .partial, perceivedDifficulty: 3))

        let client = SupabaseRESTClient(baseURL: URL(string: "https://example.invalid")!, apiKey: "x")
        let engineA = TutorSyncEngine(database: a, client: client)
        let engineB = TutorSyncEngine(database: b, client: client)

        for table in TutorSyncEngine.tables {
            let rows = try a.writer.read { db in try Row.fetchAll(db, sql: "SELECT * FROM \(table.local)") }
            let wire = rows.map { TutorSyncEngine.wire($0, dropping: table.localOnly) }
            if table.local == "student" {
                let row = try XCTUnwrap(wire.first)
                XCTAssertEqual(row["year_group"] as? String, "Year 11")
                XCTAssertNil(row["remote_id"])
                XCTAssertEqual((row["id"] as? String)?.count, 36)
                XCTAssertTrue((row["updated_at"] as? String ?? "").hasSuffix("Z"))
            }
            if table.local == "enrolment" {
                let row = try XCTUnwrap(wire.first)
                XCTAssertEqual(row["is_primary"] as? Bool, true)
                XCTAssertEqual(row["tier"] as? String, "Higher")
            }
            if table.local == "question" {
                XCTAssertEqual(wire.first?["free_tags"] as? [String], ["cgp"])
            }
            // Simulate the JSON hop (dates and uuids as strings, bools as JSON bools).
            let data = try JSONSerialization.data(withJSONObject: wire)
            let back = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]
            _ = try engineB.apply(back, to: table)
        }
        _ = engineA

        let copied = try XCTUnwrap(b.student(id: student.id))
        XCTAssertEqual(copied.name, "Frankie"); XCTAssertEqual(copied.yearGroup, "Year 11")
        XCTAssertEqual(copied.updatedAt.timeIntervalSince1970, student.updatedAt.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(try b.enrolments(forStudent: student.id).first?.id, enrolment.id)
        XCTAssertEqual(try b.enrolments(forStudent: student.id).first?.isPrimary, true)
        let q = try XCTUnwrap(b.question(id: question.id))
        XCTAssertEqual(q.topicIDs, ["maths.algebra"]); XCTAssertEqual(q.freeTags, ["cgp"])
        XCTAssertEqual(try b.outcomes(forStudent: student.id).first?.result, .partial)

        // Latest wins: an older copy must not overwrite a newer local row.
        var newer = copied; newer.name = "Frankie R"
        try b.save(newer)
        let stale = try a.writer.read { db in try Row.fetchAll(db, sql: "SELECT * FROM student") }.map { TutorSyncEngine.wire($0, dropping: ["remoteID", "remoteSyncedAt"]) }
        XCTAssertEqual(try engineB.apply(stale, to: TutorSyncEngine.tables.first { $0.local == "student" }!), 0)
        XCTAssertEqual(try b.student(id: student.id)?.name, "Frankie R")
    }
}
