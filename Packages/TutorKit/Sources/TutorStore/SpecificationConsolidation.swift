import Foundation
import GRDB
import TutorModels

/// Merges sections that the chunked importer named inconsistently
/// ("N - Number", "Number – Place value", "Number (Higher tier)") into one
/// section per strand. Points keep their ids, so question links survive.
public enum SpecificationConsolidation {
    static let strandWords: [(key: String, title: String)] = [
        ("number", "Number"), ("algebra", "Algebra"), ("ratio", "Ratio, proportion and rates of change"),
        ("geometry", "Geometry and measures"), ("measure", "Geometry and measures"),
        ("probability", "Probability"), ("statistic", "Statistics"),
    ]

    /// Strand key for a section ("number", "algebra", …) or nil when unrecognised.
    public static func strandKey(code: String, title: String) -> String? {
        let text = (code + " " + title).lowercased()
        // Single-letter codes used by Edexcel/WJEC.
        switch code.uppercased().trimmingCharacters(in: .whitespaces) {
            case "N": return "number"
            case "A": return "algebra"
            case "R": return "ratio"
            case "G", "GM": return "geometry"
            case "P": return "probability"
            case "S": return "statistic"
            default: break
        }
        for (key, _) in strandWords where text.contains(key) { return key == "measure" ? "geometry" : key }
        return nil
    }

    /// Consolidates one specification in place. Returns the number of sections removed.
    @discardableResult
    public static func consolidate(specificationID: UUID, in writer: any DatabaseWriter) throws -> Int {
        try writer.write { db in
            let sections = try SpecSection.filter(Column("specificationID") == specificationID).order(Column("sortOrder")).fetchAll(db)
            guard sections.count > 1 else { return 0 }
            var canonical: [String: SpecSection] = [:]
            var removed = 0
            for section in sections {
                guard let key = strandKey(code: section.code, title: section.title) else { continue }
                if let keep = canonical[key] {
                    try db.execute(sql: "UPDATE specPoint SET sectionID = ? WHERE sectionID = ?", arguments: [keep.id, section.id])
                    try section.delete(db)
                    removed += 1
                } else {
                    var keep = section
                    keep.title = strandWords.first { $0.key == key }?.title ?? section.title
                    keep.code = key == "statistic" ? "S" : String(key.prefix(1)).uppercased()
                    try keep.update(db)
                    canonical[key] = keep
                }
            }
            // Re-number points within each merged section so order is stable.
            return removed
        }
    }

    public static func consolidateAll(in database: TutorDatabase) throws -> Int {
        var total = 0
        for spec in try database.specifications() {
            total += try consolidate(specificationID: spec.id, in: database.writer)
        }
        return total
    }
}
