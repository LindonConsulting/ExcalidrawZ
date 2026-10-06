import Foundation

/// An exam specification (e.g. Edexcel GCSE Maths 1MA1). Sections group spec points.
public struct Specification: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var subject: Subject
    public var level: QualificationLevel
    public var board: ExamBoard
    public var title: String
    /// Board code such as "1MA1" or "8300".
    public var code: String
    public var sourceFileName: String
    public var importedAt: Date

    public init(id: UUID = UUID(), subject: Subject, level: QualificationLevel, board: ExamBoard, title: String,
                code: String = "", sourceFileName: String = "", importedAt: Date = .now) {
        self.id = id; self.subject = subject; self.level = level; self.board = board; self.title = title
        self.code = code; self.sourceFileName = sourceFileName; self.importedAt = importedAt
    }

    public var displayName: String {
        let codePart = code.isEmpty ? "" : " (\(code))"
        return "\(board.rawValue) \(level.rawValue) \(subject.rawValue)\(codePart)"
    }
}

public struct SpecSection: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var specificationID: UUID
    public var code: String
    public var title: String
    public var sortOrder: Int

    public init(id: UUID = UUID(), specificationID: UUID, code: String, title: String, sortOrder: Int) {
        self.id = id; self.specificationID = specificationID; self.code = code; self.title = title; self.sortOrder = sortOrder
    }
}

/// One assessable statement ("A4 simplify and manipulate algebraic expressions…").
public struct SpecPoint: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var specificationID: UUID
    public var sectionID: UUID
    public var code: String
    public var text: String
    /// Tier restriction for GCSE ("Higher only"); nil = both.
    public var tier: Tier?
    public var sortOrder: Int

    public init(id: UUID = UUID(), specificationID: UUID, sectionID: UUID, code: String, text: String, tier: Tier? = nil, sortOrder: Int) {
        self.id = id; self.specificationID = specificationID; self.sectionID = sectionID; self.code = code
        self.text = text; self.tier = tier; self.sortOrder = sortOrder
    }
}

public struct QuestionSpecPoint: Codable, Hashable, Sendable {
    public var questionID: UUID
    public var specPointID: UUID

    public init(questionID: UUID, specPointID: UUID) {
        self.questionID = questionID; self.specPointID = specPointID
    }
}

/// Importer output before it is saved: a whole spec as a tree.
public struct SpecificationDraft: Codable, Sendable, Equatable {
    public struct Section: Codable, Sendable, Equatable {
        public var code: String
        public var title: String
        public var points: [Point]
        public init(code: String, title: String, points: [Point]) { self.code = code; self.title = title; self.points = points }
    }
    public struct Point: Codable, Sendable, Equatable {
        public var code: String
        public var text: String
        public var tier: String?
        public init(code: String, text: String, tier: String? = nil) { self.code = code; self.text = text; self.tier = tier }
    }

    public var title: String
    public var code: String
    public var subject: String
    public var level: String
    public var board: String
    public var sections: [Section]

    public init(title: String, code: String, subject: String, level: String, board: String, sections: [Section]) {
        self.title = title; self.code = code; self.subject = subject; self.level = level; self.board = board; self.sections = sections
    }

    public var pointCount: Int { sections.reduce(0) { $0 + $1.points.count } }

    /// Normalised tier label used for de-duplication ("Higher", "Foundation" or "").
    static func tierKey(_ tier: String?) -> String {
        let lowered = (tier ?? "").lowercased()
        if lowered.contains("higher") { return "Higher" }
        if lowered.contains("foundation") { return "Foundation" }
        return ""
    }

    /// Merges another chunk's sections into this draft. Sections match on code
    /// (so "Number (Foundation)" and "Number (Higher)" join); points are
    /// de-duplicated by code **and tier**, so a Higher-only version of N1 is
    /// kept alongside the Foundation one. When the same code+tier appears
    /// twice, the longer statement wins (chunk boundaries can truncate).
    public mutating func merge(_ other: SpecificationDraft) {
        if title.isEmpty { title = other.title }
        if code.isEmpty { code = other.code }
        if subject.isEmpty { subject = other.subject }
        if level.isEmpty { level = other.level }
        if board.isEmpty { board = other.board }
        for section in other.sections {
            guard let index = sections.firstIndex(where: { $0.code == section.code && !section.code.isEmpty }) else {
                sections.append(section)
                continue
            }
            if sections[index].title.count < section.title.count, Self.tierKey(section.title) == "" {
                sections[index].title = section.title
            }
            for point in section.points {
                let key = (point.code, Self.tierKey(point.tier))
                if let existing = sections[index].points.firstIndex(where: { ($0.code, Self.tierKey($0.tier)) == key && !point.code.isEmpty }) {
                    if sections[index].points[existing].text.count < point.text.count {
                        sections[index].points[existing].text = point.text
                    }
                } else {
                    sections[index].points.append(point)
                }
            }
        }
        // Strip tier suffixes from section titles once both tiers are merged.
        for index in sections.indices {
            sections[index].title = sections[index].title
                .replacingOccurrences(of: #"\s*\((Foundation|Higher) tier\)"#, with: "", options: .regularExpression)
        }
    }
}

/// Coverage status of one spec point for one student, derived from outcomes.
public enum CoverageStatus: String, Codable, Sendable, CaseIterable {
    case notCovered, shown, right, partial, wrong

    public static func from(outcomes: [Outcome]) -> CoverageStatus {
        guard !outcomes.isEmpty else { return .notCovered }
        let recorded = outcomes.filter { $0.result != .unknown && $0.result != .skipped }
        guard let latest = recorded.max(by: { $0.shownAt < $1.shownAt }) else { return .shown }
        switch latest.result {
            case .right: return .right
            case .partial: return .partial
            case .wrong: return .wrong
            default: return .shown
        }
    }
}
