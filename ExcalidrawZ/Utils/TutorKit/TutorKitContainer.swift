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

    func hasBeenShown(_ questionID: UUID, to studentName: String) -> Bool {
        let needle = studentName.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return false }
        return (outcomes[questionID] ?? []).contains { $0.studentName.lowercased() == needle }
    }

    // MARK: - Students

    struct StudentStats {
        var lessons: Int
        var questionsShown: Int
        var lastLesson: Date?
    }

    func stats(for student: Student) -> StudentStats {
        let sessions = (try? database?.lessonSessions(forStudent: student.id)) ?? []
        let shown = outcomes.values.flatMap { $0 }.filter { $0.studentID == student.id || $0.studentName.lowercased() == student.name.lowercased() }
        return StudentStats(lessons: sessions.count, questionsShown: shown.count, lastLesson: sessions.first?.date)
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
