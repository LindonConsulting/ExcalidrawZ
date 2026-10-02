//
//  LessonDrawCoordinator.swift
//  ExcalidrawZ
//
//  Orchestrates "New Lesson Draw": calendar → student → group → previous
//  lesson → recap → new file.
//

import Foundation
import CoreData

struct LessonDrawPlan: @unchecked Sendable {
    var event: LessonCalendarEvent
    var match: LessonTitleMatch
    var student: String { match.student }
    var subject: String? { match.subject }
    /// Existing group for the student, or `nil` when one must be created.
    var groupObjectID: NSManagedObjectID?
    var previousFileObjectID: NSManagedObjectID?
    var previousFileName: String?
    var previousLessonDate: Date?
    var previousElements: [[String: Any]]
    var lessonDate: Date

    var fileName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        var name = "\(formatter.string(from: lessonDate)) \(student)"
        if let subject { name += " – \(subject)" }
        return name
    }

    var recapInput: LessonRecapInput? {
        guard let previousLessonDate else { return nil }
        return LessonRecapBuilder.recapInput(
            from: previousElements,
            student: student,
            subject: subject,
            previousLessonDate: previousLessonDate
        )
    }
}

enum LessonDrawError: LocalizedError {
    case titleDidNotMatch(String)

    var errorDescription: String? {
        switch self {
            case .titleDidNotMatch(let title):
                return "The current event “\(title)” does not match the lesson title pattern. Adjust it in Settings → Lessons, or enter the student below."
        }
    }
}

enum LessonDrawCoordinator {
    /// Detects the current lesson and everything needed to create its file.
    /// `overrideMatch` lets the UI supply a student when the title rule fails.
    @MainActor
    static func detect(
        context: NSManagedObjectContext,
        preferences: LessonDrawPreferences? = nil,
        overrideMatch: LessonTitleMatch? = nil,
        now: Date = .now
    ) async throws -> LessonDrawPlan {
        let preferences = preferences ?? LessonDrawPreferences.shared
        let events = try await LessonCalendarService.shared.currentEvents(now: now, lookbackMinutes: preferences.lookbackMinutes)
        let parser = LessonTitleParser(pattern: preferences.titlePattern)

        var chosen: (LessonCalendarEvent, LessonTitleMatch)?
        if let overrideMatch, let first = events.first {
            chosen = (first, overrideMatch)
        } else {
            for event in events {
                if let match = try parser.parse(event.title) {
                    chosen = (event, match)
                    break
                }
            }
        }
        guard let (event, match) = chosen else {
            if let first = events.first { throw LessonDrawError.titleDidNotMatch(first.title) }
            throw LessonCalendarError.noCurrentEvent
        }

        var plan = LessonDrawPlan(
            event: event,
            match: match,
            groupObjectID: nil,
            previousFileObjectID: nil,
            previousFileName: nil,
            previousLessonDate: nil,
            previousElements: [],
            lessonDate: now
        )

        if let group = try findGroup(named: match.student, context: context) {
            plan.groupObjectID = group.objectID
            let files = try PersistenceController.shared.listFiles(in: group, context: context)
                .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
            if let previous = files.first {
                plan.previousFileObjectID = previous.objectID
                plan.previousFileName = previous.name
                plan.previousLessonDate = previous.createdAt ?? previous.updatedAt ?? now
                let data = try await previous.loadContent()
                plan.previousElements = try LessonRecapBuilder.elements(from: data)
            }
        }
        return plan
    }

    @MainActor
    static func findGroup(named name: String, context: NSManagedObjectContext) throws -> Group? {
        let request = NSFetchRequest<Group>(entityName: "Group")
        request.predicate = NSPredicate(format: "name ==[c] %@ AND parent == nil AND type != %@", name, Group.GroupType.trash.rawValue)
        request.sortDescriptors = [.init(key: "createdAt", ascending: true)]
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    /// Runs the recap summarizer. Returns `nil` when no backend is available
    /// or there is no previous lesson.
    @MainActor
    static func summarize(_ plan: LessonDrawPlan) async throws -> String? {
        guard let input = plan.recapInput else { return nil }
        guard let summarizer = await LessonRecapSummarizer.resolve() else { return nil }
        return try await summarizer.summarize(input)
    }

    /// Creates the group (if needed) and the lesson file, then opens it.
    @MainActor
    @discardableResult
    static func createLessonFile(
        plan: LessonDrawPlan,
        summary: String?,
        fileState: FileState,
        context: NSManagedObjectContext
    ) async throws -> NSManagedObjectID {
        let groupObjectID: NSManagedObjectID
        if let existing = plan.groupObjectID {
            groupObjectID = existing
        } else {
            groupObjectID = try await fileState.createNewGroup(name: plan.student, activate: false, context: context)
        }

        let content = try LessonRecapBuilder.buildFileContent(
            previousElements: plan.previousElements,
            previousLessonDate: plan.previousLessonDate,
            summary: summary
        )
        let fileObjectID = try await PersistenceController.shared.fileRepository.createFile(
            name: plan.fileName,
            content: content,
            groupObjectID: groupObjectID
        )

        guard let file = context.object(with: fileObjectID) as? File else { return fileObjectID }
        file.visitedAt = .now
        try? context.save()
        if let group = file.group {
            fileState.currentActiveGroup = .group(group)
            fileState.expandToGroup(group.objectID)
        }
        _ = await fileState.requestActiveFileChange(.file(file))
        return fileObjectID
    }
}
