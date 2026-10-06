import Foundation

/// Qualification level a student is working towards.
public enum QualificationLevel: String, Codable, CaseIterable, Sendable, Identifiable {
    case ks3 = "KS3"
    case gcse = "GCSE"
    case aLevel = "A-Level"
    case other = "Other"

    public var id: String { rawValue }
}

/// Subject taught. Topic taxonomies are keyed by subject + level.
public enum Subject: String, Codable, CaseIterable, Sendable, Identifiable {
    case maths = "Maths"
    case computerScience = "Computer Science"
    case other = "Other"

    public var id: String { rawValue }
}

public enum ExamBoard: String, Codable, CaseIterable, Sendable, Identifiable {
    case aqa = "AQA", edexcel = "Edexcel", ocr = "OCR", wjec = "WJEC", ccea = "CCEA", cambridge = "Cambridge", other = "Other"
    public var id: String { rawValue }
}

public enum Tier: String, Codable, CaseIterable, Sendable, Identifiable {
    case foundation = "Foundation", higher = "Higher", notApplicable = "N/A"
    public var id: String { rawValue }
}
