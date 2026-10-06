//
//  QuestionTagSuggester.swift
//  ExcalidrawZ
//
//  AI tag suggestions for a captured question (Claude vision via TutorAI).
//

import Foundation
import TutorAI
import TutorModels

typealias QuestionTagSuggestion = TutorPrompts.TagSuggestion

struct QuestionTagSuggester {
    let client: AnthropicMessagesClient
    let topics: [Topic]

    @MainActor
    static func make(topics: [Topic]) throws -> QuestionTagSuggester {
        guard let client = try AnthropicAPIKeyStore.makeClient() else { throw TutorAIError.noAPIKey }
        return QuestionTagSuggester(client: client, topics: topics)
    }

    func suggest(thumbnailPNG: Data?, texts: [String]) async throws -> QuestionTagSuggestion {
        var parts: [AnthropicMessagesClient.ContentPart] = []
        if let thumbnailPNG { parts.append(.imagePNG(thumbnailPNG)) }
        parts.append(.text(TutorPrompts.taggingUser(texts: texts, topics: topics)))
        let reply = try await client.complete(system: nil, user: parts)
        return try AnthropicMessagesClient.decodeJSONObject(QuestionTagSuggestion.self, from: reply)
    }

    /// Applies a suggestion onto a question, only filling blanks unless `overwriteTitle`.
    static func apply(_ s: QuestionTagSuggestion, to question: inout Question, topics: [Topic], overwriteTitle: Bool) {
        if let title = s.title, !title.isEmpty, overwriteTitle || question.title.isEmpty { question.title = title }
        for raw in s.topics ?? [] {
            if let topic = TopicTaxonomy.resolve(raw, in: topics), topic.parentID != nil {
                if !question.topicIDs.contains(topic.id) { question.topicIDs.append(topic.id) }
            } else if !raw.isEmpty, !question.freeTags.contains(raw) {
                question.freeTags.append(raw)
            }
        }
        if let subject = s.subject.flatMap(Subject.init(rawValue:)) { question.subject = subject }
        if question.level == nil, let level = s.level.flatMap(QualificationLevel.init(rawValue:)) { question.level = level }
        if question.board == nil, let board = s.board.flatMap(ExamBoard.init(rawValue:)) { question.board = board }
        if question.tier == nil, let tier = s.tier.flatMap(Tier.init(rawValue:)) { question.tier = tier }
        if question.marks == nil { question.marks = s.marks }
        if question.difficulty == nil, let d = s.difficulty { question.difficulty = min(max(d, 1), 5) }
        if question.source.isEmpty, let source = s.source { question.source = source }
    }
}
