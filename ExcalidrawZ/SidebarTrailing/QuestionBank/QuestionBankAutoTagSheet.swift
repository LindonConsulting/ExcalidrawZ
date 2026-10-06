//
//  QuestionBankAutoTagSheet.swift
//  ExcalidrawZ
//
//  Bulk AI tagging: runs the tag suggester over questions that have no spec
//  points (or all), against a chosen specification.
//

import SwiftUI
import ChocofordUI
import TutorModels
import TutorAI

struct QuestionBankAutoTagSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var container = TutorKitContainer.shared

    @State private var specificationID: UUID?
    @State private var onlyUntagged = true
    @State private var overwriteTitles = false
    @State private var isRunning = false
    @State private var progress = 0
    @State private var total = 0
    @State private var log: [String] = []
    @State private var task: Task<Void, Never>?

    private var targets: [Question] {
        container.questions.filter { !onlyUntagged || (container.specPointsByQuestion[$0.id] ?? []).isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Auto-tag questions").font(.title2.bold())
            Text("Sends each question's image to the AI and fills in title (optional), topics, board, tier, marks, difficulty and matching specification points.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            Form {
                Picker("Specification", selection: $specificationID) {
                    Text("None (topics only)").tag(UUID?.none)
                    ForEach(container.specifications) { Text($0.displayName).tag(UUID?.some($0.id)) }
                }
                Toggle("Only questions with no spec points yet", isOn: $onlyUntagged)
                Toggle("Replace existing titles with AI titles", isOn: $overwriteTitles)
                LabeledContent("Questions to process", value: "\(targets.count)")
            }
            .formStyle(.columns)

            if isRunning || !log.isEmpty {
                ProgressView(value: Double(progress), total: Double(max(total, 1)))
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(log.enumerated()), id: \.offset) { _, line in
                            Text(line).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 140)
            }

            HStack {
                Spacer()
                Button(isRunning ? "Stop" : "Close") { if isRunning { task?.cancel() } else { dismiss() } }
                    .keyboardShortcut(.cancelAction)
                Button(isRunning ? "Tagging…" : "Tag \(targets.count) question\(targets.count == 1 ? "" : "s")") { task = Task { await run() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isRunning || targets.isEmpty || !AnthropicAPIKeyStore.hasKey())
            }
        }
        .padding(20)
        .frame(width: 560)
        .onAppear {
            container.openIfNeeded()
            if specificationID == nil, container.specifications.count == 1 { specificationID = container.specifications.first?.id }
        }
    }

    private func run() async {
        isRunning = true
        defer { isRunning = false }
        let tree = specificationID.flatMap { container.specificationTree(id: $0) }
        let questions = targets
        total = questions.count
        progress = 0
        log = []
        do {
            let suggester = try QuestionTagSuggester.make(topics: container.topics, specPoints: tree?.points ?? [])
            for var question in questions {
                if Task.isCancelled { log.append("Stopped."); break }
                do {
                    let suggestion = try await suggester.suggest(thumbnailPNG: container.thumbnailPNG(for: question.id), texts: [])
                    QuestionTagSuggester.apply(suggestion, to: &question, topics: container.topics, overwriteTitle: overwriteTitles)
                    try container.update(question)
                    if let tree {
                        let existing = container.specPointsByQuestion[question.id] ?? []
                        let matched = (suggestion.specPoints ?? []).compactMap { code in
                            tree.points.first { $0.code.caseInsensitiveCompare(code) == .orderedSame }?.id
                        }
                        try container.setSpecPoints(Array(Set(existing + matched)), forQuestion: question.id)
                        log.append("\(question.title): \(matched.count) spec point\(matched.count == 1 ? "" : "s"), \(question.topicIDs.count) topics")
                    } else {
                        log.append("\(question.title): \(question.topicIDs.count) topics")
                    }
                } catch {
                    log.append("\(question.title): failed – \(error.localizedDescription)")
                }
                progress += 1
            }
        } catch {
            log.append(error.localizedDescription)
        }
    }
}
