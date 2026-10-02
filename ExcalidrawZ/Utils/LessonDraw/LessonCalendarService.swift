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

struct LessonCalendarLookup: Sendable {
    var events: [LessonCalendarEvent]
    /// `true` when nothing is happening now and `events` are the next upcoming ones.
    var isUpcoming: Bool
}

enum LessonCalendarError: LocalizedError {
    case accessDenied
    case noCurrentEvent

    var errorDescription: String? {
        switch self {
            case .accessDenied:
                return "ExcalidrawZ does not have access to your calendars. Allow it in System Settings → Privacy & Security → Calendars."
            case .noCurrentEvent:
                return "No calendar event is happening now or in the next 7 days."
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

    /// Events happening now (see `currentEvents`); when there are none, the
    /// next upcoming events within `upcomingDays`, earliest first.
    func lessonEvents(now: Date = .now, lookbackMinutes: Int, upcomingDays: Int = 7) async throws -> LessonCalendarLookup {
        let current = try await currentEvents(now: now, lookbackMinutes: lookbackMinutes)
        if !current.isEmpty { return LessonCalendarLookup(events: current, isUpcoming: false) }

        let predicate = store.predicateForEvents(
            withStart: now,
            end: now.addingTimeInterval(TimeInterval(upcomingDays) * 86_400),
            calendars: nil
        )
        let upcoming = store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.startDate > now && !($0.title ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
            .sorted { $0.startDate < $1.startDate }
            .map(Self.lessonEvent)
        return LessonCalendarLookup(events: upcoming, isUpcoming: true)
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

        return candidates.map(Self.lessonEvent)
    }

    private static func lessonEvent(_ event: EKEvent) -> LessonCalendarEvent {
        LessonCalendarEvent(
            id: event.eventIdentifier ?? UUID().uuidString,
            title: event.title ?? "",
            startDate: event.startDate,
            endDate: event.endDate,
            calendarTitle: event.calendar?.title ?? ""
        )
    }
}
