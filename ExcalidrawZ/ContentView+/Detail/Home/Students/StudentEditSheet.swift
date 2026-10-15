//
//  StudentEditSheet.swift
//  ExcalidrawZ
//
//  Edits a student's profile, their enrolments (what you teach them, one per subject/level),
//  the other specifications they study, their parent contact and focus topics.
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
    /// Live enrolments being edited, primary first. Removed ones are deleted on save.
    @State private var enrolments: [Enrolment]
    @State private var contact: StudentContact
    @State private var focusTopicIDs: [String]
    @State private var groupNames: [String] = []
    @State private var isDeleteConfirmPresented = false

    private static let managementOptions = ["private", "mytutor", "school", "other"]
    private static let contactMethods = ["", "WhatsApp", "Email", "Phone", "Text", "Messenger"]

    init(student: Student?) {
        isNew = student == nil
        let container = TutorKitContainer.shared
        let record = student ?? Student(name: "")
        _student = State(initialValue: record)
        var enrolments = student.map(container.enrolments(for:)) ?? []
        if enrolments.isEmpty { enrolments = [Enrolment(studentID: record.id, isPrimary: true)] }
        if !enrolments.contains(where: \.isPrimary) { enrolments[0].isPrimary = true }
        _enrolments = State(initialValue: enrolments)
        _focusTopicIDs = State(initialValue: student.map(container.focusTopicIDs(for:)) ?? [])
        let contacts = student.map(container.contacts(for:)) ?? []
        _contact = State(initialValue: contacts.first { $0.isPrimary } ?? contacts.first ?? StudentContact(studentID: record.id, relationship: "parent", isPrimary: true))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isNew ? "New Student" : "Edit \(student.name)").font(.title2.bold())

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    section("Profile") {
                        field("Name") {
                            HStack {
                                TextField("Matches the file group", text: $student.name)
                                if !groupNames.isEmpty {
                                    Menu("Groups") {
                                        ForEach(groupNames, id: \.self) { name in Button(name) { student.name = name } }
                                    }.fixedSize()
                                }
                            }
                        }
                        field("Year group") { TextField("", text: $student.yearGroup) }
                        field("School") { TextField("", text: $student.school) }
                        field("Via") {
                            Picker("", selection: $student.management) {
                                Text("—").tag("")
                                ForEach(Self.managementOptions, id: \.self) { Text($0.capitalized).tag($0) }
                                if !student.management.isEmpty, !Self.managementOptions.contains(student.management) {
                                    Text(student.management).tag(student.management)
                                }
                            }
                            .labelsHidden().fixedSize()
                        }
                        field("Notes") { TextField("", text: $student.notes, axis: .vertical).lineLimit(2...5) }
                        field("Rapport notes") { TextField("What they're into, how lessons go", text: $student.rapportNotes, axis: .vertical).lineLimit(2...5) }
                        field("Hobbies") { TextField("", text: $student.hobbies) }
                        field("Interests") { TextField("", text: $student.interests) }
                    }

                    section("Enrolments") {
                        ForEach($enrolments) { $enrolment in
                            enrolmentRow($enrolment)
                        }
                        HStack {
                            Button { enrolments.append(Enrolment(studentID: student.id, isPrimary: enrolments.isEmpty)) } label: {
                                Label("Add enrolment", systemSymbol: .plus)
                            }
                            .controlSize(.small)
                            Spacer()
                            if let clash = duplicateEnrolment {
                                Text("Two enrolments for \(clash)").font(.caption).foregroundStyle(.red)
                            }
                        }
                    }

                    section("Parent / contact") {
                        field("Name") { TextField("", text: $contact.name) }
                        field("Relationship") { TextField("", text: $contact.relationship) }
                        field("Phone") { TextField("", text: $contact.phone) }
                        field("Email") { TextField("", text: $contact.email) }
                        field("Prefers") {
                            Picker("", selection: $contact.preferredMethod) {
                                ForEach(Self.contactMethods, id: \.self) { Text($0.isEmpty ? "—" : $0).tag($0) }
                            }
                            .labelsHidden().fixedSize()
                        }
                    }

                    section("Focus topics") { focusTopics }
                }
                .frame(width: 528, alignment: .leading)
            }

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
        .frame(width: 580, height: 720)
        .onAppear { loadGroupNames() }
        .confirmationDialog("Delete \(student.name)? Their enrolments, lesson history and question outcomes are removed too.", isPresented: $isDeleteConfirmPresented, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                do { try container.deleteStudent(id: student.id); dismiss() } catch { alertToast(error) }
            }
        }
    }

    private var primaryEnrolment: Enrolment { enrolments.first { $0.isPrimary } ?? enrolments.first ?? Enrolment(studentID: student.id) }

    /// "GCSE Maths" when two live enrolments share subject and level (the store refuses that).
    private var duplicateEnrolment: String? {
        var seen = Set<String>()
        for e in enrolments {
            let key = "\(e.level.rawValue) \(e.subject.rawValue)"
            if !seen.insert(key).inserted { return key }
        }
        return nil
    }

    @ViewBuilder
    private func enrolmentRow(_ enrolment: Binding<Enrolment>) -> some View {
        let e = enrolment.wrappedValue
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    for i in enrolments.indices { enrolments[i].isPrimary = enrolments[i].id == e.id }
                } label: {
                    Image(systemSymbol: e.isPrimary ? .starFill : .star).foregroundStyle(e.isPrimary ? .yellow : .secondary)
                }
                .buttonStyle(.borderless)
                .help(e.isPrimary ? "Main enrolment (used by Lesson Draw when the calendar doesn't say)" : "Make this the main enrolment")
                Picker("", selection: enrolment.subject) { ForEach(Subject.allCases) { Text($0.rawValue).tag($0) } }.labelsHidden()
                Picker("", selection: enrolment.level) { ForEach(QualificationLevel.allCases) { Text($0.rawValue).tag($0) } }.labelsHidden()
                Picker("", selection: enrolment.board) {
                    Text("Board").tag(ExamBoard?.none)
                    ForEach(ExamBoard.allCases) { Text($0.rawValue).tag(ExamBoard?.some($0)) }
                }.labelsHidden()
                if e.level == .gcse {
                    Picker("", selection: enrolment.tier) {
                        Text("Tier").tag(Tier?.none)
                        ForEach([Tier.foundation, .higher]) { Text($0.rawValue).tag(Tier?.some($0)) }
                    }.labelsHidden()
                }
                Button(role: .destructive) {
                    enrolments.removeAll { $0.id == e.id }
                    if !enrolments.contains(where: \.isPrimary), !enrolments.isEmpty { enrolments[0].isPrimary = true }
                } label: { Image(systemSymbol: .trash) }
                .buttonStyle(.borderless)
                .disabled(enrolments.count == 1)
            }
            HStack(spacing: 8) {
                Text("Specification").foregroundStyle(.secondary)
                Picker("", selection: enrolment.specificationID) {
                    Text("—").tag(UUID?.none)
                    ForEach(container.specifications.filter { $0.level == e.level && $0.subject == e.subject }) { spec in
                        Text(spec.displayName).tag(UUID?.some(spec.id))
                    }
                }
                .labelsHidden()
                Text("Target").foregroundStyle(.secondary)
                TextField("", text: enrolment.targetGrade).frame(width: 60)
            }
            .padding(.leading, 26)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(e.isPrimary ? 0.10 : 0.04)))
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            VStack(alignment: .leading, spacing: 8) { content() }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.06)))
    }

    /// Label on the left at a fixed width, control filling the rest.
    @ViewBuilder
    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label).foregroundStyle(.secondary).frame(width: 110, alignment: .trailing)
            content().frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var focusTopics: some View {
        VStack(alignment: .leading, spacing: 6) {
            FlowTags(tags: focusTopicIDs.map(container.topicName)) { name in
                focusTopicIDs.removeAll { container.topicName($0) == name }
            }
            Menu("Add focus topic") {
                ForEach(container.strands.filter { $0.subject == primaryEnrolment.subject && ($0.level == nil || $0.level == primaryEnrolment.level) }) { strand in
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
        if let clash = duplicateEnrolment {
            alertToast(.init(displayMode: .alert, type: .error(.red), title: "Two enrolments for \(clash). Remove one."))
            return
        }
        do {
            try container.save(student)
            let before = isNew ? [] : container.enrolments(for: student)
            for removed in before where !enrolments.contains(where: { $0.id == removed.id }) {
                try container.deleteEnrolment(id: removed.id)
            }
            // Non-primary first; saving the primary demotes the others in the store.
            for var enrolment in enrolments.sorted(by: { !$0.isPrimary && $1.isPrimary }) {
                enrolment.studentID = student.id
                if enrolment.level != .gcse { enrolment.tier = nil }
                try container.save(enrolment)
            }
            var contact = contact
            contact.studentID = student.id
            contact.isPrimary = true
            if contact.summary.isEmpty {
                if !isNew, container.contacts(for: student).contains(where: { $0.id == contact.id }) { try container.deleteContact(id: contact.id) }
            } else {
                try container.save(contact)
            }
            try container.setFocusTopics(focusTopicIDs, for: student)
            dismiss()
        } catch {
            alertToast(error)
        }
    }
}
