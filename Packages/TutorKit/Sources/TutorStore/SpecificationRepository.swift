import Foundation
import GRDB
import TutorModels

public struct SpecificationTree: Sendable {
    public var specification: Specification
    public var sections: [SpecSection]
    public var points: [SpecPoint]

    public func points(in section: SpecSection) -> [SpecPoint] {
        points.filter { $0.sectionID == section.id }.sorted { $0.sortOrder < $1.sortOrder }
    }
}

public extension TutorDatabase {
    func specifications() throws -> [Specification] {
        try writer.read { db in try Specification.order(Column("board"), Column("level"), Column("subject")).fetchAll(db) }
    }

    func specificationTree(id: UUID) throws -> SpecificationTree? {
        try writer.read { db in
            guard let spec = try Specification.fetchOne(db, key: id) else { return nil }
            let sections = try SpecSection.filter(Column("specificationID") == id).order(Column("sortOrder")).fetchAll(db)
            let points = try SpecPoint.filter(Column("specificationID") == id).order(Column("sortOrder")).fetchAll(db)
            return SpecificationTree(specification: spec, sections: sections, points: points)
        }
    }

    /// Saves an importer draft as a new specification. Returns the tree.
    @discardableResult
    func saveSpecification(from draft: SpecificationDraft, sourceFileName: String) throws -> SpecificationTree {
        let subject = Subject(rawValue: draft.subject) ?? {
            let s = draft.subject.lowercased()
            if s.contains("comput") { return .computerScience }
            if s.contains("biol") { return .biology }
            if s.contains("chem") { return .chemistry }
            if s.contains("phys") { return .physics }
            if s.contains("science") { return .combinedScience }
            return .maths
        }()
        let level = QualificationLevel(rawValue: draft.level) ?? (draft.level.lowercased().contains("a") ? .aLevel : .gcse)
        let board = ExamBoard.allCases.first { draft.board.lowercased().contains($0.rawValue.lowercased()) } ?? .other
        let spec = Specification(subject: subject, level: level, board: board, title: draft.title.isEmpty ? "\(board.rawValue) \(level.rawValue) \(subject.rawValue)" : draft.title,
                                 code: draft.code, sourceFileName: sourceFileName)
        var sections: [SpecSection] = []
        var points: [SpecPoint] = []
        var order = 0
        for (sIndex, section) in draft.sections.enumerated() {
            let record = SpecSection(specificationID: spec.id, code: section.code, title: section.title, sortOrder: sIndex)
            sections.append(record)
            for point in section.points {
                order += 1
                let tier: Tier? = point.tier.flatMap { raw in
                    let lowered = raw.lowercased()
                    if lowered.contains("higher") { return .higher }
                    if lowered.contains("foundation") { return .foundation }
                    return nil
                }
                points.append(SpecPoint(specificationID: spec.id, sectionID: record.id, code: point.code, text: point.text, tier: tier, sortOrder: order))
            }
        }
        try writer.write { db in
            try spec.insert(db)
            for section in sections { try section.insert(db) }
            for point in points { try point.insert(db) }
        }
        return SpecificationTree(specification: spec, sections: sections, points: points)
    }

    func deleteSpecification(id: UUID) throws {
        _ = try writer.write { db in try Specification.deleteOne(db, key: id) }
    }

    // MARK: Question ↔ spec point links

    func specPointIDs(forQuestion id: UUID) throws -> [UUID] {
        try writer.read { db in
            try QuestionSpecPoint.filter(Column("questionID") == id).fetchAll(db).map(\.specPointID)
        }
    }

    func setSpecPoints(_ pointIDs: [UUID], forQuestion id: UUID) throws {
        try writer.write { db in
            _ = try QuestionSpecPoint.filter(Column("questionID") == id).deleteAll(db)
            for pointID in Set(pointIDs) { try QuestionSpecPoint(questionID: id, specPointID: pointID).insert(db) }
        }
    }

    /// All links, keyed by spec point id → question ids.
    func questionIDsBySpecPoint(specificationID: UUID) throws -> [UUID: [UUID]] {
        let links = try writer.read { db in
            try QuestionSpecPoint
                .joining(required: QuestionSpecPoint.belongsTo(SpecPoint.self, using: ForeignKey(["specPointID"])).filter(Column("specificationID") == specificationID))
                .fetchAll(db)
        }
        return Dictionary(grouping: links, by: \.specPointID).mapValues { $0.map(\.questionID) }
    }

    func specPointIDsByQuestion() throws -> [UUID: [UUID]] {
        let links = try writer.read { db in try QuestionSpecPoint.fetchAll(db) }
        return Dictionary(grouping: links, by: \.questionID).mapValues { $0.map(\.specPointID) }
    }

    // MARK: Coverage

    /// Coverage per spec point for a student, from outcomes on linked questions.
    func coverage(specificationID: UUID, studentID: UUID) throws -> [UUID: CoverageStatus] {
        let byPoint = try questionIDsBySpecPoint(specificationID: specificationID)
        let outcomes = try writer.read { db in
            try Outcome.filter(Column("studentID") == studentID && Column("deletedAt") == nil).fetchAll(db)
        }
        let byQuestion = Dictionary(grouping: outcomes, by: \.questionID)
        var result: [UUID: CoverageStatus] = [:]
        for (pointID, questionIDs) in byPoint {
            result[pointID] = CoverageStatus.from(outcomes: questionIDs.flatMap { byQuestion[$0] ?? [] })
        }
        return result
    }
}
