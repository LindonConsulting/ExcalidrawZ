//
//  NewLessonDrawSheet.swift
//  ExcalidrawZ
//
//  Confirmation sheet: shows the detected student and previous lesson,
//  generates the recap in the background, and creates the file on confirm.
//

import SwiftUI
import ChocofordUI
import CoreData

struct NewLessonDrawSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.alertToast) private var alertToast
    @EnvironmentObject private var fileState: FileState

    private enum Phase {
        case detecting
        case ready(LessonDrawPlan)
        case failed(Error)
    }

    private enum SummaryState {
        case idle
        case generating
        case ready(String)
        case unavailable
        case failed(Error)
    }

    @State private var phase: Phase = .detecting
    @State private var summaryState: SummaryState = .idle
    @State private var summaryTask: Task<String?, Error>?
    @State private var isCreating = false
    @State private var manualStudent = ""
    @State private var manualSubject = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Lesson Draw")
                .font(.title2.bold())

            content

            HStack {
                if case .ready = phase, case .generating = summaryState {
                    ProgressView().controlSize(.small)
                    Text("Writing recap…").foregroundStyle(.secondary).font(.callout)
                }
                Spacer()
                Button("Cancel") {
                    summaryTask?.cancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button(isCreating ? "Creating…" : "Create") {
                    Task { await create() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canCreate || isCreating)
            }
        }
        .padding(20)
        .frame(width: 440)
        .task { await detect() }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch phase {
            case .detecting:
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Looking up the current lesson in Calendar…")
                        .foregroundStyle(.secondary)
                }
            case .failed(let error):
                failureView(error)
            case .ready(let plan):
                planView(plan)
        }
    }

    @ViewBuilder
    private func failureView(_ error: Error) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if error is LessonCalendarError, case .accessDenied = error as! LessonCalendarError {
#if os(macOS)
                Button("Open System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                        NSWorkspace.shared.open(url)
                    }
                }
#endif
            }

            if case LessonDrawError.titleDidNotMatch = error {
                Divider()
                TextField("Student", text: $manualStudent)
                TextField("Subject (optional)", text: $manualSubject)
                Button("Use this student") {
                    let match = LessonTitleMatch(
                        student: manualStudent.trimmingCharacters(in: .whitespaces),
                        studentPrefix: manualStudent,
                        subject: manualSubject.trimmingCharacters(in: .whitespaces).isEmpty ? nil : manualSubject
                    )
                    Task { await detect(overrideMatch: match) }
                }
                .disabled(manualStudent.trimmingCharacters(in: .whitespaces).isEmpty)
            } else {
                Button("Try again") { Task { await detect() } }
            }
        }
    }

    @ViewBuilder
    private func planView(_ plan: LessonDrawPlan) -> some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
            row("Event", plan.event.title)
            row("Student", plan.student)
            if let subject = plan.subject { row("Subject", subject) }
            row("Group", plan.groupObjectID == nil ? "\(plan.student) (will be created)" : plan.student)
            row("Previous lesson", previousLessonDescription(plan))
            row("File", plan.fileName)
            GridRow {
                Text("Recap").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                summaryView
            }
        }
    }

    @ViewBuilder
    private func row(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            Text(value).textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var summaryView: some View {
        switch summaryState {
            case .idle, .generating:
                Text("Generating…").foregroundStyle(.secondary)
            case .unavailable:
                Text("No recap: no previous lesson or no AI backend configured.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .failed(let error):
                Text("Recap failed: \(error.localizedDescription). The file will be created without it.")
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

    private func previousLessonDescription(_ plan: LessonDrawPlan) -> String {
        guard let date = plan.previousLessonDate else { return "None – this is the first lesson" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        let elements = LessonRecapBuilder.liveElements(plan.previousElements).count
        var text = formatter.string(from: date)
        if let name = plan.previousFileName { text += " (\(name))" }
        text += " · \(elements) element\(elements == 1 ? "" : "s")"
        return text
    }

    private var canCreate: Bool {
        if case .ready = phase { return true }
        return false
    }

    // MARK: - Actions

    private func detect(overrideMatch: LessonTitleMatch? = nil) async {
        phase = .detecting
        summaryTask?.cancel()
        summaryState = .idle
        do {
            let plan = try await LessonDrawCoordinator.detect(context: viewContext, overrideMatch: overrideMatch)
            phase = .ready(plan)
            startSummary(for: plan)
        } catch {
            phase = .failed(error)
        }
    }

    private func startSummary(for plan: LessonDrawPlan) {
        guard plan.recapInput != nil else {
            summaryState = .unavailable
            return
        }
        summaryState = .generating
        let task = Task<String?, Error> {
            try await LessonDrawCoordinator.summarize(plan)
        }
        summaryTask = task
        Task {
            do {
                if let text = try await task.value {
                    summaryState = .ready(text)
                } else {
                    summaryState = .unavailable
                }
            } catch is CancellationError {
                // dismissed
            } catch {
                summaryState = .failed(error)
            }
        }
    }

    private func create() async {
        guard case .ready(let plan) = phase else { return }
        isCreating = true
        defer { isCreating = false }

        var summary: String?
        if let task = summaryTask {
            summary = await withTimeout(seconds: 30) { try? await task.value } ?? nil
        }

        do {
            try await LessonDrawCoordinator.createLessonFile(
                plan: plan,
                summary: summary,
                fileState: fileState,
                context: viewContext
            )
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
