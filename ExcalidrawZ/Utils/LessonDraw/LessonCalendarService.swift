//
//  LessonCalendarService.swift
//  ExcalidrawZ
//
//  Finds the lesson happening now in the Mac Calendar via EventKit.
//

import Foundation
import EventKit

struct LessonCalendarEvent: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var startDate: Date
    var endDate: Date
    var calendarTitle: String
}

enum LessonCalendarError: LocalizedError {
    case accessDenied
    case noCurrentEvent

    var errorDescription: String? {
        switch self {
            case .accessDenied:
                return "ExcalidrawZ does not have access to your calendars. Allow it in System Settings → Privacy & Security → Calendars."
            case .noCurrentEvent:
                return "No calendar event is happening right now."
        }
    }
}

final class LessonCalendarService: @unchecked Sendable {
    static let shared = LessonCalendarService()

    private let store = EKEventStore()

    /// Requests full (read) access, returning `true` when granted.
    func requestAccess() async throws -> Bool {
        if #available(macOS 14.0, iOS 17.0, *) {
            return try await store.requestFullAccessToEvents()
        } else {
            return try await withCheckedThrowingContinuation { continuation in
                store.requestAccess(to: .event) { granted, error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: granted) }
                }
            }
        }
    }

    /// Events overlapping `now`, allowing `lookbackMinutes` before an event's
    /// start. Sorted so the best candidate comes first: events already in
    /// progress before upcoming ones, then by nearest start.
    func currentEvents(now: Date = .now, lookbackMinutes: Int) async throws -> [LessonCalendarEvent] {
        guard try await requestAccess() else { throw LessonCalendarError.accessDenied }

        let windowStart = now.addingTimeInterval(-12 * 3600)
        let windowEnd = now.addingTimeInterval(TimeInterval(lookbackMinutes * 60))
        let predicate = store.predicateForEvents(withStart: windowStart, end: windowEnd, calendars: nil)
        let events = store.events(matching: predicate)

        let candidates = events.filter { event in
            guard !event.isAllDay,
                  let start = event.startDate,
                  let end = event.endDate,
                  let title = event.title, !title.trimmingCharacters(in: .whitespaces).isEmpty
            else { return false }
            let effectiveStart = start.addingTimeInterval(-TimeInterval(lookbackMinutes * 60))
            return effectiveStart <= now && now <= end
        }
        .sorted { lhs, rhs in
            let lhsStarted = lhs.startDate <= now
            let rhsStarted = rhs.startDate <= now
            if lhsStarted != rhsStarted { return lhsStarted }
            return abs(lhs.startDate.timeIntervalSince(now)) < abs(rhs.startDate.timeIntervalSince(now))
        }

        return candidates.map {
            LessonCalendarEvent(
                id: $0.eventIdentifier ?? UUID().uuidString,
                title: $0.title ?? "",
                startDate: $0.startDate,
                endDate: $0.endDate,
                calendarTitle: $0.calendar?.title ?? ""
            )
        }
    }
}
