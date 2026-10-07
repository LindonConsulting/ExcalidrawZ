//
//  StudentsPage.swift
//  ExcalidrawZ
//
//  Full-page student roster: calendar is the source of truth for who is a
//  student; Supabase supplies the profile; TutorKit holds lesson data.
//

import SwiftUI
import TutorModels
import TutorSync

struct StudentsPage: View {
    @ObservedObject private var container = TutorKitContainer.shared
    @EnvironmentObject private var fileState: FileState

    @State private var query = ""
    @State private var showInactive = false
    @State private var selection: String?
    @State private var detailStudent: Student?
    @State private var creatingName: String?
    @State private var isSpecificationsPresented = false

    struct Row: Identifiable {
        var name: String
        var roster: RosterEntry?
        var student: Student?
        var id: String { name.lowercased() }
    }

    private var rows: [Row] {
        var byKey: [String: Row] = [:]
        for entry in container.roster { byKey[entry.id] = Row(name: entry.name, roster: entry, student: container.student(named: entry.name)) }
        for student in container.students {
            let key = student.name.lowercased()
            if byKey[key] == nil { byKey[key] = Row(name: student.name, roster: nil, student: student) }
        }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return byKey.values
            .filter { showInactive || ($0.roster?.isActive ?? false) }
            .filter { q.isEmpty || $0.name.lowercased().contains(q) || ($0.student.map { "\($0.board?.rawValue ?? "") \($0.level.rawValue) \($0.subject.rawValue) \($0.yearGroup) \($0.management)".lowercased().contains(q) } ?? false) }
            .sorted { ($0.roster?.nextLesson ?? .distantFuture, $0.name) < ($1.roster?.nextLesson ?? .distantFuture, $1.name) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if let error = container.rosterError {
                Text(error).foregroundStyle(.secondary).padding()
            }
            table
        }
        .task {
            container.openIfNeeded()
            await container.refreshRoster()
        }
        .sheet(item: $detailStudent) { student in StudentDetailSheet(studentID: student.id) }
        .sheet(isPresented: Binding(get: { creatingName != nil }, set: { if !$0 { creatingName = nil } })) {
            StudentEditSheet(student: Student(name: creatingName ?? ""))
        }
        .sheet(isPresented: $isSpecificationsPresented) { SpecificationsSheet() }
    }

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Students").font(.largeTitle.bold())
                Spacer()
                Button { isSpecificationsPresented = true } label: { Label("Specifications…", systemSymbol: .listBulletRectangle) }
                Button {
                    Task { await container.syncFromSupabase(); await container.refreshRoster() }
                } label: {
                    if container.isSyncing { ProgressView().controlSize(.small) } else { Label("Sync", systemSymbol: .arrowTriangle2Circlepath) }
                }
                .disabled(container.isSyncing || !TutorSyncSettings.hasKey())
                .help(TutorSyncSettings.hasKey() ? "Pull profiles from ConwyMaths and refresh the calendar roster" : "Add the Supabase key in Settings › Lessons to sync profiles")
            }
            HStack(spacing: 12) {
                TextField("Search name, board, level, year…", text: $query).textFieldStyle(.roundedBorder).frame(maxWidth: 320)
                Toggle("Show inactive", isOn: $showInactive).toggleStyle(.checkbox)
                Spacer()
                let active = container.roster.filter(\.isActive).count
                Text("\(active) active in the calendar (8 weeks either side) · \(container.students.count) profiles")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if let message = container.lastSyncMessage {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(20)
    }

    @ViewBuilder
    private var table: some View {
        Table(rows, selection: $selection) {
            TableColumn("Student") { row in
                HStack(spacing: 6) {
                    Text(row.name).font(.body.weight(.medium))
                    if row.student?.remoteID == nil {
                        Text("no profile").font(.caption2).foregroundStyle(.orange)
                    }
                }
            }
            .width(min: 140)
            TableColumn("Course") { row in
                if let s = row.student {
                    Text([s.level.rawValue, s.subject.rawValue, s.board?.rawValue, s.tier.flatMap { $0 == .notApplicable ? nil : $0.rawValue }].compactMap { $0 }.joined(separator: " · "))
                } else {
                    Text(row.roster?.subjects.joined(separator: ", ") ?? "").foregroundStyle(.secondary)
                }
            }
            .width(min: 180)
            TableColumn("Year") { row in Text(row.student?.yearGroup ?? "") }.width(70)
            TableColumn("Via") { row in Text(row.student?.management ?? "").foregroundStyle(.secondary) }.width(70)
            TableColumn("Next lesson") { row in
                Text(row.roster?.nextLesson.map { $0.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()) } ?? "—")
            }
            .width(min: 120)
            TableColumn("Lessons") { row in
                Text(row.roster.map { "\($0.pastLessons) past · \($0.upcomingLessons) ahead" + ($0.lastLesson.map { " · last \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "") } ?? "none in window").foregroundStyle(.secondary)
            }
            .width(min: 160)
            TableColumn("Coverage") { row in
                if let s = row.student, let c = container.stats(for: s).coverage {
                    Text("\(c.total - c.count(.notCovered))/\(c.total)")
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            .width(80)
            TableColumn("To record") { row in
                if let s = row.student {
                    let n = container.stats(for: s).pendingOutcomes
                    Text(n == 0 ? "" : "\(n)").foregroundStyle(.orange)
                }
            }
            .width(70)
            TableColumn("Decks") { row in
                if let id = row.student?.remoteID {
                    let assigned = container.deckAssignmentsByStudent[id] ?? []
                    Text(assigned.isEmpty ? "" : "\(assigned.filter { $0.completed_at == nil }.count) open / \(assigned.count)")
                }
            }
            .width(90)
            TableColumn("") { row in
                HStack {
                    if let student = row.student {
                        Button("Open") { detailStudent = student }
                    } else {
                        Button("Create profile") { creatingName = row.name }
                    }
                }
                .controlSize(.small)
            }
            .width(110)
        }
        .contextMenu(forSelectionType: String.self) { _ in } primaryAction: { ids in
            if let id = ids.first, let row = rows.first(where: { $0.id == id }) {
                if let student = row.student { detailStudent = student } else { creatingName = row.name }
            }
        }
    }
}
