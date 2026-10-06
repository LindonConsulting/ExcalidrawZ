import Foundation
import TutorModels

/// Chooses warm-up questions for a student. Phase 1 ships a simple
/// never-repeat picker; Phase 5 replaces the scoring.
public struct QuestionPickerRequest: Sendable {
    public var student: Student?
    public var count: Int
    public var preferredTopicIDs: [String]
    public var now: Date

    public init(student: Student?, count: Int = 3, preferredTopicIDs: [String] = [], now: Date = .now) {
        self.student = student; self.count = count; self.preferredTopicIDs = preferredTopicIDs; self.now = now
    }
}

public protocol QuestionPicking: Sendable {
    func pick(from questions: [Question], outcomes: [UUID: [Outcome]], request: QuestionPickerRequest) -> [Question]
}

public struct NeverRepeatPicker: QuestionPicking {
    public init() {}

    public func pick(from questions: [Question], outcomes: [UUID: [Outcome]], request: QuestionPickerRequest) -> [Question] {
        let studentID = request.student?.id
        let studentName = request.student?.name.lowercased()
        let unseen = questions.filter { question in
            guard question.archivedAt == nil else { return false }
            let seen = outcomes[question.id] ?? []
            return !seen.contains { outcome in
                (studentID != nil && outcome.studentID == studentID)
                    || (studentName != nil && outcome.studentName.lowercased() == studentName)
            }
        }
        let preferred = Set(request.preferredTopicIDs)
        let ranked = unseen.sorted { lhs, rhs in
            let l = lhs.topicIDs.contains(where: preferred.contains) ? 1 : 0
            let r = rhs.topicIDs.contains(where: preferred.contains) ? 1 : 0
            if l != r { return l > r }
            return lhs.createdAt > rhs.createdAt
        }
        return Array(ranked.prefix(request.count))
    }
}
