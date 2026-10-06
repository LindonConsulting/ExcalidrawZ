//
//  TutorKitContainer.swift
//  ExcalidrawZ
//
//  App-side owner of the TutorKit database: opens it, seeds the topic
//  taxonomy, migrates the pre-TutorKit question bank, and publishes
//  snapshots for SwiftUI.
//

import Foundation
import Combine
import os
import TutorModels
import TutorStore

@MainActor
final class TutorKitContainer: ObservableObject {
    static let shared = TutorKitContainer()

    private static let logger = os.Logger(subsystem: "com.lindon.tutorkit", category: "container")

    @Published private(set) var questions: [Question] = []
    @Published private(set) var outcomes: [UUID: [Outcome]] = [:]
    @Published private(set) var topics: [Topic] = []
    @Published private(set) var students: [Student] = []
    @Published private(set) var specifications: [Specification] = []
    /// question id → linked spec point ids
    @Published private(set) var specPointsByQuestion: [UUID: [UUID]] = [:]
    private var treeCache: [UUID: SpecificationTree] = [:]
    @Published private(set) var openError: Error?
    @Published private(set) var legacyImportReport: LegacyQuestionBankImporter.Report?

    private(set) var database: TutorDatabase?
    private var didOpen = false

    enum ContainerError: LocalizedError {
        case notOpen
        var errorDescription: String? { "The tutor database is not available." }
    }

    // MARK: - Lifecycle

    func openIfNeeded() {
        guard !didOpen else { return }
        didOpen = true
        do {
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let directory = support.appendingPathComponent("TutorKit", isDirectory: true)
            let db = try TutorDatabase(directory: directory)
            database = db
            try db.upsertTopics(TopicTaxonomy.builtin)

            let legacy = LegacyQuestionBankImporter(legacyDirectory: support.appendingPathComponent("QuestionBank", isDirectory: true), database: db)
            if legacy.hasLegacyData {
                let taxonomy = TopicTaxonomy.builtin
                legacyImportReport = try legacy.run(topicResolver: { TopicTaxonomy.resolve($0, in: taxonomy)?.id })
                Self.logger.info("legacy import: \(String(describing: self.legacyImportReport))")
            }
            refresh()
        } catch {
            Self.logger.error("open failed: \(error.localizedDescription)")
            openError = error
        }
    }

    func refresh() {
        guard let database else { return }
        do {
            questions = try database.questions()
            outcomes = try database.outcomesByQuestion()
            topics = try database.topics()
            students = try database.students()
            specifications = try database.specifications()
            specPointsByQuestion = try database.specPointIDsByQuestion()
            treeCache = [:]
        } catch {
            openError = error
        }
    }

    private func db() throws -> TutorDatabase {
        guard let database else { throw ContainerError.notOpen }
        return database
    }

    // MARK: - Topics

    var topicNames: [String: String] {
        Dictionary(uniqueKeysWithValues: topics.map { ($0.id, $0.name) })
    }

    func topicName(_ id: String) -> String { topicNames[id] ?? id }

    var strands: [Topic] { topics.filter { $0.parentID == nil } }

    func children(of strandID: String) -> [Topic] { topics.filter { $0.parentID == strandID } }

    func resolveTopic(_ text: String) -> Topic? { TopicTaxonomy.resolve(text, in: topics) }

    // MARK: - Questions

    func add(_ question: Question, payload: QuestionPayload) throws {
        try db().add(question, payload: payload)
        refresh()
    }

    func update(_ question: Question) throws {
        try db().update(question)
        refresh()
    }

    func deleteQuestion(id: UUID) throws {
        try db().deleteQuestion(id: id)
        refresh()
    }

    func payload(for id: UUID) throws -> QuestionPayload {
        try db().media.load(for: id)
    }

    func thumbnailPNG(for id: UUID) -> Data? {
        database?.media.thumbnailPNG(for: id)
    }

    func likelyDuplicates(ofHash hash: String, excluding id: UUID? = nil) -> [Question] {
        (try? db().questions(withImageHashNear: hash, threshold: ImageHashDistance.duplicateThreshold, excluding: id)) ?? []
    }

    // MARK: - Outcomes

    func recordUse(of questionID: UUID, studentName: String, lessonFileID: String?) throws {
        let name = studentName.trimmingCharacters(in: .whitespaces)
        let student = try db().student(named: name)
        try db().record(Outcome(questionID: questionID, studentID: student?.id, studentName: name.isEmpty ? "Unknown" : name, lessonFileID: lessonFileID))
        refresh()
    }

    func record(_ outcome: Outcome) throws {
        try db().record(outcome)
        refresh()
    }

    func deleteOutcome(id: UUID) throws {
        try db().deleteOutcome(id: id)
        refresh()
    }

    /// Outcomes still waiting for a result, optionally limited to one lesson file or student.
    func pendingOutcomes(lessonFileID: String? = nil, studentName: String? = nil) -> [Outcome] {
        outcomes.values.flatMap { $0 }
            .filter { $0.result == .unknown }
            .filter { lessonFileID == nil || $0.lessonFileID == lessonFileID }
            .filter { studentName == nil || $0.studentName.caseInsensitiveCompare(studentName!) == .orderedSame }
            .sorted { $0.shownAt > $1.shownAt }
    }

    func setResult(_ result: OutcomeResult, difficulty: Int? = nil, note: String? = nil, for outcomeID: UUID) throws {
        guard var outcome = outcomes.values.flatMap({ $0 }).first(where: { $0.id == outcomeID }) else { return }
        outcome.result = result
        if let difficulty { outcome.perceivedDifficulty = difficulty }
        if let note { outcome.note = note }
        try db().record(outcome)
        refresh()
    }

    func hasBeenShown(_ questionID: UUID, to studentName: String) -> Bool {
        let needle = studentName.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return false }
        return (outcomes[questionID] ?? []).contains { $0.studentName.lowercased() == needle }
    }

    // MARK: - Specifications

    func specificationTree(id: UUID) -> SpecificationTree? {
        if let cached = treeCache[id] { return cached }
        guard let tree = try? database?.specificationTree(id: id) else { return nil }
        treeCache[id] = tree
        return tree
    }

    func specification(id: UUID?) -> Specification? {
        guard let id else { return nil }
        return specifications.first { $0.id == id }
    }

    @discardableResult
    func saveSpecification(from draft: SpecificationDraft, sourceFileName: String) throws -> SpecificationTree {
        let tree = try db().saveSpecification(from: draft, sourceFileName: sourceFileName)
        refresh()
        return tree
    }

    func deleteSpecification(id: UUID) throws {
        try db().deleteSpecification(id: id)
        refresh()
    }

    func specPoints(forQuestion id: UUID) -> [SpecPoint] {
        let ids = Set(specPointsByQuestion[id] ?? [])
        guard !ids.isEmpty else { return [] }
        return specifications.compactMap { specificationTree(id: $0.id) }.flatMap(\.points).filter { ids.contains($0.id) }
    }

    func setSpecPoints(_ pointIDs: [UUID], forQuestion id: UUID) throws {
        try db().setSpecPoints(pointIDs, forQuestion: id)
        refresh()
    }

    func coverage(for student: Student) -> [UUID: CoverageStatus] {
        guard let specID = student.specificationID else { return [:] }
        return (try? db().coverage(specificationID: specID, studentID: student.id, studentName: student.name)) ?? [:]
    }

    /// Questions linked to a spec point, split into unused / used for the student.
    func questions(forSpecPoint pointID: UUID) -> [Question] {
        questions.filter { (specPointsByQuestion[$0.id] ?? []).contains(pointID) }
    }

    /// The specification for a student name (used when capturing from a lesson file).
    func specificationID(forStudentNamed name: String?) -> UUID? {
        guard let name else { return nil }
        return students.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.specificationID
    }

    // MARK: - Students

    struct CoverageSummary {
        var total: Int
        var counts: [CoverageStatus: Int]
        func count(_ status: CoverageStatus) -> Int { counts[status] ?? 0 }
    }

    struct StudentStats {
        var lessons: Int
        var questionsShown: Int
        var lastLesson: Date?
        var coverage: CoverageSummary?
        var pendingOutcomes: Int
    }

    func stats(for student: Student) -> StudentStats {
        let sessions = (try? database?.lessonSessions(forStudent: student.id)) ?? []
        let shown = outcomes.values.flatMap { $0 }.filter { $0.studentID == student.id || $0.studentName.lowercased() == student.name.lowercased() }
        var summary: CoverageSummary?
        if let specID = student.specificationID, let tree = specificationTree(id: specID) {
            let coverage = coverage(for: student)
            let points = tree.points.filter { $0.tier == nil || student.tier == nil || $0.tier == student.tier }
            var counts: [CoverageStatus: Int] = [:]
            for point in points { counts[coverage[point.id] ?? .notCovered, default: 0] += 1 }
            summary = CoverageSummary(total: points.count, counts: counts)
        }
        return StudentStats(lessons: sessions.count, questionsShown: shown.count, lastLesson: sessions.first?.date, coverage: summary,
                            pendingOutcomes: shown.filter { $0.result == .unknown }.count)
    }

    /// Finds the student by name or creates a minimal record (used by Lesson Draw).
    @discardableResult
    func ensureStudent(named name: String, subjectHint: String?) throws -> Student {
        openIfNeeded()
        if let existing = try db().student(named: name) { return existing }
        var student = Student(name: name.trimmingCharacters(in: .whitespaces))
        if let hint = subjectHint?.lowercased() {
            if hint.contains("computer") || hint.contains("cs") { student.subject = .computerScience }
            if hint.contains("a level") || hint.contains("a-level") || hint.contains("alevel") { student.level = .aLevel }
            else if hint.contains("ks3") { student.level = .ks3 }
            for board in ExamBoard.allCases where hint.contains(board.rawValue.lowercased()) { student.board = board }
            if hint.contains("foundation") { student.tier = .foundation } else if hint.contains("higher") { student.tier = .higher }
        }
        try db().save(student)
        refresh()
        return student
    }

    func recordLessonSession(student: Student, lessonFileID: String, date: Date, subjectLine: String, recap: String?) throws {
        try db().record(LessonSession(studentID: student.id, lessonFileID: lessonFileID, date: date, subjectLine: subjectLine, recap: recap))
        refresh()
    }

    func save(_ student: Student) throws {
        try db().save(student)
        refresh()
    }

    func deleteStudent(id: UUID) throws {
        try db().deleteStudent(id: id)
        refresh()
    }
}
