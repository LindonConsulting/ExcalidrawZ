//
//  LessonspaceImportCoordinator.swift
//  ExcalidrawZ
//
//  "Import MyTutor lesson": reads a Lessonspace Room Export ZIP, matches the
//  lesson to a student through the calendar, and lands the converted tabs in
//  that student's dated lesson file (appending when it already exists).
//

import Foundation
import CoreData
import LessonspaceImport
import TutorModels

/// Everything the import sheet shows before the user confirms.
struct LessonspaceImportPlan: @unchecked Sendable {
    var zipURL: URL
    var export: LessonspaceRoomExport
    var includeTemplates: Bool
    /// Calendar/student match; `nil` until detection succeeds.
    var lesson: LessonDrawPlan?
    /// Today's lesson file for the student when it already exists.
    var existingFileObjectID: NSManagedObjectID?
    var existingFileName: String?

    var selectedTabs: [LessonspaceTab] { export.tabs(includingTemplates: includeTemplates) }

    /// Converted scenes for the selected tabs (empty tabs dropped).
    var scenes: [LessonspaceTabScene] {
        selectedTabs
            .map { LessonspaceSceneBuilder.scene(for: $0, assets: export.assets) }
            .filter { !$0.items.isEmpty }
    }

    var fileName: String? { lesson?.fileName }

    /// Summarizer input over the imported content (what this lesson covered).
    var recapInput: LessonRecapInput? {
        guard let lesson else { return nil }
        let content = LessonspaceElementBuilder.build(scenes: scenes)
        guard let elements = try? content.elementDictionaries(), !elements.isEmpty else { return nil }
        let input = LessonRecapBuilder.recapInput(from: elements, student: lesson.student, subject: lesson.subject, previousLessonDate: lesson.lessonDate)
        return input.isEmpty ? nil : input
    }
}

struct LessonspaceImportOutcome {
    var fileObjectID: NSManagedObjectID
    var fileName: String
    var frameNames: [String]
    var elementCount: Int
    var didAppend: Bool
}

enum LessonspaceImportError: LocalizedError {
    case nothingToImport
    case noLesson

    var errorDescription: String? {
        switch self {
            case .nothingToImport: return "No whiteboard content to import. Turn on “Include MyTutor template tabs” if the lesson lives on one of those."
            case .noLesson: return "Pick a student before importing."
        }
    }
}

enum LessonspaceImportCoordinator {
    /// Newest Room Export ZIP in the user's Downloads folder.
    static func defaultExportURL() -> URL? {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)
        for folder in downloads {
            if let newest = LessonspaceRoomExport.roomExportZIPs(in: folder).first { return newest }
        }
        return nil
    }

    static func loadExport(at url: URL) async throws -> LessonspaceRoomExport {
        try await Task.detached(priority: .userInitiated) {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            return try LessonspaceRoomExport(zipURL: url)
        }.value
    }

    /// The lesson this export belongs to: the current calendar event, else the
    /// most recent one that ended within `lookbackHours`.
    @MainActor
    static func detectLesson(
        context: NSManagedObjectContext,
        overrideMatch: LessonTitleMatch? = nil,
        lookbackHours: Double = 48,
        now: Date = .now
    ) async throws -> LessonDrawPlan {
        let preferences = LessonDrawPreferences.shared
        let service = LessonCalendarService.shared
        var candidates = try await service.currentEvents(now: now, lookbackMinutes: preferences.lookbackMinutes)
        if candidates.isEmpty {
            candidates = try await service.events(from: now.addingTimeInterval(-lookbackHours * 3600), to: now)
                .filter { $0.startDate <= now }
                .sorted { $0.endDate > $1.endDate }
        }
        guard let event = candidates.first else { throw LessonCalendarError.noCurrentEvent }
        if let overrideMatch {
            return try await LessonDrawCoordinator.detect(context: context, preferences: preferences, overrideMatch: overrideMatch, specificEvent: event, now: now)
        }
        let parser = LessonTitleParser(pattern: preferences.titlePattern)
        for candidate in candidates {
            if (try? parser.parse(candidate.title)) != nil {
                return try await LessonDrawCoordinator.detect(context: context, preferences: preferences, specificEvent: candidate, now: now)
            }
        }
        throw LessonDrawError.titleDidNotMatch(event.title)
    }

    /// Today's lesson file for the plan's student, if Lesson Draw already created it.
    @MainActor
    static func existingLessonFile(for plan: LessonDrawPlan, context: NSManagedObjectContext) -> File? {
        guard let groupID = plan.groupObjectID, let group = context.object(with: groupID) as? Group else { return nil }
        let files = (try? PersistenceController.shared.listFiles(in: group, context: context)) ?? []
        return files
            .filter { $0.name == plan.fileName && !$0.inTrash }
            .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
            .first
    }

    @MainActor
    static func summarize(_ plan: LessonspaceImportPlan) async throws -> String? {
        guard let input = plan.recapInput else { return nil }
        guard let summarizer = await LessonRecapSummarizer.resolve() else { return nil }
        return try await summarizer.summarize(input)
    }

    /// Writes the imported frames (and optional recap text) into the lesson
    /// file, creating the group/file when needed, then records the session.
    @MainActor
    static func perform(
        _ plan: LessonspaceImportPlan,
        summary: String?,
        fileState: FileState,
        context: NSManagedObjectContext
    ) async throws -> LessonspaceImportOutcome {
        guard let lesson = plan.lesson else { throw LessonspaceImportError.noLesson }
        let scenes = plan.scenes
        guard !scenes.isEmpty else { throw LessonspaceImportError.nothingToImport }

        let repository = PersistenceController.shared.fileRepository
        var document: [String: Any]
        var origin = CGPoint.zero
        let fileObjectID: NSManagedObjectID
        var didAppend = false

        if let existingID = plan.existingFileObjectID, let file = context.object(with: existingID) as? File {
            let data = try await file.loadContent()
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw LessonRecapBuilder.BuildError.invalidPreviousFile
            }
            document = json
            let live = LessonRecapBuilder.liveElements(document["elements"] as? [[String: Any]] ?? [])
            let frames = (document["elements"] as? [[String: Any]] ?? []).filter { ($0["type"] as? String) == "frame" && $0["isDeleted"] as? Bool != true }
            let maxX = (live + frames).map { ($0["x"] as? Double ?? 0) + max(0, $0["width"] as? Double ?? 0) }.max()
            if let maxX { origin.x = maxX + LessonspaceElementBuilder.frameGap }
            fileObjectID = existingID
            didAppend = true
        } else {
            guard let templateData = ExcalidrawFile().content,
                  let json = try JSONSerialization.jsonObject(with: templateData) as? [String: Any]
            else { throw LessonRecapBuilder.BuildError.invalidTemplate }
            document = json
            let groupObjectID: NSManagedObjectID
            if let existing = lesson.groupObjectID {
                groupObjectID = existing
            } else {
                groupObjectID = try await fileState.createNewGroup(name: lesson.student, activate: false, context: context)
            }
            fileObjectID = try await repository.createFile(name: lesson.fileName, content: templateData, groupObjectID: groupObjectID)
        }

        let content = LessonspaceElementBuilder.build(scenes: scenes, origin: origin)
        var newElements = try content.elementDictionaries()
        if let summary, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            let text = LessonRecapBuilder.makeTextElement(
                text: "Recap – \(formatter.string(from: lesson.lessonDate))\n\n\(summary)",
                x: content.maxX + LessonspaceElementBuilder.frameGap / 2,
                y: origin.y
            )
            newElements.append(text)
        }

        var elements = document["elements"] as? [[String: Any]] ?? []
        elements += newElements
        document["elements"] = elements
        var files = document["files"] as? [String: Any] ?? [:]
        files.merge(try content.fileDictionaries()) { current, _ in current }
        document["files"] = files
        let fullData = try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])

        if didAppend {
            try await repository.updateElements(fileObjectID: fileObjectID, fileData: fullData, checkpoint: .userEdit(newCheckpoint: true))
        } else {
            try await repository.saveFileContentToStorage(fileObjectID: fileObjectID, content: fullData)
        }

        // Images live as media items, mirrored into the canvas's IndexedDB.
        let resources = Array(content.files.values)
        if !resources.isEmpty {
            _ = try await PersistenceController.shared.mediaItemRepository.createMediaItems(resources: resources, fileObjectID: fileObjectID)
            try? await fileState.excalidrawWebCoordinator?.insertMediaFiles(resources)
        }

        guard let file = context.object(with: fileObjectID) as? File else {
            return LessonspaceImportOutcome(fileObjectID: fileObjectID, fileName: lesson.fileName, frameNames: content.frameNames, elementCount: newElements.count, didAppend: didAppend)
        }
        file.visitedAt = .now
        try? context.save()

        let container = TutorKitContainer.shared
        if let student = try? container.ensureStudent(named: lesson.student, subjectHint: lesson.subject),
           let fileID = file.id?.uuidString {
            try? container.upsertLessonSession(student: student, lessonFileID: fileID, date: lesson.lessonDate, subjectLine: lesson.subject ?? "", recap: summary)
        }

        if didAppend, fileState.currentActiveFile?.id == FileState.ActiveFile.file(file).id {
            if let refreshed = try? ExcalidrawFile(data: fullData, id: FileState.ActiveFile.file(file).id) {
                await fileState.excalidrawWebCoordinator?.loadFile(from: refreshed, force: true)
            }
        } else {
            if let group = file.group {
                fileState.currentActiveGroup = .group(group)
                fileState.expandToGroup(group.objectID)
            }
            _ = await fileState.requestActiveFileChange(.file(file))
        }

        return LessonspaceImportOutcome(fileObjectID: fileObjectID, fileName: lesson.fileName, frameNames: content.frameNames, elementCount: newElements.count, didAppend: didAppend)
    }
}
