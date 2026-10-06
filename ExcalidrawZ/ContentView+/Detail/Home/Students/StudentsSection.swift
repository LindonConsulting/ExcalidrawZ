//
//  StudentsSection.swift
//  ExcalidrawZ
//
//  Home-page section listing tutoring students (TutorKit), with add/edit.
//

import SwiftUI
import CoreData
import TutorModels

struct StudentsSection: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.alertToast) private var alertToast
    @EnvironmentObject private var fileState: FileState
    @ObservedObject private var container = TutorKitContainer.shared

    @State private var editingStudent: Student?
    @State private var detailStudent: Student?
    @State private var isAddingStudent = false
    @State private var isSpecificationsPresented = false

    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemSymbol: .person2)
                Text("Students")
                Spacer()
                Button { isSpecificationsPresented = true } label: { Label("Specifications…", systemSymbol: .listBulletRectangle) }
                    .controlSize(.small)
                Button { isAddingStudent = true } label: { Label("Add student", systemSymbol: .plus) }
                    .controlSize(.small)
            }
            .font(.headline)

            if container.students.isEmpty {
                Text("No students yet. Add one, or run New Lesson Draw and the student is created from the calendar event.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    ForEach(container.students) { student in
                        StudentCard(student: student, stats: container.stats(for: student))
                            .onTapGesture { detailStudent = student }
                            .contextMenu {
                                Button("Edit…") { editingStudent = student }
                                Button("Open group") { openGroup(named: student.name) }
                                Divider()
                                Button("Archive", role: .destructive) { archive(student) }
                            }
                    }
                }
            }
        }
        .onAppear { container.openIfNeeded() }
        .sheet(item: $editingStudent) { student in StudentEditSheet(student: student) }
        .sheet(isPresented: $isAddingStudent) { StudentEditSheet(student: nil) }
        .sheet(item: $detailStudent) { student in StudentDetailSheet(studentID: student.id) }
        .sheet(isPresented: $isSpecificationsPresented) { SpecificationsSheet() }
    }

    private func archive(_ student: Student) {
        var copy = student
        copy.archivedAt = .now
        do { try container.save(copy) } catch { alertToast(error) }
    }

    private func openGroup(named name: String) {
        if let group = try? LessonDrawCoordinator.findGroup(named: name, context: viewContext) {
            fileState.currentActiveGroup = .group(group)
            fileState.expandToGroup(group.objectID)
        }
    }
}

struct StudentCard: View {
    let student: Student
    let stats: TutorKitContainer.StudentStats

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(student.name).font(.headline).lineLimit(1)
                Spacer()
                if !student.targetGrade.isEmpty {
                    Text("Target \(student.targetGrade)")
                        .font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                }
            }
            Text([student.level.rawValue, student.subject.rawValue, student.board?.rawValue, student.tier.flatMap { $0 == .notApplicable ? nil : $0.rawValue }]
                .compactMap { $0 }.joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary)
            if let coverage = stats.coverage {
                CoverageBar(coverage: coverage)
            }
            HStack(spacing: 12) {
                Label("\(stats.lessons)", systemSymbol: .calendar)
                Label("\(stats.questionsShown)", systemSymbol: .archivebox)
                if let last = stats.lastLesson {
                    Label(last.formatted(date: .abbreviated, time: .omitted), systemSymbol: .clock)
                }
                if stats.pendingOutcomes > 0 {
                    Label("\(stats.pendingOutcomes) to record", systemSymbol: .checklist).foregroundStyle(.orange)
                }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator, lineWidth: 0.5))
        .contentShape(Rectangle())
    }
}
