//
//  StudentDetailSheet.swift
//  ExcalidrawZ
//
//  Per-student view: profile summary and lesson history.
//

import SwiftUI
import ChocofordUI
import TutorModels
import TutorStore

struct StudentDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var container = TutorKitContainer.shared

    let studentID: UUID
    @State private var isEditing = false

    private var student: Student? { container.students.first { $0.id == studentID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let student {
                header(student)
                Divider()
                lessonHistory(student)
            } else {
                Text("Student not found.").foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(minWidth: 640, minHeight: 480)
        .sheet(isPresented: $isEditing) {
            if let student { StudentEditSheet(student: student) }
        }
    }

    @ViewBuilder
    private func header(_ student: Student) -> some View {
        let stats = container.stats(for: student)
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(student.name).font(.title2.bold())
                let enrolment = container.primaryEnrolment(for: student)
                Text([container.courseSummary(for: student), (enrolment?.targetGrade).flatMap { $0.isEmpty ? nil : "Target \($0)" }]
                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .foregroundStyle(.secondary)
                let others = container.enrolments(for: student).filter { $0.id != enrolment?.id }
                if !others.isEmpty {
                    Text("Also: " + others.map(\.courseName).joined(separator: ", ")).font(.callout).foregroundStyle(.secondary)
                }
                HStack(spacing: 14) {
                    Label("\(stats.lessons) lessons", systemSymbol: .calendar)
                    if let last = stats.lastLesson {
                        Label("Last \(last.formatted(date: .abbreviated, time: .omitted))", systemSymbol: .clock)
                    }
                }
                .font(.callout).foregroundStyle(.secondary)
                let profile = [student.yearGroup, student.school, student.management].filter { !$0.isEmpty }.joined(separator: " · ")
                if !profile.isEmpty { Text(profile).font(.callout).foregroundStyle(.secondary) }
                if let contact = container.contacts(for: student).first, !contact.summary.isEmpty {
                    Label(contact.summary + (contact.preferredMethod.isEmpty ? "" : " (\(contact.preferredMethod))"), systemSymbol: .personCropCircle)
                        .font(.callout).foregroundStyle(.secondary)
                }
                if !student.notes.isEmpty { Text(student.notes).font(.callout) }
                if !student.rapportNotes.isEmpty { Text(student.rapportNotes).font(.callout).foregroundStyle(.secondary) }
                let focus = container.focusTopicIDs(for: student)
                if !focus.isEmpty {
                    Text("Focus: " + focus.map(container.topicName).joined(separator: ", ")).font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Edit…") { isEditing = true }
        }
    }

    @ViewBuilder
    private func lessonHistory(_ student: Student) -> some View {
        let lessons = container.lessons(for: student)
        VStack(alignment: .leading, spacing: 8) {
            Text("Lessons").font(.headline)
            if lessons.isEmpty {
                Text("No lessons recorded yet. New Lesson Draw adds one for each lesson file.")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(lessons) { lesson in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 8) {
                                    Text(lesson.startAt.formatted(date: .abbreviated, time: .shortened)).font(.subheadline.bold())
                                    if !lesson.subjectLine.isEmpty {
                                        Text(lesson.subjectLine).font(.subheadline).foregroundStyle(.secondary)
                                    }
                                    if lesson.status != .done {
                                        Text(lesson.status.rawValue.capitalized).font(.caption).foregroundStyle(.orange)
                                    }
                                }
                                if let recap = lesson.recap, !recap.isEmpty {
                                    Text(recap).font(.callout).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.06)))
                        }
                    }
                    .padding(.trailing, 8)
                }
            }
        }
    }
}
