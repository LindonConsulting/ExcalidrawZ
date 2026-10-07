//
//  StudentRoster.swift
//  ExcalidrawZ
//
//  The calendar is the source of truth for who is a student: anyone with a
//  lesson in the window. Built from EventKit via the lesson title pattern.
//

import Foundation

struct RosterEntry: Identifiable, Sendable {
    var name: String
    var subjects: [String]
    var pastLessons: Int
    var upcomingLessons: Int
    var lastLesson: Date?
    var nextLesson: Date?
    var id: String { name.lowercased() }

    var isActive: Bool { pastLessons + upcomingLessons > 0 }
}

enum StudentRosterBuilder {
    /// Lessons from `weeksBack` weeks ago to `weeksAhead` weeks ahead, grouped by student.
    static func build(weeksBack: Int = 8, weeksAhead: Int = 8, pattern: String, now: Date = .now) async throws -> [RosterEntry] {
        let service = LessonCalendarService.shared
        guard try await service.requestAccess() else { throw LessonCalendarError.accessDenied }
        let start = now.addingTimeInterval(-Double(weeksBack) * 7 * 86_400)
        let end = now.addingTimeInterval(Double(weeksAhead) * 7 * 86_400)
        let events = try await service.events(from: start, to: end)
        let parser = LessonTitleParser(pattern: pattern)
        var byName: [String: RosterEntry] = [:]
        for event in events {
            guard let match = try? parser.parse(event.title) else { continue }
            let key = match.student.lowercased()
            var entry = byName[key] ?? RosterEntry(name: match.student, subjects: [], pastLessons: 0, upcomingLessons: 0, lastLesson: nil, nextLesson: nil)
            if let subject = match.subject, !entry.subjects.contains(subject) { entry.subjects.append(subject) }
            if event.endDate <= now {
                entry.pastLessons += 1
                if entry.lastLesson.map({ event.startDate > $0 }) ?? true { entry.lastLesson = event.startDate }
            } else {
                entry.upcomingLessons += 1
                if entry.nextLesson.map({ event.startDate < $0 }) ?? true { entry.nextLesson = event.startDate }
            }
            byName[key] = entry
        }
        return byName.values.sorted { ($0.nextLesson ?? .distantFuture, $0.name) < ($1.nextLesson ?? .distantFuture, $1.name) }
    }
}
