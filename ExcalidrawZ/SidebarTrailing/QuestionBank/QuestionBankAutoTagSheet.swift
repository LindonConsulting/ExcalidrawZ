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
            let topics = container.topics
            let thumbnails = Dictionary(uniqueKeysWithValues: questions.map { ($0.id, container.thumbnailPNG(for: $0.id)) })
            let overwrite = overwriteTitles
            // Up to 4 requests in flight; results applied on the main actor as they arrive.
            try await withThrowingTaskGroup(of: (Question, QuestionTagSuggestion?, String?).self) { group in
                var iterator = questions.makeIterator()
                func enqueue() {
                    guard let question = iterator.next() else { return }
                    group.addTask {
                        do {
                            let s = try await suggester.suggest(thumbnailPNG: thumbnails[question.id] ?? nil, texts: [])
                            return (question, s, nil)
                        } catch {
                            return (question, nil, error.localizedDescription)
                        }
                    }
                }
                for _ in 0..<4 { enqueue() }
                while let (original, suggestion, failure) = try await group.next() {
                    if Task.isCancelled { group.cancelAll(); log.append("Stopped."); break }
                    var question = original
                    if let suggestion {
                        QuestionTagSuggester.apply(suggestion, to: &question, topics: topics, overwriteTitle: overwrite)
                        do {
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
                            log.append("\(question.title): save failed – \(error.localizedDescription)")
                        }
                    } else {
                        log.append("\(question.title): failed – \(failure ?? "unknown error")")
                    }
                    progress += 1
                    enqueue()
                }
            }
        } catch {
            log.append(error.localizedDescription)
        }
    }
}
