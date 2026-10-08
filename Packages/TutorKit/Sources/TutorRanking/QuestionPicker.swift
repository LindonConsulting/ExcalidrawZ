import Foundation
import TutorModels

/// Chooses warm-up questions for a student. `NeverRepeatPicker` is the simple
/// fallback; `CoveragePicker` does the real scoring.
public struct QuestionPickerRequest: Sendable {
    public var studentID: UUID?
    public var count: Int
    public var preferredTopicIDs: [String]
    public var now: Date

    public init(studentID: UUID?, count: Int = 3, preferredTopicIDs: [String] = [], now: Date = .now) {
        self.studentID = studentID; self.count = count; self.preferredTopicIDs = preferredTopicIDs; self.now = now
    }
}

public protocol QuestionPicking: Sendable {
    func pick(from questions: [Question], outcomes: [UUID: [Outcome]], request: QuestionPickerRequest) -> [Question]
}

public struct NeverRepeatPicker: QuestionPicking {
    public init() {}

    public func pick(from questions: [Question], outcomes: [UUID: [Outcome]], request: QuestionPickerRequest) -> [Question] {
        let studentID = request.studentID
        let unseen = questions.filter { question in
            guard question.deletedAt == nil else { return false }
            guard let studentID else { return true }
            return !(outcomes[question.id] ?? []).contains { $0.studentID == studentID }
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
