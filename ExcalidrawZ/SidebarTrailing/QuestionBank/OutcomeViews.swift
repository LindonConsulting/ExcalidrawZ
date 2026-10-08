//
//  OutcomeViews.swift
//  ExcalidrawZ
//
//  Recording how a shown question went: inline quick buttons and the
//  lesson review sheet.
//

import SwiftUI
import ChocofordUI
import TutorModels

/// Right / Partly / Wrong / Skipped buttons for one outcome.
struct OutcomeQuickButtons: View {
    @Environment(\.alertToast) private var alertToast
    @ObservedObject private var container = TutorKitContainer.shared
    let outcome: Outcome
    var compact = true

    var body: some View {
        HStack(spacing: 4) {
            button(.right, "checkmark", .green)
            button(.partial, "plusminus", .orange)
            button(.wrong, "xmark", .red)
            button(.skipped, "arrow.uturn.forward", .secondary)
        }
        .controlSize(.small)
    }

    private func button(_ result: OutcomeResult, _ symbol: String, _ color: Color) -> some View {
        Button {
            do { try container.setResult(result, for: outcome.id) } catch { alertToast(error) }
        } label: {
            if compact {
                Image(systemName: symbol).foregroundStyle(color)
            } else {
                Label(result.title, systemImage: symbol).foregroundStyle(color)
            }
        }
        .help(result.title)
    }
}

/// Review every question shown in a lesson (or to a student) and record results.
struct LessonReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.alertToast) private var alertToast
    @ObservedObject private var container = TutorKitContainer.shared

    var lessonFileID: String?
    var studentID: UUID?
    var title: String

    @State private var difficulty: [UUID: Int] = [:]

    private var pending: [Outcome] { container.pendingOutcomes(lessonFileID: lessonFileID, studentID: studentID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title2.bold())
            if pending.isEmpty {
                Center {
                    VStack(spacing: 8) {
                        Image(systemSymbol: .checkmarkCircle).font(.largeTitle).foregroundStyle(.green)
                        Text("All questions have a result.").font(.headline)
                    }
                }
            } else {
                Text("\(pending.count) question\(pending.count == 1 ? "" : "s") without a result. Tap how it went; difficulty is optional.")
                    .font(.callout).foregroundStyle(.secondary)
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(pending) { outcome in row(outcome) }
                    }
                }
            }
            HStack {
                if !pending.isEmpty {
                    Button("Mark all right") { markAll(.right) }
                    Button("Skip remaining") { markAll(.skipped) }
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 620, minHeight: 420)
    }

    @ViewBuilder
    private func row(_ outcome: Outcome) -> some View {
        let question = container.questions.first { $0.id == outcome.questionID }
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(Color.white)
                if let png = container.thumbnailPNG(for: outcome.questionID), let image = PlatformImage(data: png) {
                    Image(platformImage: image).resizable().scaledToFit().padding(4)
                }
            }
            .frame(width: 120, height: 80)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator, lineWidth: 1))

            VStack(alignment: .leading, spacing: 6) {
                Text(question?.title ?? "Question").font(.headline).lineLimit(2)
                Text("\(container.studentName(for: outcome.studentID)) · \(outcome.shownAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    OutcomeQuickButtons(outcome: outcome, compact: false)
                    Spacer()
                    Picker("Felt", selection: Binding(
                        get: { difficulty[outcome.id] ?? outcome.perceivedDifficulty ?? 0 },
                        set: { value in
                            difficulty[outcome.id] = value
                            do { try container.setResult(outcome.result, difficulty: value == 0 ? nil : value, for: outcome.id) } catch { alertToast(error) }
                        }
                    )) {
                        Text("—").tag(0)
                        ForEach(1...5, id: \.self) { Text(String(repeating: "●", count: $0)).tag($0) }
                    }
                    .fixedSize()
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
    }

    private func markAll(_ result: OutcomeResult) {
        for outcome in pending {
            do { try container.setResult(result, for: outcome.id) } catch { alertToast(error) }
        }
    }
}
