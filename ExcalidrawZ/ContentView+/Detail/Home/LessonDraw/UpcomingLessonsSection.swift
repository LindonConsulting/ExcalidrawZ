//
//  UpcomingLessonsSection.swift
//  ExcalidrawZ
//
//  Home-page list of the next week's lessons from the Mac Calendar (Google
//  calendars sync into it), with the matched student and a Draw button.
//

import SwiftUI
import TutorModels

struct UpcomingLessonsSection: View {
    @ObservedObject private var preferences = LessonDrawPreferences.shared
    @ObservedObject private var container = TutorKitContainer.shared

    @State private var events: [LessonCalendarEvent] = []
    @State private var error: String?
    @State private var isLoading = true
    @State private var drawEvent: LessonCalendarEvent?
    @State private var detailStudent: Student?
    @State private var days = 7

    private struct Row: Identifiable {
        var event: LessonCalendarEvent
        var match: LessonTitleMatch?
        var student: Student?
        var id: String { event.id }
    }

    private var rows: [Row] {
        let parser = LessonTitleParser(pattern: preferences.titlePattern)
        return events.map { event in
            let match = try? parser.parse(event.title)
            let student = match.flatMap { m in container.students.first { $0.name.caseInsensitiveCompare(m.student) == .orderedSame } }
            return Row(event: event, match: match, student: student)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemSymbol: .calendar)
                Text("Upcoming lessons")
                Spacer()
                Picker("", selection: $days) {
                    Text("Today").tag(1)
                    Text("7 days").tag(7)
                    Text("14 days").tag(14)
                }
                .pickerStyle(.segmented).frame(width: 220)
                .onChange(of: days) { _ in Task { await load() } }
                Button { Task { await load() } } label: { Image(systemSymbol: .arrowClockwise) }
                    .controlSize(.small)
            }
            .font(.headline)

            if let error {
                Text(error).font(.callout).foregroundStyle(.secondary)
            } else if isLoading {
                ProgressView().controlSize(.small)
            } else if rows.isEmpty {
                Text("Nothing in the calendar for the next \(days == 1 ? "day" : "\(days) days").")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 6) {
                    ForEach(rows) { row in rowView(row) }
                }
            }
        }
        .task { await load() }
        .onAppear { container.openIfNeeded() }
        .sheet(item: $drawEvent) { event in NewLessonDrawSheet(event: event) }
        .sheet(item: $detailStudent) { student in StudentDetailSheet(studentID: student.id) }
    }

    @ViewBuilder
    private func rowView(_ row: Row) -> some View {
        let isLesson = row.match != nil
        let isNow = row.event.startDate <= .now && row.event.endDate >= .now
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(row.event.startDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    .font(.caption).foregroundStyle(.secondary)
                Text(row.event.startDate.formatted(date: .omitted, time: .shortened) + "–" + row.event.endDate.formatted(date: .omitted, time: .shortened))
                    .font(.callout.monospacedDigit())
            }
            .frame(width: 110, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.match?.student ?? row.event.title).font(.headline).lineLimit(1)
                    if isNow {
                        Text("NOW").font(.caption2.bold()).padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.green.opacity(0.2), in: Capsule()).foregroundStyle(.green)
                    }
                }
                if let subject = row.match?.subject {
                    Text(subject).font(.caption).foregroundStyle(.secondary)
                } else if !isLesson {
                    Text("Not a lesson (title doesn't match the pattern)").font(.caption).foregroundStyle(.tertiary)
                }
            }
            Spacer()

            if let student = row.student {
                let stats = container.stats(for: student)
                VStack(alignment: .trailing, spacing: 2) {
                    if let coverage = stats.coverage {
                        Text("\(coverage.total - coverage.count(.notCovered))/\(coverage.total) covered").font(.caption).foregroundStyle(.secondary)
                    }
                    if stats.pendingOutcomes > 0 {
                        Text("\(stats.pendingOutcomes) to record").font(.caption).foregroundStyle(.orange)
                    }
                    if let last = stats.lastLesson {
                        Text("Last: \(last.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Button("Student") { detailStudent = student }.controlSize(.small)
            } else if isLesson {
                Text("New student").font(.caption).foregroundStyle(.secondary)
            }
            if isLesson {
                Button { drawEvent = row.event } label: { Label("Draw", systemSymbol: .pencilAndOutline) }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(isNow ? Color.green.opacity(0.08) : Color.secondary.opacity(0.08)))
        .opacity(isLesson ? 1 : 0.6)
    }

    private func load() async {
        isLoading = true
        error = nil
        do {
            events = try await LessonCalendarService.shared.upcomingEvents(days: days)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}
