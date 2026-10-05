//
//  QuestionBankModels.swift
//  ExcalidrawZ
//
//  Records for the tutoring question bank (issue #7).
//

import Foundation

struct QuestionUse: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var date: Date
    var student: String
    var lessonFileID: String?
}

struct QuestionBankEntry: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var title: String
    /// Where it came from: "Edexcel 1MA1/1H June 2023 Q12", "CGP p.44 Q3", ...
    var source: String = ""
    var topics: [String] = []
    var board: String = ""
    var tier: String = ""
    var marks: Int?
    var notes: String = ""
    var createdAt: Date = .now
    var uses: [QuestionUse] = []
    /// dHash of the thumbnail (see QuestionImageHash); nil for old entries.
    var imageHash: String?

    func hasBeenUsed(by student: String) -> Bool {
        let normalized = student.trimmingCharacters(in: .whitespaces).lowercased()
        guard !normalized.isEmpty else { return false }
        return uses.contains { $0.student.lowercased() == normalized }
    }

    var lastUse: QuestionUse? { uses.max { $0.date < $1.date } }

    func matches(query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return true }
        let haystack = ([title, source, board, tier, notes] + topics + uses.map(\.student)).joined(separator: " ").lowercased()
        return q.split(separator: " ").allSatisfy { haystack.contains($0) }
    }
}

/// Fixed topic list used for AI suggestions and the filter menu. The user can
/// still type any tag.
enum QuestionBankTaxonomy {
    static let boards = ["AQA", "Edexcel", "OCR", "WJEC", "CCEA", "Cambridge", "Other"]
    static let tiers = ["Foundation", "Higher", "A-Level", "KS3", "Other"]
    static let topics: [String] = [
        "Number", "Fractions, decimals & percentages", "Ratio & proportion", "Indices & surds", "Standard form",
        "Algebra basics", "Expanding & factorising", "Linear equations", "Simultaneous equations", "Quadratics",
        "Inequalities", "Sequences", "Functions", "Iteration", "Algebraic fractions", "Proof",
        "Straight-line graphs", "Quadratic & other graphs", "Transformations of graphs", "Gradients & rates of change",
        "Angles & polygons", "Pythagoras", "Trigonometry", "Sine & cosine rules", "Circle theorems", "Vectors",
        "Transformations", "Constructions & loci", "Similarity & congruence", "Area & perimeter", "Volume & surface area",
        "Bearings & scale", "Bounds & accuracy", "Compound measures",
        "Probability", "Venn diagrams & sets", "Averages & spread", "Charts & diagrams", "Scatter graphs", "Cumulative frequency & box plots", "Histograms",
        "Problem solving", "Mixed revision",
    ]
}
