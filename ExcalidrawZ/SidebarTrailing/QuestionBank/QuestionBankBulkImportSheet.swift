//
//  QuestionBankBulkImportSheet.swift
//  ExcalidrawZ
//
//  Bulk import: one question per image file, with shared metadata and
//  optional AI tagging per file.
//

import SwiftUI
import ChocofordUI
import UniformTypeIdentifiers

struct QuestionBankBulkImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = QuestionBankStore.shared

    let urls: [URL]

    @State private var source = ""
    @State private var board = ""
    @State private var tier = ""
    @State private var topics: [String] = []
    @State private var topicInput = ""
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
                Picker("Board", selection: $board) {
                    Text("—").tag("")
                    ForEach(QuestionBankTaxonomy.boards, id: \.self) { Text($0).tag($0) }
                }
                Picker("Tier", selection: $tier) {
                    Text("—").tag("")
                    ForEach(QuestionBankTaxonomy.tiers, id: \.self) { Text($0).tag($0) }
                }
                HStack {
                    TextField("Shared topic…", text: $topicInput).onSubmit(addTopic)
                    Menu("Choose") {
                        ForEach(QuestionBankTaxonomy.topics, id: \.self) { topic in
                            Button(topic) { topicInput = topic; addTopic() }
                        }
                    }.fixedSize()
                }
                FlowTags(tags: topics) { tag in topics.removeAll { $0 == tag } }
                Toggle("Suggest title and tags with AI for each file", isOn: $useAI)
                    .disabled(!AnthropicAPIKeyStore().hasKey())
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
                Button(isRunning ? "Close" : "Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isRunning)
                Button(isRunning ? "Importing…" : "Import all") { Task { await run() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isRunning || progress == urls.count)
            }
        }
        .padding(20)
        .frame(width: 560)
    }

    private func addTopic() {
        let value = topicInput.trimmingCharacters(in: .whitespaces)
        if !value.isEmpty, !topics.contains(value) { topics.append(value) }
        topicInput = ""
    }

    private func run() async {
        isRunning = true
        defer { isRunning = false }
        let suggester = useAI ? try? QuestionTagSuggester.make() : nil
        for url in urls {
            let name = url.deletingPathExtension().lastPathComponent
            do {
                let document = try QuestionBankImportDocument(url: url)
                guard let page = document.renderPage(0) else { throw QuestionBankImportDocument.ImportError.unreadable }
                let draft = try QuestionBankImportDocument.makeDraft(
                    from: page,
                    crop: CGRect(x: 0, y: 0, width: page.width, height: page.height),
                    pixelsPerPoint: 2
                )
                var entry = QuestionBankEntry(title: name, source: source, topics: topics, board: board, tier: tier)
                if let png = draft.thumbnailPNG, let hash = QuestionImageHash.hash(png: png) {
                    entry.imageHash = hash
                    if skipDuplicates, let dup = store.likelyDuplicates(ofHash: hash).first {
                        log.append("Skipped \(name): looks like “\(dup.title)”")
                        progress += 1
                        continue
                    }
                }
                if let suggester {
                    do {
                        let suggestion = try await suggester.suggest(thumbnailPNG: draft.thumbnailPNG, texts: [])
                        if let title = suggestion.title, !title.isEmpty { entry.title = title }
                        for topic in suggestion.topics ?? [] where !entry.topics.contains(topic) { entry.topics.append(topic) }
                        if entry.board.isEmpty, let value = suggestion.board { entry.board = value }
                        if entry.tier.isEmpty, let value = suggestion.tier { entry.tier = value }
                        if entry.marks == nil { entry.marks = suggestion.marks }
                        if entry.source.isEmpty, let value = suggestion.source { entry.source = value }
                    } catch {
                        log.append("AI tagging failed for \(name): \(error.localizedDescription)")
                    }
                }
                try store.add(entry, elementsJSON: draft.elementsJSON, filesJSON: draft.filesJSON, thumbnailPNG: draft.thumbnailPNG)
                log.append("Added “\(entry.title)”")
            } catch {
                log.append("Failed \(name): \(error.localizedDescription)")
            }
            progress += 1
        }
    }
}
