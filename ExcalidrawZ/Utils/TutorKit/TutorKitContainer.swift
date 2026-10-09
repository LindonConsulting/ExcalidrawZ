//
//  TutorKitContainer.swift
//  ExcalidrawZ
//
//  App-side owner of the TutorKit database: opens it, seeds the topic
//  taxonomy, migrates the pre-TutorKit question bank, and publishes
//  snapshots for SwiftUI. Students are looked up by id; names only come in
//  from the calendar and the file group, and are resolved once at the edge.
//

import Foundation
import Combine
import os
import TutorModels
import TutorStore
import TutorRanking
import TutorSync

@MainActor
final class TutorKitContainer: ObservableObject {
    static let shared = TutorKitContainer()

    private static let logger = os.Logger(subsystem: "com.lindon.tutorkit", category: "container")

    @Published private(set) var questions: [Question] = []
    @Published private(set) var outcomes: [UUID: [Outcome]] = [:]
    @Published private(set) var topics: [Topic] = []
    @Published private(set) var students: [Student] = []
    /// student id → live enrolments, primary first
    @Published private(set) var enrolments: [UUID: [Enrolment]] = [:]
    /// student id → lessons, newest first
    @Published private(set) var lessons: [UUID: [Lesson]] = [:]
    /// student id → focus topic ids
    @Published private(set) var focusTopics: [UUID: [String]] = [:]
    /// student id → contacts
    @Published private(set) var contacts: [UUID: [StudentContact]] = [:]
    @Published private(set) var specifications: [Specification] = []
    @Published private(set) var roster: [RosterEntry] = []
    @Published private(set) var rosterError: String?
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncMessage: String?
    @Published private(set) var deckAssignmentsByStudent: [UUID: [RemoteDeckAssignment]] = [:]
    @Published private(set) var remoteDecks: [UUID: RemoteDeck] = [:]
    /// question id → linked spec point ids
    @Published private(set) var specPointsByQuestion: [UUID: [UUID]] = [:]
    private var treeCache: [UUID: SpecificationTree] = [:]
    private var lessonsByFile: [String: Lesson] = [:]
    @Published private(set) var openError: Error?
    @Published private(set) var legacyImportReport: LegacyQuestionBankImporter.Report?

    private(set) var database: TutorDatabase?
    private var didOpen = false
    private(set) var directory: URL?
    @Published private(set) var lastAutomaticBackup: Date?
    static let automaticBackupsEnabledKey = "TutorKit.automaticBackups"

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
            self.directory = directory
            try db.upsertTopics(TopicTaxonomy.builtin)
            runAutomaticBackupIfEnabled()
            let merged = try SpecificationConsolidation.consolidateAll(in: db)
            if merged > 0 { Self.logger.info("consolidated \(merged) specification sections") }

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
            enrolments = try database.enrolmentsByStudent()
            lessons = try database.lessonsByStudent()
            focusTopics = try database.focusTopicIDsByStudent()
            contacts = try database.contactsByStudent()
            specifications = try database.specifications()
            specPointsByQuestion = try database.specPointIDsByQuestion()
            lessonsByFile = Dictionary(lessons.values.flatMap { $0 }.compactMap { lesson in lesson.fileID.map { ($0, lesson) } }, uniquingKeysWith: { a, _ in a })
            treeCache = [:]
        } catch {
            openError = error
        }
    }

    private func db() throws -> TutorDatabase {
        guard let database else { throw ContainerError.notOpen }
        return database
    }

    // MARK: - Students and enrolments

    func student(id: UUID?) -> Student? {
        guard let id else { return nil }
        return students.first { $0.id == id }
    }

    func student(named name: String) -> Student? {
        let needle = name.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return nil }
        return students.first { $0.name.caseInsensitiveCompare(needle) == .orderedSame }
    }

    /// Display name for an outcome's student, or "Unknown".
    func studentName(for id: UUID?) -> String {
        student(id: id)?.name ?? (id.flatMap { try? database?.student(id: $0) }?.name ?? "Unknown")
    }

    func enrolments(for student: Student) -> [Enrolment] { enrolments[student.id] ?? [] }

    func primaryEnrolment(for student: Student) -> Enrolment? {
        let list = enrolments(for: student)
        return list.first { $0.isPrimary } ?? list.first
    }

    /// Specification ids linked through the student's enrolments, primary first.
    func specificationIDs(for student: Student) -> [UUID] {
        var result: [UUID] = []
        for id in enrolments(for: student).compactMap(\.specificationID) where !result.contains(id) { result.append(id) }
        return result
    }

    /// Specifications linked to a student, primary first.
    func specifications(for student: Student) -> [Specification] {
        specificationIDs(for: student).compactMap { specification(id: $0) }
    }

    func focusTopicIDs(for student: Student) -> [String] { focusTopics[student.id] ?? [] }

    func contacts(for student: Student) -> [StudentContact] { contacts[student.id] ?? [] }

    /// "GCSE · Maths · Edexcel · Higher" from the primary enrolment.
    func courseSummary(for student: Student) -> String {
        guard let e = primaryEnrolment(for: student) else { return "" }
        return [e.level.rawValue, e.subject.rawValue, e.board?.rawValue, e.tier.flatMap { $0 == .notApplicable ? nil : $0.rawValue }]
            .compactMap { $0 }.joined(separator: " · ")
    }

    func save(_ student: Student) throws {
        try db().save(student)
        refresh()
    }

    func archive(_ student: Student) throws {
        var copy = student
        copy.deletedAt = .now
        try db().save(copy)
        refresh()
    }

    func deleteStudent(id: UUID) throws {
        try db().deleteStudent(id: id)
        refresh()
    }

    @discardableResult
    func save(_ enrolment: Enrolment) throws -> Enrolment {
        let saved = try db().save(enrolment)
        refresh()
        return saved
    }

    func deleteEnrolment(id: UUID) throws {
        try db().deleteEnrolment(id: id)
        refresh()
    }

    func setFocusTopics(_ topicIDs: [String], for student: Student) throws {
        try db().setFocusTopics(topicIDs, forStudent: student.id)
        refresh()
    }

    /// Finds the student by name or creates a minimal record with a primary
    /// enrolment guessed from the calendar subject (used by Lesson Draw).
    @discardableResult
    func ensureStudent(named name: String, subjectHint: String?) throws -> Student {
        openIfNeeded()
        if let existing = try db().student(named: name) { return existing }
        let student = try db().save(Student(name: name.trimmingCharacters(in: .whitespaces)))
        try db().save(Self.enrolment(for: student.id, subjectHint: subjectHint, isPrimary: true))
        refresh()
        return student
    }

    /// An enrolment guessed from free text such as "A-Level Maths (Edexcel, Higher)".
    static func enrolment(for studentID: UUID, subjectHint: String?, isPrimary: Bool) -> Enrolment {
        var enrolment = Enrolment(studentID: studentID, isPrimary: isPrimary)
        guard let hint = subjectHint?.lowercased() else { return enrolment }
        if hint.contains("computer") || hint.contains(" cs") || hint.hasPrefix("cs") { enrolment.subject = .computerScience }
        else if hint.contains("biolog") { enrolment.subject = .biology }
        else if hint.contains("chem") { enrolment.subject = .chemistry }
        else if hint.contains("physic") { enrolment.subject = .physics }
        if hint.contains("a level") || hint.contains("a-level") || hint.contains("alevel") { enrolment.level = .aLevel }
        else if hint.contains("ks3") { enrolment.level = .ks3 }
        for board in ExamBoard.allCases where hint.contains(board.rawValue.lowercased()) { enrolment.board = board }
        if hint.contains("foundation") { enrolment.tier = .foundation } else if hint.contains("higher") { enrolment.tier = .higher }
        return enrolment
    }

    // MARK: - Roster (calendar) and Supabase sync

    func refreshRoster() async {
        do {
            roster = try await StudentRosterBuilder.build(pattern: LessonDrawPreferences.shared.titlePattern)
            rosterError = nil
        } catch {
            rosterError = error.localizedDescription
        }
    }

    /// Two-way sync with the TutorKit Supabase project (pull, then push), plus the deck catalogue.
    func syncFromSupabase() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let database = try db()
            let client = try TutorSyncSettings.makeClient()
            let report = try await TutorSyncEngine(database: database, client: client).sync()
            if let decksRemote = try? await client.fetchDecks() {
                remoteDecks = Dictionary(uniqueKeysWithValues: decksRemote.map { ($0.id, $0) })
            }
            if let assignmentsRemote = try? await client.fetchDeckAssignments() {
                deckAssignmentsByStudent = Dictionary(grouping: assignmentsRemote, by: \.student_id)
            }
            refresh()
            lastSyncMessage = "Synced at \(Date().formatted(date: .omitted, time: .shortened)): \(report.description)"
        } catch {
            lastSyncMessage = "Sync failed: \(error.localizedDescription)"
            Self.logger.error("sync failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Backups

    var backupsDirectory: URL? { directory?.appendingPathComponent("backups", isDirectory: true) }

    var automaticBackupsEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.automaticBackupsEnabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.automaticBackupsEnabledKey); objectWillChange.send(); runAutomaticBackupIfEnabled() }
    }

    func runAutomaticBackupIfEnabled() {
        guard automaticBackupsEnabled, let database, let backupsDirectory else { return }
        do {
            _ = try TutorBackupManager(database: database).runAutomaticBackupIfDue(in: backupsDirectory)
            lastAutomaticBackup = try TutorBackupManager.backups(in: backupsDirectory).first?.manifest.createdAt
        } catch {
            Self.logger.error("automatic backup failed: \(error.localizedDescription)")
        }
    }

    var automaticBackups: [TutorBackupManager.BackupEntry] {
        guard let backupsDirectory else { return [] }
        return (try? TutorBackupManager.backups(in: backupsDirectory)) ?? []
    }

    @discardableResult
    func exportBackup(to destination: URL) throws -> URL {
        try TutorBackupManager(database: try db()).exportBackup(to: destination)
    }

    func restoreBackup(from folder: URL) throws {
        try TutorBackupManager(database: try db()).restoreBackup(from: folder, safetyDirectory: backupsDirectory)
        treeCache = [:]
        refresh()
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

    // MARK: - Lessons

    /// The lesson a Lesson Draw file belongs to, if any.
    func lesson(forFile fileID: String?) -> Lesson? {
        guard let fileID else { return nil }
        return lessonsByFile[fileID]
    }

    func lessons(for student: Student) -> [Lesson] { lessons[student.id] ?? [] }

    /// Creates the lesson for `fileID`, or merges the recap into the existing one
    /// (e.g. an imported MyTutor lesson appended to a Lesson Draw file).
    @discardableResult
    func upsertLesson(student: Student, fileID: String, date: Date, subjectLine: String, recap: String?) throws -> Lesson {
        let database = try db()
        let lesson: Lesson
        if var existing = try database.lesson(forFile: fileID) {
            if let recap, !recap.isEmpty {
                existing.recap = [existing.recap, recap].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n\n")
            }
            if existing.subjectLine.isEmpty { existing.subjectLine = subjectLine }
            lesson = try database.save(existing)
        } else {
            let enrolment = Self.matchEnrolment(subjectLine, among: try database.enrolments(forStudent: student.id))
            lesson = try database.save(Lesson(studentID: student.id, enrolmentID: enrolment?.id, fileID: fileID, startAt: date,
                                              status: .done, subjectLine: subjectLine, recap: recap))
        }
        refresh()
        return lesson
    }

    func save(_ lesson: Lesson) throws {
        try db().save(lesson)
        refresh()
    }

    /// Picks the enrolment whose subject appears in the calendar subject line; falls back to the primary.
    static func matchEnrolment(_ subjectLine: String, among enrolments: [Enrolment]) -> Enrolment? {
        let line = subjectLine.lowercased()
        if !line.isEmpty {
            if let hit = enrolments.first(where: { line.contains($0.subject.rawValue.lowercased()) }) { return hit }
            if line.contains("cs") || line.contains("comput"), let hit = enrolments.first(where: { $0.subject == .computerScience }) { return hit }
        }
        return enrolments.first { $0.isPrimary } ?? enrolments.first
    }

    // MARK: - Outcomes

    /// Records that a question was shown. The name comes from the file group;
    /// a student record (and the lesson row for the file) is created when needed.
    func recordUse(of questionID: UUID, studentName: String?, lessonFileID: String?) throws {
        let name = (studentName ?? "").trimmingCharacters(in: .whitespaces)
        var student: Student?
        if !name.isEmpty, name.caseInsensitiveCompare("Unknown") != .orderedSame {
            student = try ensureStudent(named: name, subjectHint: nil)
        }
        var lessonID: UUID?
        if let fileID = lessonFileID, let student {
            lessonID = try db().lesson(forFile: fileID)?.id
                ?? upsertLesson(student: student, fileID: fileID, date: .now, subjectLine: "", recap: nil).id
        }
        try db().record(Outcome(questionID: questionID, studentID: student?.id, lessonID: lessonID))
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
    func pendingOutcomes(lessonFileID: String? = nil, studentID: UUID? = nil) -> [Outcome] {
        let lessonID = lesson(forFile: lessonFileID)?.id
        if lessonFileID != nil, lessonID == nil { return [] }
        return outcomes.values.flatMap { $0 }
            .filter { $0.result == .unknown }
            .filter { lessonID == nil || $0.lessonID == lessonID }
            .filter { studentID == nil || $0.studentID == studentID }
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

    func hasBeenShown(_ questionID: UUID, to studentID: UUID) -> Bool {
        (outcomes[questionID] ?? []).contains { $0.studentID == studentID }
    }

    func hasBeenShown(_ questionID: UUID, toStudentNamed name: String) -> Bool {
        guard let student = student(named: name) else { return false }
        return hasBeenShown(questionID, to: student.id)
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
        _ = try SpecificationConsolidation.consolidate(specificationID: tree.specification.id, in: try db().writer)
        refresh()
        return specificationTree(id: tree.specification.id) ?? tree
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

    /// Coverage across every specification linked to the student.
    func coverage(for student: Student) -> [UUID: CoverageStatus] {
        var result: [UUID: CoverageStatus] = [:]
        for specID in specificationIDs(for: student) {
            if let partial = try? db().coverage(specificationID: specID, studentID: student.id) {
                result.merge(partial) { current, _ in current }
            }
        }
        return result
    }

    /// Questions linked to a spec point.
    func questions(forSpecPoint pointID: UUID) -> [Question] {
        questions.filter { (specPointsByQuestion[$0.id] ?? []).contains(pointID) }
    }

    /// The primary specification for a student name (used when capturing from a lesson file).
    func specificationID(forStudentNamed name: String?) -> UUID? {
        guard let name, let student = student(named: name) else { return nil }
        return primaryEnrolment(for: student)?.specificationID ?? specificationIDs(for: student).first
    }

    /// Number of students enrolled against a specification.
    func studentCount(forSpecification id: UUID) -> Int {
        enrolments.values.filter { $0.contains { $0.specificationID == id } }.count
    }

    // MARK: - Warm-up picks

    struct WarmUpPick: Identifiable, Equatable {
        var question: Question
        var reason: String
        var id: UUID { question.id }
        static func == (lhs: WarmUpPick, rhs: WarmUpPick) -> Bool { lhs.id == rhs.id }
    }

    /// Picks warm-up questions for a student name (creates no records).
    func warmUpPicks(forStudentNamed name: String, subjectLine: String? = nil, count: Int = 3) -> [WarmUpPick] {
        openIfNeeded()
        let student = student(named: name)
        var tiers: [UUID: Tier?] = [:]
        var coverage: [UUID: CoverageStatus] = [:]
        var enrolment: Enrolment?
        if let student {
            enrolment = Self.matchEnrolment(subjectLine ?? "", among: enrolments(for: student))
            for tree in specificationIDs(for: student).compactMap({ specificationTree(id: $0) }) {
                for point in tree.points { tiers[point.id] = point.tier }
            }
            coverage = self.coverage(for: student)
        }
        let context = PickerContext(student: student, enrolment: enrolment, focusTopicIDs: Set(student.map(focusTopicIDs(for:)) ?? []),
                                    coverage: coverage, specPointsByQuestion: specPointsByQuestion, specPointTiers: tiers, outcomes: outcomes)
        return CoveragePicker(count: count).pick(questions, context: context).map { WarmUpPick(question: $0.question, reason: $0.reason) }
    }

    // MARK: - Stats

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
        let lessons = lessons(for: student)
        let shown = outcomes.values.flatMap { $0 }.filter { $0.studentID == student.id }
        var summary: CoverageSummary?
        let trees = specificationIDs(for: student).compactMap { specificationTree(id: $0) }
        if !trees.isEmpty {
            let coverage = coverage(for: student)
            let tier = primaryEnrolment(for: student)?.tier
            var counts: [CoverageStatus: Int] = [:]
            var total = 0
            for tree in trees {
                let points = tree.points.filter { $0.tier == nil || tier == nil || $0.tier == tier }
                for point in points { counts[coverage[point.id] ?? .notCovered, default: 0] += 1 }
                total += points.count
            }
            summary = CoverageSummary(total: total, counts: counts)
        }
        return StudentStats(lessons: lessons.count, questionsShown: shown.count, lastLesson: lessons.first?.startAt, coverage: summary,
                            pendingOutcomes: shown.filter { $0.result == .unknown }.count)
    }
}
