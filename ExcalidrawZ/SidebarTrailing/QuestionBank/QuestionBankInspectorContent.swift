//
//  QuestionBankInspectorContent.swift
//  ExcalidrawZ
//
//  Trailing-sidebar panel: browse, filter and insert stored questions.
//

import SwiftUI
import ChocofordUI
import UniformTypeIdentifiers
import TutorModels

extension Notification.Name {
    static let shouldCaptureQuestionBankSelection = Notification.Name("ShouldCaptureQuestionBankSelection")
}

struct QuestionBankInspectorContent: View {
    @Environment(\.alertToast) private var alertToast
    @EnvironmentObject private var fileState: FileState
    @ObservedObject private var container = TutorKitContainer.shared

    @State private var query = ""
    @State private var hideUsedByCurrentStudent = true
    @State private var strandFilter = ""
    @State private var editingQuestion: Question?
    @State private var deletingQuestion: Question?
    @State private var insertingID: UUID?
    @State private var isImporterPresented = false
    @State private var importDocument: QuestionBankImportDocument?
    @State private var bulkImportURLs: [URL]?
    @State private var isReviewPresented = false
    @State private var isAutoTagPresented = false
    @State private var isPaperImporterPresented = false
    @State private var paperImportURLs: [URL]?

    private var currentStudent: String? {
        if case .file(let file) = fileState.currentActiveFile, let name = file.group?.name, !name.isEmpty { return name }
        return nil
    }

    private var currentFileID: String? { fileState.currentActiveFile?.id }

    private var filtered: [Question] {
        let names = container.topicNames
        return container.questions.filter { question in
            guard question.matches(query: query, topicNames: names) else { return false }
            if !strandFilter.isEmpty, !question.topicIDs.contains(where: { $0.hasPrefix(strandFilter + ".") || $0 == strandFilter }) { return false }
            if hideUsedByCurrentStudent, let student = currentStudent, container.hasBeenShown(question.id, to: student) { return false }
            return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let error = container.openError {
                Center { Text(error.localizedDescription).foregroundStyle(.red).padding() }
            } else if container.questions.isEmpty {
                emptyState
            } else if filtered.isEmpty {
                Center { Text("No questions match.").foregroundStyle(.secondary) }
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filtered) { question in card(question) }
                    }
                    .padding(12)
                }
            }
        }
        .onAppear { container.openIfNeeded() }
        .fileImporterWithAlert(isPresented: $isImporterPresented, allowedContentTypes: [.pdf, .png, .jpeg], allowsMultipleSelection: true) { urls in
            try await handleImport(urls: urls)
        }
        .onDrop(of: [.pdf, .png, .jpeg, .fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in try? await handleImport(urls: [url]) }
            }
            return true
        }
        .sheet(item: $importDocument) { document in QuestionBankImportSheet(document: document) }
        .sheet(isPresented: Binding(get: { bulkImportURLs != nil }, set: { if !$0 { bulkImportURLs = nil } })) {
            QuestionBankBulkImportSheet(urls: bulkImportURLs ?? [])
        }
        .sheet(item: $editingQuestion) { question in QuestionBankEntrySheet(question: question) }
        .sheet(isPresented: $isAutoTagPresented) { QuestionBankAutoTagSheet() }
        .fileImporterWithAlert(isPresented: $isPaperImporterPresented, allowedContentTypes: [.pdf, .folder], allowsMultipleSelection: true) { urls in
            await MainActor.run { paperImportURLs = urls }
        }
        .sheet(isPresented: Binding(get: { paperImportURLs != nil }, set: { if !$0 { paperImportURLs = nil } })) {
            QuestionBankPastPaperImportSheet(urls: paperImportURLs ?? [])
        }
        .sheet(isPresented: $isReviewPresented) {
            LessonReviewSheet(lessonFileID: currentFileID, title: "Lesson review\(currentStudent.map { " · \($0)" } ?? "")")
        }
        .confirmationDialog(
            "Delete “\(deletingQuestion?.title ?? "")” from the question bank?",
            isPresented: Binding(get: { deletingQuestion != nil }, set: { if !$0 { deletingQuestion = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let question = deletingQuestion {
                    do { try container.deleteQuestion(id: question.id) } catch { alertToast(error) }
                }
                deletingQuestion = nil
            }
        }
    }

    @MainActor
    private func handleImport(urls: [URL]) async throws {
        guard !urls.isEmpty else { return }
        let isAllImages = urls.allSatisfy { UTType(filenameExtension: $0.pathExtension)?.conforms(to: .image) == true }
        if urls.count > 1, isAllImages { bulkImportURLs = urls } else { importDocument = try QuestionBankImportDocument(url: urls[0]) }
    }

    @ViewBuilder
    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                TextField("Search title, source, topic, student…", text: $query).textFieldStyle(.roundedBorder)
                Button {
                    NotificationCenter.default.post(name: .shouldCaptureQuestionBankSelection, object: nil)
                } label: { Label("Add selection", systemSymbol: .plus) }
                .help("Add the selected frame or elements to the question bank (Tools › Add Selection to Question Bank)")
                .disabled(fileState.currentActiveFile == nil)
                Menu {
                    Button { isPaperImporterPresented = true } label: { Label("Import past papers (files or folders)…", systemSymbol: .docTextMagnifyingglass) }
                    Button { isImporterPresented = true } label: { Label("Crop from PDF or images…", systemSymbol: .docViewfinder) }
                    Button { isAutoTagPresented = true } label: { Label("Auto-tag with AI…", systemSymbol: .sparkles) }
                } label: {
                    Image(systemSymbol: .ellipsisCircle)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Import questions from a PDF or images, or tag questions with AI")
            }
            HStack(spacing: 8) {
                Menu {
                    Button("All strands") { strandFilter = "" }
                    Divider()
                    ForEach(container.strands) { strand in
                        Button("\(strand.subject.rawValue) · \(strand.level?.rawValue ?? "") · \(strand.name)") { strandFilter = strand.id }
                    }
                } label: {
                    Text(strandFilter.isEmpty ? "All strands" : container.topicName(strandFilter))
                }
                .fixedSize()
                Spacer()
                if let student = currentStudent {
                    Toggle("Hide used by \(student)", isOn: $hideUsedByCurrentStudent).toggleStyle(.checkbox).font(.callout)
                } else {
                    Text("Open a student's file to filter by usage").font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                Text("\(filtered.count) of \(container.questions.count) questions")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                let pending = container.pendingOutcomes(lessonFileID: currentFileID).count
                if currentFileID != nil {
                    Button {
                        isReviewPresented = true
                    } label: {
                        Label(pending == 0 ? "Review lesson" : "Review lesson (\(pending))", systemSymbol: .checklist)
                    }
                    .controlSize(.small)
                    .help("Record how each question shown in this lesson went")
                }
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private var emptyState: some View {
        Center {
            VStack(spacing: 10) {
                Image(systemSymbol: .archivebox).font(.largeTitle).foregroundStyle(.secondary)
                Text("No questions yet").font(.headline)
                Text("Select a frame or elements on the canvas and use Tools › Add Selection to Question Bank, or press Import… to crop questions out of a PDF or image.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(24)
        }
    }

    @ViewBuilder
    private func card(_ question: Question) -> some View {
        let uses = container.outcomes[question.id] ?? []
        let usedByCurrent = currentStudent.map { container.hasBeenShown(question.id, to: $0) } ?? false
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color.white)
                if let png = container.thumbnailPNG(for: question.id), let image = PlatformImage(data: png) {
                    Image(platformImage: image).resizable().scaledToFit().padding(6)
                } else {
                    Text("No preview").foregroundStyle(.secondary)
                }
            }
            .frame(height: 140)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator, lineWidth: 1))

            Text(question.title).font(.headline).lineLimit(2)
            if !question.source.isEmpty { Text(question.source).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            HStack(spacing: 6) {
                if let level = question.level { tagPill(level.rawValue) }
                if let board = question.board { tagPill(board.rawValue) }
                if let tier = question.tier, tier != .notApplicable { tagPill(tier.rawValue) }
                if let marks = question.marks { tagPill("\(marks) marks") }
                if let d = question.difficulty { tagPill(String(repeating: "●", count: d)) }
            }
            let specCodes = container.specPoints(forQuestion: question.id).map(\.code)
            if !question.topicIDs.isEmpty || !question.freeTags.isEmpty || !specCodes.isEmpty {
                FlowTags(tags: specCodes + question.topicIDs.map(container.topicName) + question.freeTags.map { "#\($0)" })
            }
            if let pendingHere = uses.first(where: { $0.result == .unknown && $0.lessonFileID == currentFileID && currentFileID != nil }) {
                HStack(spacing: 8) {
                    Text("How did it go?").font(.caption).foregroundStyle(.secondary)
                    OutcomeQuickButtons(outcome: pendingHere)
                }
            }
            if let last = uses.first {
                Label(
                    "Shown \(uses.count)× · last to \(last.studentName), \(last.shownAt.formatted(date: .abbreviated, time: .omitted))",
                    systemSymbol: usedByCurrent ? .exclamationmarkTriangle : .clock
                )
                .font(.caption).foregroundStyle(usedByCurrent ? .orange : .secondary)
            } else {
                Label("Never used", systemSymbol: .circleDashed).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button { Task { await insert(question) } } label: {
                    if insertingID == question.id { ProgressView().controlSize(.small) } else { Label("Insert", systemSymbol: .plusSquareOnSquare) }
                }
                .disabled(fileState.currentActiveFile == nil || insertingID != nil)
                Spacer()
                Menu {
                    Button("Edit…") { editingQuestion = question }
                    if !uses.isEmpty {
                        Menu("Remove use") {
                            ForEach(uses) { use in
                                Button("\(use.studentName) · \(use.shownAt.formatted(date: .abbreviated, time: .omitted))") {
                                    do { try container.deleteOutcome(id: use.id) } catch { alertToast(error) }
                                }
                            }
                        }
                    }
                    Divider()
                    Button("Delete…", role: .destructive) { deletingQuestion = question }
                } label: { Image(systemSymbol: .ellipsisCircle) }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(usedByCurrent ? Color.orange.opacity(0.6) : .clear, lineWidth: 1))
    }

    @ViewBuilder
    private func tagPill(_ text: String) -> some View {
        Text(text).font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.secondary.opacity(0.15), in: Capsule())
    }

    private var activeCanvasCoordinator: ExcalidrawCanvasView.Coordinator? {
        switch fileState.currentActiveFile {
            case .collaborationFile: fileState.excalidrawCollaborationWebCoordinator
            case .file, .localFile, .temporaryFile, .cloudStorageFile: fileState.excalidrawWebCoordinator
            case nil: nil
        }
    }

    private func insert(_ question: Question) async {
        guard let coordinator = activeCanvasCoordinator else { return }
        insertingID = question.id
        defer { insertingID = nil }
        do {
            try await QuestionBankCanvasBridge.insert(question, from: container, into: coordinator)
            try container.recordUse(of: question.id, studentName: currentStudent ?? "Unknown", lessonFileID: currentFileID)
            alertToast(.init(displayMode: .hud, type: .complete(.green), title: "Inserted “\(question.title)”"))
        } catch {
            alertToast(error)
        }
    }
}
