//
//  QuestionBankBulkImportSheet.swift
//  ExcalidrawZ
//
//  Bulk import: one question per image file, shared metadata, optional AI
//  tagging per file.
//

import SwiftUI
import ChocofordUI
import UniformTypeIdentifiers
import TutorModels

struct QuestionBankBulkImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var container = TutorKitContainer.shared

    let urls: [URL]

    @State private var source = ""
    @State private var subject: Subject = .maths
    @State private var level: QualificationLevel? = .gcse
    @State private var board: ExamBoard?
    @State private var tier: Tier?
    @State private var topicIDs: [String] = []
    @State private var useAI = false
    @State private var skipDuplicates = true
    @State private var isRunning = false
    @State private var progress = 0
    @State private var log: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Bulk import \(urls.count) image\(urls.count == 1 ? "" : "s")").font(.title3.bold())
            Text("One question per file. The file name becomes the title unless AI tagging is on.")
                .font(.callout).foregroundStyle(.secondary)

            Form {
                TextField("Source (shared)", text: $source)
                Picker("Subject", selection: $subject) { ForEach(Subject.allCases) { Text($0.rawValue).tag($0) } }
                Picker("Level", selection: $level) {
                    Text("—").tag(QualificationLevel?.none)
                    ForEach(QualificationLevel.allCases) { Text($0.rawValue).tag(QualificationLevel?.some($0)) }
                }
                Picker("Board", selection: $board) {
                    Text("—").tag(ExamBoard?.none)
                    ForEach(ExamBoard.allCases) { Text($0.rawValue).tag(ExamBoard?.some($0)) }
                }
                Picker("Tier", selection: $tier) {
                    Text("—").tag(Tier?.none)
                    ForEach(Tier.allCases) { Text($0.rawValue).tag(Tier?.some($0)) }
                }
                HStack {
                    Text("Shared topics")
                    Menu("Choose") {
                        ForEach(container.strands.filter { $0.subject == subject }) { strand in
                            Menu(strand.name) {
                                ForEach(container.children(of: strand.id)) { topic in
                                    Button(topic.name) { if !topicIDs.contains(topic.id) { topicIDs.append(topic.id) } }
                                }
                            }
                        }
                    }.fixedSize()
                }
                FlowTags(tags: topicIDs.map(container.topicName)) { name in
                    topicIDs.removeAll { container.topicName($0) == name }
                }
                Toggle("Suggest title and tags with AI for each file", isOn: $useAI)
                    .disabled(!AnthropicAPIKeyStore.hasKey())
                Toggle("Skip files that look like existing questions", isOn: $skipDuplicates)
            }
            .formStyle(.columns)

            if isRunning || !log.isEmpty {
                ProgressView(value: Double(progress), total: Double(urls.count))
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(log.enumerated()), id: \.offset) { _, line in
                            Text(line).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 120)
            }

            HStack {
                Spacer()
                Button(isRunning ? "Close" : "Cancel") { dismiss() }.keyboardShortcut(.cancelAction).disabled(isRunning)
                Button(isRunning ? "Importing…" : "Import all") { Task { await run() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isRunning || progress == urls.count)
            }
        }
        .padding(20)
        .frame(width: 560)
        .onAppear { container.openIfNeeded() }
    }

    private func run() async {
        isRunning = true
        defer { isRunning = false }
        let suggester = useAI ? try? QuestionTagSuggester.make(topics: container.topics) : nil
        for url in urls {
            let name = url.deletingPathExtension().lastPathComponent
            do {
                let document = try QuestionBankImportDocument(url: url)
                guard let page = document.renderPage(0) else { throw QuestionBankImportDocument.ImportError.unreadable }
                let draft = try QuestionBankImportDocument.makeDraft(from: page, crop: CGRect(x: 0, y: 0, width: page.width, height: page.height), pixelsPerPoint: 2)
                var question = Question(title: name, source: source, subject: subject, level: level, board: board, tier: tier, topicIDs: topicIDs)
                if let png = draft.thumbnailPNG, let hash = QuestionImageHash.hash(png: png) {
                    question.imageHash = hash
                    if skipDuplicates, let dup = container.likelyDuplicates(ofHash: hash).first {
                        log.append("Skipped \(name): looks like “\(dup.title)”")
                        progress += 1
                        continue
                    }
                }
                if let suggester {
                    do {
                        let suggestion = try await suggester.suggest(thumbnailPNG: draft.thumbnailPNG, texts: [])
                        QuestionTagSuggester.apply(suggestion, to: &question, topics: container.topics, overwriteTitle: true)
                    } catch {
                        log.append("AI tagging failed for \(name): \(error.localizedDescription)")
                    }
                }
                try container.add(question, payload: draft.payload)
                log.append("Added “\(question.title)”")
            } catch {
                log.append("Failed \(name): \(error.localizedDescription)")
            }
            progress += 1
        }
    }
}
