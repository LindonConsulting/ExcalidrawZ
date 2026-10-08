import Foundation
import TutorModels

/// One-off import of the pre-TutorKit question bank
/// (`QuestionBank/index.json` + `<id>/elements.json|files.json|thumb.png`).
public struct LegacyQuestionBankImporter {
    public struct Report: Sendable, Equatable {
        public var questionsImported = 0
        public var outcomesImported = 0
        public var skipped = 0

        public init(questionsImported: Int = 0, outcomesImported: Int = 0, skipped: Int = 0) {
            self.questionsImported = questionsImported; self.outcomesImported = outcomesImported; self.skipped = skipped
        }
    }

    private struct LegacyUse: Decodable {
        var id: UUID?
        var date: Date
        var student: String
        var lessonFileID: String?
    }

    private struct LegacyEntry: Decodable {
        var id: UUID
        var title: String
        var source: String?
        var topics: [String]?
        var board: String?
        var tier: String?
        var marks: Int?
        var notes: String?
        var createdAt: Date
        var uses: [LegacyUse]?
        var imageHash: String?
    }

    private struct LegacyIndex: Decodable {
        var entries: [LegacyEntry]
    }

    public let legacyDirectory: URL
    public let database: TutorDatabase

    public init(legacyDirectory: URL, database: TutorDatabase) {
        self.legacyDirectory = legacyDirectory
        self.database = database
    }

    public var hasLegacyData: Bool {
        FileManager.default.fileExists(atPath: legacyDirectory.appendingPathComponent("index.json").path)
    }

    /// Imports everything, then renames the legacy folder to `<name>.migrated`.
    /// Topic strings become taxonomy ids when they match a known topic, else free tags.
    @discardableResult
    public func run(topicResolver: (String) -> String? = { _ in nil }, renameWhenDone: Bool = true) throws -> Report {
        var report = Report()
        let indexURL = legacyDirectory.appendingPathComponent("index.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let index = try decoder.decode(LegacyIndex.self, from: Data(contentsOf: indexURL))
        let existing = Set(try database.questions(includeDeleted: true).map(\.id))

        for entry in index.entries {
            if existing.contains(entry.id) { report.skipped += 1; continue }
            let folder = legacyDirectory.appendingPathComponent(entry.id.uuidString, isDirectory: true)
            guard let elements = try? Data(contentsOf: folder.appendingPathComponent("elements.json")) else {
                report.skipped += 1; continue
            }
            let payload = QuestionPayload(
                elementsJSON: elements,
                filesJSON: try? Data(contentsOf: folder.appendingPathComponent("files.json")),
                thumbnailPNG: try? Data(contentsOf: folder.appendingPathComponent("thumb.png"))
            )
            var topicIDs: [String] = [], freeTags: [String] = []
            for raw in entry.topics ?? [] {
                if let id = topicResolver(raw) { topicIDs.append(id) } else { freeTags.append(raw) }
            }
            let question = Question(
                id: entry.id,
                title: entry.title,
                source: entry.source ?? "",
                subject: .maths,
                level: Self.level(from: entry.tier),
                board: ExamBoard(rawValue: entry.board ?? ""),
                tier: Self.tier(from: entry.tier),
                marks: entry.marks,
                notes: entry.notes ?? "",
                topicIDs: topicIDs,
                freeTags: freeTags,
                imageHash: entry.imageHash,
                createdAt: entry.createdAt
            )
            try database.add(question, payload: payload)
            report.questionsImported += 1

            for use in entry.uses ?? [] {
                let student = try database.student(named: use.student)
                var lessonID: UUID?
                if let fileID = use.lessonFileID, let student {
                    if let lesson = try database.lesson(forFile: fileID) {
                        lessonID = lesson.id
                    } else {
                        lessonID = try database.save(Lesson(studentID: student.id, fileID: fileID, startAt: use.date, status: .done)).id
                    }
                }
                try database.record(Outcome(
                    id: use.id ?? UUID(),
                    questionID: entry.id,
                    studentID: student?.id,
                    lessonID: lessonID,
                    shownAt: use.date,
                    result: .unknown,
                    note: student == nil ? "Legacy use by \(use.student)" : ""
                ))
                report.outcomesImported += 1
            }
        }

        if renameWhenDone {
            let target = legacyDirectory.deletingLastPathComponent()
                .appendingPathComponent(legacyDirectory.lastPathComponent + ".migrated")
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.moveItem(at: legacyDirectory, to: target)
        }
        return report
    }

    private static func level(from tier: String?) -> QualificationLevel? {
        switch tier {
            case "Foundation", "Higher": return .gcse
            case "A-Level": return .aLevel
            case "KS3": return .ks3
            default: return nil
        }
    }

    private static func tier(from tier: String?) -> Tier? {
        switch tier {
            case "Foundation": return .foundation
            case "Higher": return .higher
            default: return nil
        }
    }
}
