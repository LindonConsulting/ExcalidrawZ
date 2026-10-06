//
//  StudentEditSheet.swift
//  ExcalidrawZ
//

import SwiftUI
import CoreData
import ChocofordUI
import TutorModels

struct StudentEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.alertToast) private var alertToast
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject private var container = TutorKitContainer.shared

    private let isNew: Bool
    @State private var student: Student
    @State private var groupNames: [String] = []
    @State private var isDeleteConfirmPresented = false

    init(student: Student?) {
        isNew = student == nil
        _student = State(initialValue: student ?? Student(name: ""))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isNew ? "New Student" : "Edit Student").font(.title2.bold())

            Form {
                HStack {
                    TextField("Name (matches the file group)", text: $student.name)
                    if !groupNames.isEmpty {
                        Menu("Groups") {
                            ForEach(groupNames, id: \.self) { name in Button(name) { student.name = name } }
                        }.fixedSize()
                    }
                }
                Picker("Subject", selection: $student.subject) { ForEach(Subject.allCases) { Text($0.rawValue).tag($0) } }
                Picker("Level", selection: $student.level) { ForEach(QualificationLevel.allCases) { Text($0.rawValue).tag($0) } }
                Picker("Board", selection: $student.board) {
                    Text("—").tag(ExamBoard?.none)
                    ForEach(ExamBoard.allCases) { Text($0.rawValue).tag(ExamBoard?.some($0)) }
                }
                if student.level == .gcse {
                    Picker("Tier", selection: $student.tier) {
                        Text("—").tag(Tier?.none)
                        ForEach([Tier.foundation, .higher]) { Text($0.rawValue).tag(Tier?.some($0)) }
                    }
                }
                Picker("Specification", selection: $student.specificationID) {
                    Text("—").tag(UUID?.none)
                    ForEach(container.specifications.filter { $0.subject == student.subject && $0.level == student.level }) { spec in
                        Text(spec.displayName).tag(UUID?.some(spec.id))
                    }
                }
                TextField("Target grade", text: $student.targetGrade)
                TextField("Notes", text: $student.notes, axis: .vertical).lineLimit(2...5)
            }
            .formStyle(.columns)

            focusTopics

            HStack {
                if !isNew {
                    Button("Delete…", role: .destructive) { isDeleteConfirmPresented = true }
                    if student.archivedAt != nil {
                        Button("Unarchive") { student.archivedAt = nil }
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(isNew ? "Add" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(student.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear { loadGroupNames() }
        .confirmationDialog("Delete \(student.name)? Their lesson history and question outcomes are removed too.", isPresented: $isDeleteConfirmPresented, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                do { try container.deleteStudent(id: student.id); dismiss() } catch { alertToast(error) }
            }
        }
    }

    @ViewBuilder
    private var focusTopics: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Focus topics").font(.callout).foregroundStyle(.secondary)
            FlowTags(tags: student.focusTopicIDs.map(container.topicName)) { name in
                student.focusTopicIDs.removeAll { container.topicName($0) == name }
            }
            Menu("Add focus topic") {
                ForEach(container.strands.filter { $0.subject == student.subject && ($0.level == nil || $0.level == student.level) }) { strand in
                    Menu(strand.name) {
                        ForEach(container.children(of: strand.id)) { topic in
                            Button(topic.name) { if !student.focusTopicIDs.contains(topic.id) { student.focusTopicIDs.append(topic.id) } }
                        }
                    }
                }
            }
            .fixedSize()
        }
    }

    private func loadGroupNames() {
        let request = NSFetchRequest<Group>(entityName: "Group")
        request.predicate = NSPredicate(format: "parent == nil AND type != %@", Group.GroupType.trash.rawValue)
        request.sortDescriptors = [.init(key: "name", ascending: true)]
        let existing = Set(container.students.map { $0.name.lowercased() })
        groupNames = ((try? viewContext.fetch(request)) ?? []).compactMap(\.name).filter { !existing.contains($0.lowercased()) }
    }

    private func save() {
        student.name = student.name.trimmingCharacters(in: .whitespaces)
        if student.level != .gcse { student.tier = nil }
        do { try container.save(student); dismiss() } catch { alertToast(error) }
    }
}
