//
//  StudentDetailSheet.swift
//  ExcalidrawZ
//
//  Per-student view: profile summary, lessons, and the specification
//  coverage checklist.
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
    @State private var isReviewPresented = false
    @State private var filter: Filter = .all
    @State private var expandedSections: Set<UUID> = []

    private enum Filter: String, CaseIterable, Identifiable {
        case all = "All", notCovered = "Not covered", needsWork = "Needs work"
        var id: String { rawValue }
    }

    private var student: Student? { container.students.first { $0.id == studentID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let student {
                header(student)
                Divider()
                if let specID = student.specificationID, let tree = container.specificationTree(id: specID) {
                    checklist(student: student, tree: tree)
                } else {
                    VStack(spacing: 8) {
                        Text("No specification linked.").font(.headline)
                        Text("Edit the student and choose a specification to get a coverage checklist. Import one from the Specifications… button on the Home page.")
                            .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                Text("Student not found.").foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(minWidth: 720, minHeight: 560)
        .sheet(isPresented: $isEditing) {
            if let student { StudentEditSheet(student: student) }
        }
        .sheet(isPresented: $isReviewPresented) {
            if let student { LessonReviewSheet(studentName: student.name, title: "Results for \(student.name)") }
        }
    }

    @ViewBuilder
    private func header(_ student: Student) -> some View {
        let stats = container.stats(for: student)
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(student.name).font(.title2.bold())
                Text([student.level.rawValue, student.subject.rawValue, student.board?.rawValue, student.tier?.rawValue, student.targetGrade.isEmpty ? nil : "Target \(student.targetGrade)"]
                    .compactMap { $0 }.joined(separator: " · "))
                    .foregroundStyle(.secondary)
                if let spec = container.specification(id: student.specificationID) {
                    Text(spec.title).font(.callout).foregroundStyle(.secondary)
                }
                HStack(spacing: 14) {
                    Label("\(stats.lessons) lessons", systemSymbol: .calendar)
                    Label("\(stats.questionsShown) questions shown", systemSymbol: .archivebox)
                }
                .font(.callout).foregroundStyle(.secondary)
                if !student.notes.isEmpty { Text(student.notes).font(.callout) }
                if let coverage = stats.coverage { CoverageBar(coverage: coverage).frame(maxWidth: 420) }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                Button("Edit…") { isEditing = true }
                let pending = container.pendingOutcomes(studentName: student.name).count
                if pending > 0 {
                    Button { isReviewPresented = true } label: { Label("Record \(pending) result\(pending == 1 ? "" : "s")", systemSymbol: .checklist) }
                }
            }
        }
    }

    @ViewBuilder
    private func checklist(student: Student, tree: SpecificationTree) -> some View {
        let coverage = container.coverage(for: student)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Specification coverage").font(.headline)
                Spacer()
                Picker("", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 320)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(tree.sections) { section in
                        let points = visiblePoints(tree.points(in: section), student: student, coverage: coverage)
                        if !points.isEmpty {
                            DisclosureGroup(isExpanded: Binding(
                                get: { expandedSections.contains(section.id) || filter != .all },
                                set: { if $0 { expandedSections.insert(section.id) } else { expandedSections.remove(section.id) } }
                            )) {
                                ForEach(points) { point in pointRow(point, status: coverage[point.id] ?? .notCovered) }
                            } label: {
                                HStack {
                                    Text(section.code.isEmpty ? section.title : "\(section.code) · \(section.title)").font(.subheadline.bold())
                                    Spacer()
                                    sectionSummary(points, coverage: coverage)
                                }
                            }
                        }
                    }
                }
                .padding(.trailing, 8)
            }
        }
    }

    private func visiblePoints(_ points: [SpecPoint], student: Student, coverage: [UUID: CoverageStatus]) -> [SpecPoint] {
        points.filter { point in
            if let tier = point.tier, let studentTier = student.tier, tier != studentTier { return false }
            let status = coverage[point.id] ?? .notCovered
            switch filter {
                case .all: return true
                case .notCovered: return status == .notCovered
                case .needsWork: return status == .wrong || status == .partial
            }
        }
    }

    @ViewBuilder
    private func sectionSummary(_ points: [SpecPoint], coverage: [UUID: CoverageStatus]) -> some View {
        let covered = points.filter { (coverage[$0.id] ?? .notCovered) != .notCovered }.count
        Text("\(covered)/\(points.count)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
    }

    @ViewBuilder
    private func pointRow(_ point: SpecPoint, status: CoverageStatus) -> some View {
        let linked = container.questions(forSpecPoint: point.id).count
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(point.code).font(.caption.monospaced()).foregroundStyle(.secondary).frame(width: 56, alignment: .leading)
            Text(point.text).font(.callout).fixedSize(horizontal: false, vertical: true)
            if let tier = point.tier { Text(tier == .higher ? "H" : "F").font(.caption2).foregroundStyle(.secondary) }
            Spacer()
            Text("\(linked) q").font(.caption).foregroundStyle(linked == 0 ? .tertiary : .secondary)
            StatusPill(status: status)
        }
        .padding(.vertical, 2)
        .padding(.leading, 12)
    }
}
