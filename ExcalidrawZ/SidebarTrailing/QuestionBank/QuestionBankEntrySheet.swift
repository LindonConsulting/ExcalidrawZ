//
//  QuestionBankEntrySheet.swift
//  ExcalidrawZ
//
//  Metadata form for a captured (new) or existing question, with taxonomy
//  topic picking and AI tag suggestions.
//

import SwiftUI
import ChocofordUI
import TutorModels
import TutorStore

struct QuestionBankEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.alertToast) private var alertToast
    @ObservedObject private var container = TutorKitContainer.shared

    /// Present for a new capture; nil when editing an existing question.
    private let draft: QuestionBankCaptureDraft?
    private let onAdded: (() -> Void)?
    @State private var question: Question
    @State private var thumbnail: PlatformImage?
    @State private var topicInput = ""
    @State private var marksText = ""
    @State private var isSuggesting = false
    @State private var isSaving = false
    @State private var suggestionError: String?
    @State private var duplicateWarning: String?
    @State private var specificationID: UUID?
    @State private var specPointIDs: [UUID] = []
    private let defaultSpecificationID: UUID?

    init(draft: QuestionBankCaptureDraft, defaultSource: String = "", defaultSpecificationID: UUID? = nil, onAdded: (() -> Void)? = nil) {
        self.draft = draft
        self.onAdded = onAdded
        self.defaultSpecificationID = defaultSpecificationID
        _question = State(initialValue: Question(
            title: draft.textContent.first.map { String($0.prefix(60)) } ?? "",
            source: defaultSource
        ))
        if let png = draft.thumbnailPNG { _thumbnail = State(initialValue: PlatformImage(data: png)) }
    }

    init(question: Question) {
        self.draft = nil
        self.onAdded = nil
        self.defaultSpecificationID = nil
        _question = State(initialValue: question)
        _marksText = State(initialValue: question.marks.map(String.init) ?? "")
        if let png = TutorKitContainer.shared.thumbnailPNG(for: question.id) { _thumbnail = State(initialValue: PlatformImage(data: png)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(draft == nil ? "Edit Question" : "Add to Question Bank").font(.title2.bold())

            HStack(alignment: .top, spacing: 16) {
                thumbnailView.frame(width: 180, height: 180)
                Form {
                    TextField("Title", text: $question.title)
                    TextField("Source (paper / book / page)", text: $question.source)
                    Picker("Subject", selection: $question.subject) {
                        ForEach(Subject.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Level", selection: $question.level) {
                        Text("—").tag(QualificationLevel?.none)
                        ForEach(QualificationLevel.allCases) { Text($0.rawValue).tag(QualificationLevel?.some($0)) }
                    }
                    Picker("Board", selection: $question.board) {
                        Text("—").tag(ExamBoard?.none)
                        ForEach(ExamBoard.allCases) { Text($0.rawValue).tag(ExamBoard?.some($0)) }
                    }
                    Picker("Tier", selection: $question.tier) {
                        Text("—").tag(Tier?.none)
                        ForEach(Tier.allCases) { Text($0.rawValue).tag(Tier?.some($0)) }
                    }
                    TextField("Marks", text: $marksText)
                    Picker("Difficulty", selection: $question.difficulty) {
                        Text("—").tag(Int?.none)
                        ForEach(1...5, id: \.self) { Text(String(repeating: "●", count: $0)).tag(Int?.some($0)) }
                    }
                    TextField("Notes", text: $question.notes)
                }
                .formStyle(.columns)
            }

            topicsEditor
            specPointsEditor

            if let duplicateWarning {
                Label(duplicateWarning, systemSymbol: .exclamationmarkTriangle)
                    .font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            if let suggestionError {
                Text(suggestionError).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button { Task { await suggestTags() } } label: {
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
                    .disabled(question.title.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
            }
        }
        .padding(20)
        .frame(width: 600)
        .onAppear {
            container.openIfNeeded()
            checkForDuplicates()
            if draft == nil {
                let linked = container.specPoints(forQuestion: question.id)
                specPointIDs = linked.map(\.id)
                specificationID = linked.first?.specificationID
            } else {
                specificationID = defaultSpecificationID ?? (container.specifications.count == 1 ? container.specifications.first?.id : nil)
            }
        }
    }

    @ViewBuilder
    private var specPointsEditor: some View {
        if !container.specifications.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Specification points").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Picker("", selection: $specificationID) {
                        Text("No specification").tag(UUID?.none)
                        ForEach(container.specifications) { Text($0.displayName).tag(UUID?.some($0.id)) }
                    }
                    .labelsHidden().fixedSize()
                }
                if let specificationID, let tree = container.specificationTree(id: specificationID) {
                    let selected = tree.points.filter { specPointIDs.contains($0.id) }
                    FlowTags(tags: selected.map { "\($0.code) \($0.text.prefix(40))\($0.text.count > 40 ? "…" : "")" }) { label in
                        if let point = selected.first(where: { label.hasPrefix($0.code + " ") }) { specPointIDs.removeAll { $0 == point.id } }
                    }
                    Menu("Add spec point") {
                        ForEach(tree.sections) { section in
                            Menu(section.code.isEmpty ? section.title : "\(section.code) · \(section.title)") {
                                ForEach(tree.points(in: section)) { point in
                                    Button("\(point.code) \(point.text.prefix(70))") { if !specPointIDs.contains(point.id) { specPointIDs.append(point.id) } }
                                }
                            }
                        }
                    }
                    .fixedSize()
                }
            }
        }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(Color.white)
            RoundedRectangle(cornerRadius: 8).stroke(.separator, lineWidth: 1)
            if let thumbnail {
                Image(platformImage: thumbnail).resizable().scaledToFit().padding(6)
            } else {
                Text("No preview").foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var topicsEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Topics").font(.callout).foregroundStyle(.secondary)
            FlowTags(tags: question.topicIDs.map(container.topicName) + question.freeTags.map { "#\($0)" }) { tag in
                if tag.hasPrefix("#") {
                    question.freeTags.removeAll { "#\($0)" == tag }
                } else if let id = question.topicIDs.first(where: { container.topicName($0) == tag }) {
                    question.topicIDs.removeAll { $0 == id }
                }
            }
            HStack {
                TextField("Add topic (matches the taxonomy, otherwise a free tag)…", text: $topicInput)
                    .onSubmit(addTopicFromInput)
                Menu("Choose") {
                    ForEach(container.strands.filter { $0.subject == question.subject }) { strand in
                        Menu(strand.name) {
                            ForEach(container.children(of: strand.id)) { topic in
                                Button(topic.name) { addTopic(topic.id) }
                            }
                        }
                    }
                }
                .fixedSize()
            }
        }
    }

    private func addTopicFromInput() {
        let raw = topicInput.trimmingCharacters(in: .whitespaces)
        topicInput = ""
        guard !raw.isEmpty else { return }
        if let topic = container.resolveTopic(raw), topic.parentID != nil {
            addTopic(topic.id)
        } else if !question.freeTags.contains(where: { $0.caseInsensitiveCompare(raw) == .orderedSame }) {
            question.freeTags.append(raw)
        }
    }

    private func addTopic(_ id: String) {
        if !question.topicIDs.contains(id) { question.topicIDs.append(id) }
    }

    private func checkForDuplicates() {
        guard let draft, let png = draft.thumbnailPNG, let hash = QuestionImageHash.hash(png: png) else { return }
        question.imageHash = hash
        let matches = container.likelyDuplicates(ofHash: hash)
        guard let first = matches.first else { return }
        let when = first.createdAt.formatted(date: .abbreviated, time: .omitted)
        duplicateWarning = matches.count == 1
            ? "Looks like a duplicate of “\(first.title)” (added \(when))."
            : "Looks like a duplicate of “\(first.title)” and \(matches.count - 1) other\(matches.count == 2 ? "" : "s")."
    }

    private func suggestTags() async {
        isSuggesting = true
        suggestionError = nil
        defer { isSuggesting = false }
        do {
            let tree = specificationID.flatMap { container.specificationTree(id: $0) }
            let suggester = try QuestionTagSuggester.make(topics: container.topics, specPoints: tree?.points ?? [])
            let png = draft?.thumbnailPNG ?? container.thumbnailPNG(for: question.id)
            let suggestion = try await suggester.suggest(thumbnailPNG: png, texts: draft?.textContent ?? [])
            QuestionTagSuggester.apply(suggestion, to: &question, topics: container.topics, overwriteTitle: draft != nil)
            if let tree {
                for code in suggestion.specPoints ?? [] {
                    if let point = tree.points.first(where: { $0.code.caseInsensitiveCompare(code) == .orderedSame }), !specPointIDs.contains(point.id) {
                        specPointIDs.append(point.id)
                    }
                }
            }
            if marksText.isEmpty, let marks = question.marks { marksText = String(marks) }
        } catch {
            suggestionError = error.localizedDescription
        }
    }

    private func save() {
        isSaving = true
        defer { isSaving = false }
        question.marks = Int(marksText.trimmingCharacters(in: .whitespaces))
        question.title = question.title.trimmingCharacters(in: .whitespaces)
        do {
            if let draft {
                try container.add(question, payload: draft.payload)
                try container.setSpecPoints(specPointIDs, forQuestion: question.id)
                alertToast(.init(displayMode: .hud, type: .complete(.green), title: "Added to Question Bank"))
                onAdded?()
            } else {
                try container.update(question)
                try container.setSpecPoints(specPointIDs, forQuestion: question.id)
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
                    .padding(.horizontal, 8).padding(.vertical, 3)
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
