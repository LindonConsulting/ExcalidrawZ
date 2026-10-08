//
//  StudentEditSheet.swift
//  ExcalidrawZ
//
//  Edits a student, their primary enrolment (what you teach them), the other
//  specifications they study, and their focus topics.
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
    @State private var primary: Enrolment
    /// Specification ids of the non-primary enrolments.
    @State private var otherSpecificationIDs: Set<UUID>
    @State private var focusTopicIDs: [String]
    @State private var groupNames: [String] = []
    @State private var isDeleteConfirmPresented = false

    init(student: Student?) {
        isNew = student == nil
        let container = TutorKitContainer.shared
        let record = student ?? Student(name: "")
        _student = State(initialValue: record)
        let enrolments = student.map(container.enrolments(for:)) ?? []
        let primary = enrolments.first { $0.isPrimary } ?? enrolments.first ?? Enrolment(studentID: record.id, isPrimary: true)
        _primary = State(initialValue: primary)
        _otherSpecificationIDs = State(initialValue: Set(enrolments.filter { $0.id != primary.id }.compactMap(\.specificationID)))
        _focusTopicIDs = State(initialValue: student.map(container.focusTopicIDs(for:)) ?? [])
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
                TextField("Year group", text: $student.yearGroup)
                Picker("Subject", selection: $primary.subject) { ForEach(Subject.allCases) { Text($0.rawValue).tag($0) } }
                Picker("Level", selection: $primary.level) { ForEach(QualificationLevel.allCases) { Text($0.rawValue).tag($0) } }
                Picker("Board", selection: $primary.board) {
                    Text("—").tag(ExamBoard?.none)
                    ForEach(ExamBoard.allCases) { Text($0.rawValue).tag(ExamBoard?.some($0)) }
                }
                if primary.level == .gcse {
                    Picker("Tier", selection: $primary.tier) {
                        Text("—").tag(Tier?.none)
                        ForEach([Tier.foundation, .higher]) { Text($0.rawValue).tag(Tier?.some($0)) }
                    }
                }
                Picker("Main specification", selection: $primary.specificationID) {
                    Text("—").tag(UUID?.none)
                    ForEach(container.specifications.filter { $0.level == primary.level }) { spec in
                        Text(spec.displayName).tag(UUID?.some(spec.id))
                    }
                }
                TextField("Target grade", text: $primary.targetGrade)
                TextField("Notes", text: $student.notes, axis: .vertical).lineLimit(2...5)
            }
            .formStyle(.columns)

            VStack(alignment: .leading, spacing: 6) {
                Text("Also studying (other specifications)").font(.callout).foregroundStyle(.secondary)
                ForEach(container.specifications.filter { $0.id != primary.specificationID }) { spec in
                    Toggle(spec.displayName, isOn: Binding(
                        get: { otherSpecificationIDs.contains(spec.id) },
                        set: { on in if on { otherSpecificationIDs.insert(spec.id) } else { otherSpecificationIDs.remove(spec.id) } }
                    ))
                    .toggleStyle(.checkbox)
                }
            }

            focusTopics

            HStack {
                if !isNew {
                    Button("Delete…", role: .destructive) { isDeleteConfirmPresented = true }
                    if student.deletedAt != nil {
                        Button("Unarchive") { student.deletedAt = nil }
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
        .confirmationDialog("Delete \(student.name)? Their enrolments, lesson history and question outcomes are removed too.", isPresented: $isDeleteConfirmPresented, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                do { try container.deleteStudent(id: student.id); dismiss() } catch { alertToast(error) }
            }
        }
    }

    @ViewBuilder
    private var focusTopics: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Focus topics").font(.callout).foregroundStyle(.secondary)
            FlowTags(tags: focusTopicIDs.map(container.topicName)) { name in
                focusTopicIDs.removeAll { container.topicName($0) == name }
            }
            Menu("Add focus topic") {
                ForEach(container.strands.filter { $0.subject == primary.subject && ($0.level == nil || $0.level == primary.level) }) { strand in
                    Menu(strand.name) {
                        ForEach(container.children(of: strand.id)) { topic in
                            Button(topic.name) { if !focusTopicIDs.contains(topic.id) { focusTopicIDs.append(topic.id) } }
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
        if primary.level != .gcse { primary.tier = nil }
        primary.isPrimary = true
        primary.studentID = student.id
        do {
            try container.save(student)
            try container.save(primary)
            // Other specifications: one enrolment each; drop the ones switched off.
            let existing = container.enrolments(for: student).filter { $0.id != primary.id }
            for enrolment in existing where enrolment.specificationID.map({ !otherSpecificationIDs.contains($0) }) ?? false {
                try container.deleteEnrolment(id: enrolment.id)
            }
            for specID in otherSpecificationIDs where !existing.contains(where: { $0.specificationID == specID }) {
                guard let spec = container.specification(id: specID) else { continue }
                try container.save(Enrolment(studentID: student.id, specificationID: spec.id, subject: spec.subject, level: spec.level,
                                             board: spec.board, tier: spec.level == .gcse ? primary.tier : nil))
            }
            try container.setFocusTopics(focusTopicIDs, for: student)
            dismiss()
        } catch {
            alertToast(error)
        }
    }
}
