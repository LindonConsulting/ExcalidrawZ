//
//  ImportMyTutorLessonSheet.swift
//  ExcalidrawZ
//
//  Confirmation sheet for "Import MyTutor lesson…": picks the Room Export
//  ZIP (newest in Downloads by default), lists its tabs, matches the lesson
//  to a student via the calendar, writes a recap in the background, and
//  imports on confirm.
//

import SwiftUI
import ChocofordUI
import CoreData
import UniformTypeIdentifiers
import LessonspaceImport

struct ImportMyTutorLessonSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.alertToast) private var alertToast
    @EnvironmentObject private var fileState: FileState

    @AppStorage("LessonspaceImport.includeTemplates") private var includeTemplates = false

    private enum ZipPhase {
        case none
        case loading(URL)
        case loaded(URL, LessonspaceRoomExport)
        case failed(URL, Error)
    }

    private enum LessonPhase {
        case detecting
        case ready(LessonDrawPlan, existingFile: File?)
        case failed(Error)
    }

    private enum SummaryState {
        case idle, generating, ready(String), unavailable, failed(Error)
    }

    @State private var zipPhase: ZipPhase = .none
    @State private var lessonPhase: LessonPhase = .detecting
    @State private var summaryState: SummaryState = .idle
    @State private var summaryTask: Task<String?, Error>?
    @State private var isImporting = false
    @State private var isFilePickerPresented = false
    @State private var manualStudent = ""
    @State private var manualSubject = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import MyTutor lesson")
                .font(.title2.bold())

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    label("Export")
                    zipView
                }
                if case .loaded(_, let export) = zipPhase {
                    GridRow {
                        label("Tabs")
                        tabsView(export)
                    }
                }
                GridRow {
                    label("Lesson")
                    lessonView
                }
                if case .ready(let plan, let existing) = lessonPhase {
                    GridRow {
                        label("Destination")
                        Text(existing == nil
                             ? "New file “\(plan.fileName)” in \(plan.student)"
                             : "Append to “\(existing!.name ?? plan.fileName)”")
                            .textSelection(.enabled)
                    }
                    GridRow {
                        label("Recap")
                        summaryView
                    }
                }
            }

            HStack {
                if case .generating = summaryState {
                    ProgressView().controlSize(.small)
                    Text("Writing recap…").foregroundStyle(.secondary).font(.callout)
                }
                Spacer()
                Button("Cancel") {
                    summaryTask?.cancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button(isImporting ? "Importing…" : "Import") {
                    Task { await importLesson() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canImport || isImporting)
            }
        }
        .padding(20)
        .frame(width: 480)
        .task {
            async let lesson: () = detect()
            if let url = LessonspaceImportCoordinator.defaultExportURL() {
                await load(url)
            }
            await lesson
        }
        .onChange(of: includeTemplates) { _ in restartSummary() }
        .fileImporter(isPresented: $isFilePickerPresented, allowedContentTypes: [.zip]) { result in
            if case .success(let url) = result { Task { await load(url) } }
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func label(_ title: String) -> some View {
        Text(title).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
    }

    @ViewBuilder
    private var zipView: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch zipPhase {
                case .none:
                    Text("No “Room Export … .zip” found in Downloads.").foregroundStyle(.secondary)
                case .loading(let url):
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text(url.lastPathComponent) }
                case .loaded(let url, _):
                    Text(url.lastPathComponent).textSelection(.enabled)
                case .failed(let url, let error):
                    Text(url.lastPathComponent)
                    Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary).font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
            }
            Button("Choose another ZIP…") { isFilePickerPresented = true }
                .controlSize(.small)
        }
    }

    @ViewBuilder
    private func tabsView(_ export: LessonspaceRoomExport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(export.tabs, id: \.id) { tab in
                let skipped = tab.isTemplate && !includeTemplates
                HStack(spacing: 6) {
                    Image(systemName: skipped ? "minus.circle" : "checkmark.circle.fill")
                        .foregroundStyle(skipped ? Color.secondary : Color.accentColor)
                    Text(tab.name).strikethrough(skipped).foregroundStyle(skipped ? .secondary : .primary)
                    Text("· \(tab.objects.count) object\(tab.objects.count == 1 ? "" : "s")")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if export.tabs.contains(where: \.isTemplate) {
                Toggle("Include MyTutor template tabs", isOn: $includeTemplates)
                    .toggleStyle(.checkbox)
                    .font(.callout)
            }
        }
    }

    @ViewBuilder
    private var lessonView: some View {
        switch lessonPhase {
            case .detecting:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Matching the lesson in Calendar…").foregroundStyle(.secondary)
                }
            case .failed(let error):
                lessonFailureView(error)
            case .ready(let plan, _):
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(plan.student)\(plan.subject.map { " – \($0)" } ?? "")")
                    Text(eventDescription(plan)).font(.callout).foregroundStyle(.secondary)
                }
        }
    }

    @ViewBuilder
    private func lessonFailureView(_ error: Error) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let calendarError = error as? LessonCalendarError, case .accessDenied = calendarError {
#if os(macOS)
                Button("Open System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                        NSWorkspace.shared.open(url)
                    }
                }
#endif
            }
            TextField("Student", text: $manualStudent)
            TextField("Subject (optional)", text: $manualSubject)
            HStack {
                Button("Use this student") {
                    let match = LessonTitleMatch(
                        student: manualStudent.trimmingCharacters(in: .whitespaces),
                        studentPrefix: manualStudent,
                        subject: manualSubject.trimmingCharacters(in: .whitespaces).isEmpty ? nil : manualSubject
                    )
                    Task { await detect(overrideMatch: match) }
                }
                .disabled(manualStudent.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Try again") { Task { await detect() } }
            }
        }
    }

    @ViewBuilder
    private var summaryView: some View {
        switch summaryState {
            case .idle, .generating:
                Text("Generating…").foregroundStyle(.secondary)
            case .unavailable:
                Text("No recap: nothing to summarise or no AI backend configured.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .failed(let error):
                Text("Recap failed: \(error.localizedDescription). The lesson will be imported without it.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .ready(let text):
                ScrollView {
                    Text(text)
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 140)
                .padding(8)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private func eventDescription(_ plan: LessonDrawPlan) -> String {
        let formatter = DateFormatter()
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "\(plan.event.title) · \(formatter.string(from: plan.event.startDate))"
    }

    // MARK: - State

    private var currentPlan: LessonspaceImportPlan? {
        guard case .loaded(let url, let export) = zipPhase else { return nil }
        var plan = LessonspaceImportPlan(zipURL: url, export: export, includeTemplates: includeTemplates)
        if case .ready(let lesson, let existing) = lessonPhase {
            plan.lesson = lesson
            plan.existingFileObjectID = existing?.objectID
            plan.existingFileName = existing?.name
        }
        return plan
    }

    private var canImport: Bool {
        guard let plan = currentPlan, plan.lesson != nil else { return false }
        return !plan.selectedTabs.isEmpty
    }

    // MARK: - Actions

    private func load(_ url: URL) async {
        zipPhase = .loading(url)
        do {
            let export = try await LessonspaceImportCoordinator.loadExport(at: url)
            zipPhase = .loaded(url, export)
        } catch {
            zipPhase = .failed(url, error)
        }
        restartSummary()
    }

    private func detect(overrideMatch: LessonTitleMatch? = nil) async {
        lessonPhase = .detecting
        do {
            let plan = try await LessonspaceImportCoordinator.detectLesson(context: viewContext, overrideMatch: overrideMatch)
            let existing = LessonspaceImportCoordinator.existingLessonFile(for: plan, context: viewContext)
            lessonPhase = .ready(plan, existingFile: existing)
        } catch {
            lessonPhase = .failed(error)
        }
        restartSummary()
    }

    private func restartSummary() {
        summaryTask?.cancel()
        summaryTask = nil
        guard let plan = currentPlan, plan.lesson != nil else {
            summaryState = .idle
            return
        }
        guard plan.recapInput != nil else {
            summaryState = .unavailable
            return
        }
        summaryState = .generating
        let task = Task<String?, Error> { try await LessonspaceImportCoordinator.summarize(plan) }
        summaryTask = task
        Task {
            do {
                if let text = try await task.value {
                    guard summaryTask == task else { return }
                    summaryState = .ready(text)
                } else {
                    guard summaryTask == task else { return }
                    summaryState = .unavailable
                }
            } catch is CancellationError {
                // superseded or dismissed
            } catch {
                guard summaryTask == task else { return }
                summaryState = .failed(error)
            }
        }
    }

    private func importLesson() async {
        guard let plan = currentPlan, plan.lesson != nil else { return }
        isImporting = true
        defer { isImporting = false }

        var summary: String?
        if let task = summaryTask {
            summary = await withTimeout(seconds: 30) { try? await task.value } ?? nil
        }

        do {
            let outcome = try await LessonspaceImportCoordinator.perform(plan, summary: summary, fileState: fileState, context: viewContext)
            alertToast(.init(displayMode: .hud, type: .complete(.green),
                             title: outcome.didAppend ? "Lesson appended" : "Lesson imported",
                             subTitle: "\(outcome.frameNames.count) tab\(outcome.frameNames.count == 1 ? "" : "s") → \(outcome.fileName)"))
            dismiss()
        } catch {
            alertToast(error)
        }
    }

    private func withTimeout<T: Sendable>(seconds: Double, _ operation: @escaping @Sendable () async -> T?) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await operation() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
