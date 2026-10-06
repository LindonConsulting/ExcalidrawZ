import Foundation
import TutorModels

/// Everything the picker needs about one student, precomputed by the caller.
public struct PickerContext: Sendable {
    public var student: Student?
    /// spec point id → status for this student (empty when no spec is linked)
    public var coverage: [UUID: CoverageStatus]
    /// question id → spec point ids
    public var specPointsByQuestion: [UUID: [UUID]]
    /// spec point id → tier restriction
    public var specPointTiers: [UUID: Tier?]
    public var outcomes: [UUID: [Outcome]]
    public var now: Date

    public init(student: Student?, coverage: [UUID: CoverageStatus] = [:], specPointsByQuestion: [UUID: [UUID]] = [:],
                specPointTiers: [UUID: Tier?] = [:], outcomes: [UUID: [Outcome]] = [:], now: Date = .now) {
        self.student = student; self.coverage = coverage; self.specPointsByQuestion = specPointsByQuestion
        self.specPointTiers = specPointTiers; self.outcomes = outcomes; self.now = now
    }
}

/// Picks warm-up questions by specification coverage: prefers spec points the
/// student got wrong or never met, then focus topics, never repeats a question
/// for the student, and mixes difficulty.
public struct CoveragePicker: Sendable {
    public var count: Int

    public init(count: Int = 3) { self.count = count }

    public struct Scored: Sendable {
        public var question: Question
        public var score: Double
        public var reason: String
    }

    public func rank(_ questions: [Question], context: PickerContext) -> [Scored] {
        let student = context.student
        let focus = Set(student?.focusTopicIDs ?? [])
        var scored: [Scored] = []
        for question in questions where question.archivedAt == nil {
            // Never repeat for this student.
            let seen = (context.outcomes[question.id] ?? []).contains { outcome in
                (student != nil && outcome.studentID == student!.id)
                    || (student != nil && outcome.studentName.caseInsensitiveCompare(student!.name) == .orderedSame)
            }
            if seen { continue }
            // Subject/level/tier fit.
            if let student {
                if question.subject != student.subject { continue }
                if let level = question.level, level != student.level { continue }
                if student.level == .gcse, let tier = question.tier, let studentTier = student.tier, tier != .notApplicable, tier != studentTier { continue }
            }

            var score = 1.0
            var reasons: [String] = []
            let points = context.specPointsByQuestion[question.id] ?? []
            var pointScore = 0.0
            for point in points {
                if let tier = context.specPointTiers[point] ?? nil, let studentTier = student?.tier, tier != studentTier { continue }
                switch context.coverage[point] ?? .notCovered {
                    case .wrong: pointScore += 5; reasons.append("got this wrong before")
                    case .partial: pointScore += 4; reasons.append("partly right before")
                    case .notCovered: pointScore += 3; reasons.append("spec point not covered yet")
                    case .shown: pointScore += 1
                    case .right: pointScore += 0.25
                }
            }
            score += pointScore
            if !focus.isEmpty, question.topicIDs.contains(where: focus.contains) { score += 3; reasons.append("focus topic") }
            // Mild preference for mid difficulty so a warm-up isn't three hard ones.
            if let d = question.difficulty { score += d == 3 ? 0.5 : (d == 2 || d == 4 ? 0.25 : 0) }
            // Slight preference for recently added material.
            let ageDays = context.now.timeIntervalSince(question.createdAt) / 86_400
            score += max(0, 0.5 - ageDays / 365)
            scored.append(Scored(question: question, score: score, reason: reasons.first ?? "not yet shown to this student"))
        }
        return scored.sorted { $0.score > $1.score }
    }

    /// Top `count`, avoiding more than one question per spec point and spreading difficulty.
    public func pick(_ questions: [Question], context: PickerContext) -> [Scored] {
        var picked: [Scored] = []
        var usedPoints = Set<UUID>()
        var usedDifficulties: [Int] = []
        for candidate in rank(questions, context: context) {
            let points = Set(context.specPointsByQuestion[candidate.question.id] ?? [])
            if !points.isEmpty, !points.isDisjoint(with: usedPoints), picked.count < count { continue }
            if let d = candidate.question.difficulty, usedDifficulties.filter({ $0 == d }).count >= 2 { continue }
            picked.append(candidate)
            usedPoints.formUnion(points)
            if let d = candidate.question.difficulty { usedDifficulties.append(d) }
            if picked.count == count { break }
        }
        // Fill up if the diversity rules left gaps.
        if picked.count < count {
            let ids = Set(picked.map(\.question.id))
            for candidate in rank(questions, context: context) where !ids.contains(candidate.question.id) {
                picked.append(candidate)
                if picked.count == count { break }
            }
        }
        return picked
    }
}
