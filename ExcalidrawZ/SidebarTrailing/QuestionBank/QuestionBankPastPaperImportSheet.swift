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

    /// Question papers found in `urls` (folders are searched recursively; mark schemes skipped).
    private var papers: [URL] {
        var result: [URL] = []
        let fm = FileManager.default
        for url in urls {
            var isDirectory: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                    for case let file as URL in enumerator where file.pathExtension.lowercased() == "pdf" {
                        let name = file.deletingPathExtension().lastPathComponent.lowercased()
                        let isMarkScheme = name.contains(" ms") || name.hasSuffix("ms") || name.contains("mark scheme") || name.contains("markscheme")
                        let isSpec = file.path.lowercased().contains("_specs") || name.contains("spec")
                        if !isMarkScheme, !isSpec { result.append(file) }
                    }
                }
            } else if url.pathExtension.lowercased() == "pdf" {
                result.append(url)
            }
        }
        return result.sorted { $0.path < $1.path }
    }

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
            Text("Import \(papers.count) past paper\(papers.count == 1 ? "" : "s")").font(.title2.bold())
            Text("Each paper is split into questions (one image each, answer space trimmed). The file name becomes the source; the question number becomes the title. Folders are searched for question papers; mark schemes are skipped. Board and tier are guessed per file from the path (e.g. Unit-1H → Higher).")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(papers, id: \.self) { url in
                        Text(url.deletingLastPathComponent().lastPathComponent + " / " + url.deletingPathExtension().lastPathComponent)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 90)

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
                Picker(papers.count > 1 ? "Tier (fallback when not in the path)" : "Tier", selection: $tier) {
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

    private struct PathGuess { var board: ExamBoard?; var tier: Tier?; var level: QualificationLevel?; var subject: Subject? }

    /// Board/tier/level/subject from a path ("wjec_gcse/Unit-1H/June 2022 QP.pdf").
    private static func guess(path rawPath: String) -> PathGuess {
        let path = rawPath.lowercased()
        var g = PathGuess()
        for candidate in ExamBoard.allCases where path.contains(candidate.rawValue.lowercased()) { g.board = candidate }
        if path.contains("higher") || path.range(of: #"[-_ ]?[0-9]h\b"#, options: .regularExpression) != nil { g.tier = .higher }
        if path.contains("foundation") || path.range(of: #"[-_ ]?[0-9]f\b"#, options: .regularExpression) != nil { g.tier = .foundation }
        if path.contains("intermediate") || path.range(of: #"[-_ ]?[0-9]i\b"#, options: .regularExpression) != nil { g.tier = nil }
        if path.contains("a-level") || path.contains("alevel") || path.contains("a_level") { g.level = .aLevel }
        if path.contains("gcse") { g.level = .gcse }
        if path.contains("computer") || path.contains("comp-sci") || path.contains("/cs/") { g.subject = .computerScience }
        return g
    }

    private func guess() {
        guard let first = papers.first else { return }
        let g = Self.guess(path: first.path)
        if let b = g.board { board = b }
        tier = g.tier
        if let l = g.level { level = l }
        if let s = g.subject { subject = s }
    }

    private func run() async {
        isRunning = true
        defer { isRunning = false }
        log = []
        var added: [Question] = []

        // Split and render on a background thread.
        struct Rendered { var question: PastPaperQuestion; var png: Data; var size: CGSize; var paper: String; var tier: Tier? }
        var rendered: [Rendered] = []
        for url in papers {
            let paper = url.deletingPathExtension().lastPathComponent
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            guard let document = PDFDocument(url: url) else { log.append("\(paper): could not open"); continue }
            let analysis = PastPaperAnalyzer.analyze(document)
            if analysis.source == .pagesFallback { log.append("\(paper): no question numbers found in the text layer, using whole pages") }
            for question in analysis.questions {
                do {
                    let image = try PastPaperRenderer.render(question, in: document)
                    rendered.append(Rendered(question: question, png: image.pngData, size: image.pointSize, paper: paper,
                                             tier: papers.count > 1 ? Self.guess(path: url.path).tier ?? tier : tier))
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
                var question = Question(title: "\(item.paper) \(item.question.label)", source: item.paper, subject: subject, level: level, board: board, tier: item.tier)
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
