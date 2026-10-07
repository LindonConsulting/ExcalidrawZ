import Foundation
import TutorModels

/// Turns the text of an exam specification into a `SpecificationDraft` using
/// the Messages API, chunk by chunk, merging the results.
public struct SpecificationImporter: Sendable {
    public var client: AnthropicMessagesClient
    public var chunkCharacters = 12_000

    public init(client: AnthropicMessagesClient) {
        var client = client
        client.maxTokens = 16_000
        client.effort = "medium"
        client.timeout = 600
        self.client = client
    }

    public static let system = """
    You extract the assessable content from UK exam specifications (GCSE / A-Level Maths, Computer Science, Biology, Chemistry, Physics and Combined Science; boards AQA, Edexcel/Pearson, OCR, WJEC/Eduqas, CCEA). \
    Return JSON only, no prose, matching exactly:
    {"title": string, "code": string (board qualification code such as "1MA1", "8300", "J560", "H240", "8525"; "" if unknown),
     "subject": "Maths" | "Computer Science" | "Biology" | "Chemistry" | "Physics" | "Combined Science", "level": "GCSE" | "A-Level" | "KS3" | "Other", "board": string,
     "sections": [{"code": string, "title": string, "points": [{"code": string, "text": string, "tier": "Higher" | "Foundation" | null}]}]}
    Rules: one point per numbered/lettered statement exactly as the specification numbers them (e.g. "N1", "A4", "3.1.1", "1.2.3", "1.5B", "SP1.3"). \
    For science specifications a section is a topic (e.g. "Topic 1 – Key concepts in biology") and the points are the numbered statements in it; mark "Higher Tier only" statements (often printed in bold or flagged) with "tier":"Higher". \
    Keep the statement text verbatim but trimmed, without the bold/underline markers and without repeated headers or page furniture. \
    If content is marked higher-tier only (bold text in Edexcel/AQA GCSE Maths, "Higher only", "H"), set "tier":"Higher". \
    GCSE Maths specifications often list the Foundation tier content and then the Higher tier content again under the same codes with extra statements: \
    emit Foundation-section statements with "tier":"Foundation" and Higher-section statements with "tier":"Higher" (same codes are fine); \
    when a Higher statement merely repeats the Foundation one, still include it so each tier has its full list. \
    Use the section code without the tier (e.g. "1", "A") and a tier-free section title. \
    Ignore assessment objectives, introductions, formulae sheets, guidance for teachers and appendices. \
    If this chunk contains no assessable content, return {"title":"","code":"","subject":"","level":"","board":"","sections":[]}.
    """

    /// Splits `pages` into chunks (never splitting a page), calls the model per chunk, merges.
    public func importSpecification(pages: [String], progress: (@Sendable (Int, Int) -> Void)? = nil) async throws -> SpecificationDraft {
        let chunks = Self.chunk(pages: pages, maxCharacters: chunkCharacters)
        var draft = SpecificationDraft(title: "", code: "", subject: "", level: "", board: "", sections: [])
        for (index, chunk) in chunks.enumerated() {
            progress?(index, chunks.count)
            let user = "Specification text, chunk \(index + 1) of \(chunks.count):\n\n\(chunk)"
            let reply = try await client.complete(system: Self.system, user: [.text(user)])
            let part = try AnthropicMessagesClient.decodeJSONObject(SpecificationDraft.self, from: reply)
            draft.merge(part)
        }
        progress?(chunks.count, chunks.count)
        return draft
    }

    public static func chunk(pages: [String], maxCharacters: Int) -> [String] {
        var chunks: [String] = []
        var current = ""
        for page in pages {
            let trimmed = page.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if !current.isEmpty, current.count + trimmed.count > maxCharacters {
                chunks.append(current)
                current = ""
            }
            current += (current.isEmpty ? "" : "\n\n") + trimmed
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }
}
