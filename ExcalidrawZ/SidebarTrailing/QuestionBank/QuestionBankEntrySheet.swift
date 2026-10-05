//
//  QuestionBankEntrySheet.swift
//  ExcalidrawZ
//
//  Metadata form for a captured (new) or existing question, with AI tag
//  suggestions.
//

import SwiftUI
import ChocofordUI
import os

private let qbLogger = os.Logger(subsystem: "com.lindon.questionbank", category: "sheet")

struct QuestionBankEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.alertToast) private var alertToast
    @ObservedObject private var store = QuestionBankStore.shared

    /// Present for a new capture; nil when editing an existing entry.
    private let draft: QuestionBankCaptureDraft?
    @State private var entry: QuestionBankEntry
    @State private var thumbnail: PlatformImage?
    @State private var topicInput = ""
    @State private var marksText = ""
    @State private var isSuggesting = false
    @State private var isSaving = false
    @State private var suggestionError: String?
    @State private var duplicateWarning: String?

    private let onAdded: (() -> Void)?

    init(draft: QuestionBankCaptureDraft, defaultSource: String = "", onAdded: (() -> Void)? = nil) {
        self.draft = draft
        self.onAdded = onAdded
        _entry = State(initialValue: QuestionBankEntry(
            title: draft.textContent.first.map { String($0.prefix(60)) } ?? "",
            source: defaultSource
        ))
        if let png = draft.thumbnailPNG {
            _thumbnail = State(initialValue: PlatformImage(data: png))
        }
    }

    init(entry: QuestionBankEntry) {
        self.draft = nil
        self.onAdded = nil
        _entry = State(initialValue: entry)
        _marksText = State(initialValue: entry.marks.map(String.init) ?? "")
        if let png = QuestionBankStore.shared.thumbnailPNG(for: entry.id) {
            _thumbnail = State(initialValue: PlatformImage(data: png))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(draft == nil ? "Edit Question" : "Add to Question Bank")
                .font(.title2.bold())

            HStack(alignment: .top, spacing: 16) {
                thumbnailView
                    .frame(width: 180, height: 180)

                Form {
                    TextField("Title", text: $entry.title)
                    TextField("Source (paper / book / page)", text: $entry.source)
                    Picker("Board", selection: $entry.board) {
                        Text("—").tag("")
                        ForEach(QuestionBankTaxonomy.boards, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Tier", selection: $entry.tier) {
                        Text("—").tag("")
                        ForEach(QuestionBankTaxonomy.tiers, id: \.self) { Text($0).tag($0) }
                    }
                    TextField("Marks", text: $marksText)
                    TextField("Notes", text: $entry.notes)
                }
                .formStyle(.columns)
            }

            topicsEditor

            if let duplicateWarning {
                Label(duplicateWarning, systemSymbol: .exclamationmarkTriangle)
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let suggestionError {
                Text(suggestionError)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button {
                    Task { await suggestTags() }
                } label: {
                    if isSuggesting {
                        HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Suggesting…") }
                    } else {
                        Label("Suggest tags", systemSymbol: .sparkles)
                    }
                }
                .disabled(isSuggesting)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(draft == nil ? "Save" : "Add") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(entry.title.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
            }
        }
        .padding(20)
        .frame(width: 560)
        .onAppear(perform: checkForDuplicates)
    }

    private func checkForDuplicates() {
        guard let draft, let png = draft.thumbnailPNG, let hash = QuestionImageHash.hash(png: png) else { return }
        entry.imageHash = hash
        let matches = store.likelyDuplicates(ofHash: hash)
        guard let first = matches.first else { return }
        let when = first.createdAt.formatted(date: .abbreviated, time: .omitted)
        duplicateWarning = matches.count == 1
            ? "Looks like a duplicate of “\(first.title)” (added \(when))."
            : "Looks like a duplicate of “\(first.title)” and \(matches.count - 1) other\(matches.count == 2 ? "" : "s")."
    }

    @ViewBuilder
    private var thumbnailView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(Color.white)
            RoundedRectangle(cornerRadius: 8).stroke(.separator, lineWidth: 1)
            if let thumbnail {
                Image(platformImage: thumbnail)
                    .resizable()
                    .scaledToFit()
                    .padding(6)
            } else {
                Text("No preview").foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var topicsEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Topics").font(.callout).foregroundStyle(.secondary)
            FlowTags(tags: entry.topics) { tag in
                entry.topics.removeAll { $0 == tag }
            }
            HStack {
                TextField("Add topic…", text: $topicInput)
                    .onSubmit(addTopicFromInput)
                Menu {
                    ForEach(QuestionBankTaxonomy.topics, id: \.self) { topic in
                        Button(topic) { addTopic(topic) }
                    }
                } label: {
                    Text("Choose")
                }
                .fixedSize()
            }
        }
    }

    private func addTopicFromInput() {
        addTopic(topicInput)
        topicInput = ""
    }

    private func addTopic(_ raw: String) {
        let topic = raw.trimmingCharacters(in: .whitespaces)
        guard !topic.isEmpty, !entry.topics.contains(where: { $0.caseInsensitiveCompare(topic) == .orderedSame }) else { return }
        entry.topics.append(topic)
    }

    private func suggestTags() async {
        isSuggesting = true
        suggestionError = nil
        defer { isSuggesting = false }
        do {
            let suggester = try QuestionTagSuggester.make()
            let png = draft?.thumbnailPNG ?? store.thumbnailPNG(for: entry.id)
            let suggestion = try await suggester.suggest(thumbnailPNG: png, texts: draft?.textContent ?? [])
            if entry.title.trimmingCharacters(in: .whitespaces).isEmpty, let title = suggestion.title { entry.title = title }
            if let title = suggestion.title, draft != nil { entry.title = title }
            for topic in suggestion.topics ?? [] { addTopic(topic) }
            if entry.board.isEmpty, let board = suggestion.board, QuestionBankTaxonomy.boards.contains(board) { entry.board = board }
            if entry.tier.isEmpty, let tier = suggestion.tier, QuestionBankTaxonomy.tiers.contains(tier) { entry.tier = tier }
            if marksText.isEmpty, let marks = suggestion.marks { marksText = String(marks) }
            if entry.source.isEmpty, let source = suggestion.source { entry.source = source }
        } catch {
            qbLogger.error("suggest failed: \(error.localizedDescription, privacy: .public)")
            suggestionError = error.localizedDescription
        }
    }

    private func save() {
        isSaving = true
        defer { isSaving = false }
        entry.marks = Int(marksText.trimmingCharacters(in: .whitespaces))
        entry.title = entry.title.trimmingCharacters(in: .whitespaces)
        do {
            if let draft {
                try store.add(entry, elementsJSON: draft.elementsJSON, filesJSON: draft.filesJSON, thumbnailPNG: draft.thumbnailPNG)
                alertToast(.init(displayMode: .hud, type: .complete(.green), title: "Added to Question Bank"))
                onAdded?()
            } else {
                try store.update(entry)
            }
            dismiss()
        } catch {
            alertToast(error)
        }
    }
}

/// Simple wrapping tag row.
struct FlowTags: View {
    var tags: [String]
    var onRemove: ((String) -> Void)?

    var body: some View {
        if tags.isEmpty {
            Text("No topics yet").font(.callout).foregroundStyle(.tertiary)
        } else {
            FlowLayoutStack(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    HStack(spacing: 4) {
                        Text(tag).font(.callout)
                        if let onRemove {
                            Button { onRemove(tag) } label: { Image(systemSymbol: .xmark).font(.caption2) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.15), in: Capsule())
                }
            }
        }
    }
}

/// Minimal flow layout (macOS 13+ `Layout`).
struct FlowLayoutStack: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 400
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX, y: CGFloat = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
