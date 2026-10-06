//
//  QuestionBankPastPaperImportSheet.swift
//  ExcalidrawZ
//
//  Imports whole exam papers: splits each PDF into questions with the
//  existing past-paper analyzer, renders one image per question, and adds
//  them to the bank with the paper as source. Optionally auto-tags after.
//

import SwiftUI
import ChocofordUI
import PDFKit
import TutorModels
import TutorAI

struct QuestionBankPastPaperImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var container = TutorKitContainer.shared

    let urls: [URL]

    @State private var subject: Subject = .maths
    @State private var level: QualificationLevel? = .gcse
    @State private var board: ExamBoard?
    @State private var tier: Tier?
    @State private var autoTag = true
    @State private var specificationID: UUID?
    @State private var skipDuplicates = true
    @State private var isRunning = false
    @State private var progress = 0
    @State private var total = 0
    @State private var log: [String] = []
    @State private var task: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import \(urls.count) past paper\(urls.count == 1 ? "" : "s")").font(.title2.bold())
            Text("Each paper is split into questions (one image each, answer space trimmed). The file name becomes the source; the question number becomes the title.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ForEach(urls, id: \.self) { url in
                Text(url.deletingPathExtension().lastPathComponent).font(.caption).foregroundStyle(.secondary)
            }

            Form {
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
                    ForEach([Tier.foundation, .higher]) { Text($0.rawValue).tag(Tier?.some($0)) }
                }
                Toggle("Skip questions that look like existing ones", isOn: $skipDuplicates)
                Toggle("Auto-tag with AI after importing", isOn: $autoTag).disabled(!AnthropicAPIKeyStore.hasKey())
                if autoTag {
                    Picker("Specification for tagging", selection: $specificationID) {
                        Text("None (topics only)").tag(UUID?.none)
                        ForEach(container.specifications) { Text($0.displayName).tag(UUID?.some($0.id)) }
                    }
                }
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
                .frame(height: 150)
            }

            HStack {
                Spacer()
                Button(isRunning ? "Stop" : "Close") { if isRunning { task?.cancel() } else { dismiss() } }.keyboardShortcut(.cancelAction)
                Button(isRunning ? "Importing…" : "Import") { task = Task { await run() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isRunning || progress > 0)
            }
        }
        .padding(20)
        .frame(width: 600)
        .onAppear {
            container.openIfNeeded()
            guess()
            if specificationID == nil, container.specifications.count == 1 { specificationID = container.specifications.first?.id }
        }
    }

    /// Board/tier from the path ("wjec_gcse/Unit-1H/June 2022 QP.pdf").
    private func guess() {
        let path = urls.first?.path.lowercased() ?? ""
        for candidate in ExamBoard.allCases where path.contains(candidate.rawValue.lowercased()) { board = candidate }
        if path.contains("higher") || path.range(of: #"-[0-9]h\b"#, options: .regularExpression) != nil || path.range(of: #"[0-9]h[/ ]"#, options: .regularExpression) != nil { tier = .higher }
        if path.contains("foundation") || path.range(of: #"-[0-9]f\b"#, options: .regularExpression) != nil || path.range(of: #"[0-9]f[/ ]"#, options: .regularExpression) != nil { tier = .foundation }
        if path.contains("a-level") || path.contains("alevel") || path.contains("a_level") { level = .aLevel }
        if path.contains("computer") || path.contains("comp-sci") || path.contains("/cs/") { subject = .computerScience }
    }

    private func run() async {
        isRunning = true
        defer { isRunning = false }
        log = []
        var added: [Question] = []

        // Split and render on a background thread.
        struct Rendered { var question: PastPaperQuestion; var png: Data; var size: CGSize; var paper: String }
        var rendered: [Rendered] = []
        for url in urls {
            let paper = url.deletingPathExtension().lastPathComponent
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            guard let document = PDFDocument(url: url) else { log.append("\(paper): could not open"); continue }
            let analysis = PastPaperAnalyzer.analyze(document)
            if analysis.source == .pagesFallback { log.append("\(paper): no question numbers found in the text layer, using whole pages") }
            for question in analysis.questions {
                do {
                    let image = try PastPaperRenderer.render(question, in: document)
                    rendered.append(Rendered(question: question, png: image.pngData, size: image.pointSize, paper: paper))
                } catch {
                    log.append("\(paper) \(question.label): \(error.localizedDescription)")
                }
            }
            log.append("\(paper): \(analysis.questions.count) questions found")
        }
        total = rendered.count
        progress = 0

        for item in rendered {
            if Task.isCancelled { log.append("Stopped."); break }
            do {
                let draft = try QuestionBankImportDocument.makeDraft(png: item.png, pointSize: item.size)
                var question = Question(title: "\(item.paper) \(item.question.label)", source: item.paper, subject: subject, level: level, board: board, tier: tier)
                if let hash = QuestionImageHash.hash(png: item.png) {
                    question.imageHash = hash
                    if skipDuplicates, let dup = container.likelyDuplicates(ofHash: hash).first {
                        log.append("Skipped \(question.title): looks like “\(dup.title)”")
                        progress += 1
                        continue
                    }
                }
                try container.add(question, payload: draft.payload)
                added.append(question)
            } catch {
                log.append("\(item.paper) \(item.question.label): \(error.localizedDescription)")
            }
            progress += 1
        }
        log.append("Added \(added.count) questions.")

        guard autoTag, !added.isEmpty, !Task.isCancelled else { return }
        let tree = specificationID.flatMap { container.specificationTree(id: $0) }
        guard let suggester = try? QuestionTagSuggester.make(topics: container.topics, specPoints: tree?.points ?? []) else {
            log.append("Auto-tag skipped: no API key.")
            return
        }
        total = added.count
        progress = 0
        for var question in added {
            if Task.isCancelled { log.append("Stopped."); break }
            do {
                let suggestion = try await suggester.suggest(thumbnailPNG: container.thumbnailPNG(for: question.id), texts: [])
                QuestionTagSuggester.apply(suggestion, to: &question, topics: container.topics, overwriteTitle: false)
                if let title = suggestion.title, !title.isEmpty { question.title = "\(question.title) – \(title)" }
                try container.update(question)
                if let tree {
                    let ids = (suggestion.specPoints ?? []).compactMap { code in tree.points.first { $0.code.caseInsensitiveCompare(code) == .orderedSame }?.id }
                    try container.setSpecPoints(ids, forQuestion: question.id)
                    log.append("Tagged \(question.title): \(ids.count) spec points")
                } else {
                    log.append("Tagged \(question.title)")
                }
            } catch {
                log.append("Tagging failed for \(question.title): \(error.localizedDescription)")
            }
            progress += 1
        }
    }
}
