import XCTest
import TutorModels
import TutorStore
import TutorRanking
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
        let student = try db.save(Student(name: "Frankie", board: .edexcel, tier: .higher, targetGrade: "7"))
        XCTAssertEqual(try db.student(named: "frankie")?.id, student.id)

        let question = Question(title: "Expand (x+2)(x+3)", topicIDs: ["maths.algebra.expanding"], imageHash: "00ff00ff00ff00ff")
        try db.add(question, payload: QuestionPayload(elementsJSON: Data("[]".utf8), thumbnailPNG: Data([1, 2, 3])))
        XCTAssertEqual(try db.questions().count, 1)
        XCTAssertEqual(db.media.thumbnailPNG(for: question.id), Data([1, 2, 3]))

        try db.record(Outcome(questionID: question.id, studentID: student.id, studentName: student.name, result: .partial, perceivedDifficulty: 4))
        XCTAssertEqual(try db.outcomes(forStudent: student.id).first?.result, .partial)

        // Cascade: deleting the question removes outcomes and media.
        try db.deleteQuestion(id: question.id)
        XCTAssertTrue(try db.outcomes(forStudent: student.id).isEmpty)
        XCTAssertNil(db.media.thumbnailPNG(for: question.id))

        // Reopen: migrations are idempotent.
        _ = try TutorDatabase(directory: tempDir)
    }

    func testNearDuplicateLookup() throws {
        let db = try TutorDatabase(directory: tempDir)
        let a = Question(title: "a", imageHash: "0000000000000000")
        try db.add(a, payload: QuestionPayload(elementsJSON: Data("[]".utf8)))
        XCTAssertEqual(try db.questions(withImageHashNear: "0000000000000007", threshold: 10).count, 1)
        XCTAssertEqual(try db.questions(withImageHashNear: "ffffffffffffffff", threshold: 10).count, 0)
    }

    func testLegacyImport() throws {
        let legacy = tempDir.appendingPathComponent("QuestionBank", isDirectory: true)
        let qid = UUID()
        try FileManager.default.createDirectory(at: legacy.appendingPathComponent(qid.uuidString), withIntermediateDirectories: true)
        try Data("[{\"type\":\"text\"}]".utf8).write(to: legacy.appendingPathComponent("\(qid.uuidString)/elements.json"))
        try Data([9]).write(to: legacy.appendingPathComponent("\(qid.uuidString)/thumb.png"))
        let index = """
        {"version":1,"entries":[{"id":"\(qid.uuidString)","title":"Legacy Q","source":"CGP p.3","topics":["Quadratics","Weird tag"],
          "board":"AQA","tier":"Higher","marks":4,"notes":"","createdAt":"2026-10-01T10:00:00Z",
          "uses":[{"id":"\(UUID().uuidString)","date":"2026-10-02T15:00:00Z","student":"Frankie","lessonFileID":"f1"}],
          "imageHash":"abcdefabcdefabcd"}]}
        """
        try Data(index.utf8).write(to: legacy.appendingPathComponent("index.json"))

        let db = try TutorDatabase(directory: tempDir.appendingPathComponent("TutorKit"))
        try db.save(Student(name: "Frankie"))
        let importer = LegacyQuestionBankImporter(legacyDirectory: legacy, database: db)
        XCTAssertTrue(importer.hasLegacyData)
        let report = try importer.run(topicResolver: { $0 == "Quadratics" ? "maths.algebra.quadratics" : nil })
        XCTAssertEqual(report, .init(questionsImported: 1, outcomesImported: 1, skipped: 0))

        let q = try XCTUnwrap(db.question(id: qid))
        XCTAssertEqual(q.topicIDs, ["maths.algebra.quadratics"])
        XCTAssertEqual(q.freeTags, ["Weird tag"])
        XCTAssertEqual(q.board, .aqa); XCTAssertEqual(q.tier, .higher); XCTAssertEqual(q.level, .gcse)
        let outcome = try XCTUnwrap(db.outcomes(forQuestion: qid).first)
        XCTAssertEqual(outcome.studentName, "Frankie")
        XCTAssertNotNil(outcome.studentID)
        XCTAssertEqual(db.media.thumbnailPNG(for: qid), Data([9]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.path + ".migrated"))
    }

    func testNeverRepeatPicker() {
        let student = Student(name: "Sam")
        let q1 = Question(title: "1", topicIDs: ["t.a"]), q2 = Question(title: "2", topicIDs: ["t.b"]), q3 = Question(title: "3")
        let outcomes: [UUID: [Outcome]] = [q1.id: [Outcome(questionID: q1.id, studentID: student.id, studentName: "Sam")]]
        let picks = NeverRepeatPicker().pick(from: [q1, q2, q3], outcomes: outcomes, request: .init(student: student, count: 2, preferredTopicIDs: ["t.b"]))
        XCTAssertEqual(picks.map(\.title), ["2", "3"])
    }

    func testJSONExtraction() throws {
        let text = "Sure! ```json\n{\"title\":\"Hi\",\"topics\":[\"a\"],\"marks\":3}\n```"
        let s = try AnthropicMessagesClient.decodeJSONObject(TutorPrompts.TagSuggestion.self, from: text)
        XCTAssertEqual(s.title, "Hi"); XCTAssertEqual(s.marks, 3)
    }
}

final class SpecificationTests: XCTestCase {
    func testDraftMergeSaveAndCoverage() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("spec-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = try TutorDatabase(directory: dir)

        var draft = SpecificationDraft(title: "GCSE Maths", code: "1MA1", subject: "Maths", level: "GCSE", board: "Edexcel", sections: [
            .init(code: "A", title: "Algebra", points: [.init(code: "A4", text: "simplify"), .init(code: "A18", text: "quadratics", tier: "Higher")]),
        ])
        draft.merge(SpecificationDraft(title: "", code: "", subject: "", level: "", board: "", sections: [
            .init(code: "A", title: "Algebra", points: [.init(code: "A18", text: "dup"), .init(code: "A19", text: "simultaneous")]),
            .init(code: "N", title: "Number", points: [.init(code: "N1", text: "order")]),
        ]))
        XCTAssertEqual(draft.sections.count, 2)
        XCTAssertEqual(draft.pointCount, 4)

        let tree = try db.saveSpecification(from: draft, sourceFileName: "spec.pdf")
        XCTAssertEqual(tree.specification.board, .edexcel)
        XCTAssertEqual(tree.points.first { $0.code == "A18" }?.tier, .higher)
        XCTAssertEqual(try db.specificationTree(id: tree.specification.id)?.points.count, 4)

        let student = try db.save(Student(name: "Frankie", specificationID: tree.specification.id))
        let q = Question(title: "q")
        try db.add(q, payload: QuestionPayload(elementsJSON: Data("[]".utf8)))
        let a18 = tree.points.first { $0.code == "A18" }!
        try db.setSpecPoints([a18.id], forQuestion: q.id)
        XCTAssertEqual(try db.specPointIDs(forQuestion: q.id), [a18.id])

        var coverage = try db.coverage(specificationID: tree.specification.id, studentID: student.id, studentName: student.name)
        XCTAssertEqual(coverage[a18.id], .notCovered)
        try db.record(Outcome(questionID: q.id, studentID: student.id, studentName: "Frankie", result: .unknown))
        coverage = try db.coverage(specificationID: tree.specification.id, studentID: student.id, studentName: student.name)
        XCTAssertEqual(coverage[a18.id], .shown)
        try db.record(Outcome(questionID: q.id, studentID: nil, studentName: "frankie", shownAt: .now.addingTimeInterval(60), result: .wrong))
        coverage = try db.coverage(specificationID: tree.specification.id, studentID: student.id, studentName: student.name)
        XCTAssertEqual(coverage[a18.id], .wrong)

        try db.deleteSpecification(id: tree.specification.id)
        XCTAssertTrue(try db.specPointIDs(forQuestion: q.id).isEmpty)
        XCTAssertNil(try db.student(id: student.id)?.specificationID)
    }
}
