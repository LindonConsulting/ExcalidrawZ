//
//  QuestionBankInspectorContent.swift
//  ExcalidrawZ
//
//  Trailing-sidebar panel: browse, filter and insert stored questions.
//

import SwiftUI
import ChocofordUI
import UniformTypeIdentifiers

extension Notification.Name {
    static let shouldCaptureQuestionBankSelection = Notification.Name("ShouldCaptureQuestionBankSelection")
}

struct QuestionBankInspectorContent: View {
    @Environment(\.alertToast) private var alertToast
    @EnvironmentObject private var fileState: FileState
    @ObservedObject private var store = QuestionBankStore.shared

    @State private var query = ""
    @State private var hideUsedByCurrentStudent = true
    @State private var topicFilter = ""
    @State private var editingEntry: QuestionBankEntry?
    @State private var deletingEntry: QuestionBankEntry?
    @State private var insertingID: UUID?
    @State private var isImporterPresented = false
    @State private var importDocument: QuestionBankImportDocument?
    @State private var bulkImportURLs: [URL]?

    private var currentStudent: String? {
        if case .file(let file) = fileState.currentActiveFile, let name = file.group?.name, !name.isEmpty {
            return name
        }
        return nil
    }

    private var currentFileID: String? { fileState.currentActiveFile?.id }

    private var filtered: [QuestionBankEntry] {
        store.entries.filter { entry in
            guard entry.matches(query: query) else { return false }
            if !topicFilter.isEmpty, !entry.topics.contains(topicFilter) { return false }
            if hideUsedByCurrentStudent, let student = currentStudent, entry.hasBeenUsed(by: student) { return false }
            return true
        }
    }

    private var allTopics: [String] { Array(Set(store.entries.flatMap(\.topics))).sorted() }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if store.entries.isEmpty {
                emptyState
            } else if filtered.isEmpty {
                Center { Text("No questions match.").foregroundStyle(.secondary) }
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filtered) { entry in
                            card(entry)
                        }
                    }
                    .padding(12)
                }
            }
        }
        .onAppear { store.loadIfNeeded() }
        .fileImporterWithAlert(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.pdf, .png, .jpeg],
            allowsMultipleSelection: true
        ) { urls in
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
        .sheet(item: $importDocument) { document in
            QuestionBankImportSheet(document: document)
        }
        .sheet(isPresented: Binding(get: { bulkImportURLs != nil }, set: { if !$0 { bulkImportURLs = nil } })) {
            QuestionBankBulkImportSheet(urls: bulkImportURLs ?? [])
        }
        .sheet(item: $editingEntry) { entry in
            QuestionBankEntrySheet(entry: entry)
        }
        .confirmationDialog(
            "Delete “\(deletingEntry?.title ?? "")” from the question bank?",
            isPresented: Binding(get: { deletingEntry != nil }, set: { if !$0 { deletingEntry = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let entry = deletingEntry {
                    do { try store.delete(entry.id) } catch { alertToast(error) }
                }
                deletingEntry = nil
            }
        }
    }

    /// One PDF or image → crop sheet; several images → bulk import.
    @MainActor
    private func handleImport(urls: [URL]) async throws {
        guard !urls.isEmpty else { return }
        let isAllImages = urls.allSatisfy { UTType(filenameExtension: $0.pathExtension)?.conforms(to: .image) == true }
        if urls.count > 1, isAllImages {
            bulkImportURLs = urls
        } else {
            importDocument = try QuestionBankImportDocument(url: urls[0])
        }
    }

    @ViewBuilder
    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                TextField("Search title, source, topic, student…", text: $query)
                    .textFieldStyle(.roundedBorder)
                Button {
                    NotificationCenter.default.post(name: .shouldCaptureQuestionBankSelection, object: nil)
                } label: {
                    Label("Add selection", systemSymbol: .plus)
                }
                .help("Add the selected frame or elements to the question bank (Tools › Add Selection to Question Bank)")
                .disabled(fileState.currentActiveFile == nil)
                Button {
                    isImporterPresented = true
                } label: {
                    Label("Import…", systemSymbol: .docViewfinder)
                }
                .help("Crop questions out of a PDF or image, or pick several images to add one question per file")
            }
            HStack(spacing: 8) {
                Menu {
                    Button("All topics") { topicFilter = "" }
                    Divider()
                    ForEach(allTopics, id: \.self) { topic in
                        Button(topic) { topicFilter = topic }
                    }
                } label: {
                    Text(topicFilter.isEmpty ? "All topics" : topicFilter)
                }
                .fixedSize()
                Spacer()
                if let student = currentStudent {
                    Toggle("Hide used by \(student)", isOn: $hideUsedByCurrentStudent)
                        .toggleStyle(.checkbox)
                        .font(.callout)
                } else {
                    Text("Open a student's file to filter by usage")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text("\(filtered.count) of \(store.entries.count) questions")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
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
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
        }
    }

    @ViewBuilder
    private func card(_ entry: QuestionBankEntry) -> some View {
        let usedByCurrent = currentStudent.map { entry.hasBeenUsed(by: $0) } ?? false
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color.white)
                if let png = store.thumbnailPNG(for: entry.id), let image = PlatformImage(data: png) {
                    Image(platformImage: image).resizable().scaledToFit().padding(6)
                } else {
                    Text("No preview").foregroundStyle(.secondary)
                }
            }
            .frame(height: 140)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator, lineWidth: 1))

            Text(entry.title).font(.headline).lineLimit(2)
            if !entry.source.isEmpty {
                Text(entry.source).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            HStack(spacing: 6) {
                if !entry.board.isEmpty { tagPill(entry.board) }
                if !entry.tier.isEmpty { tagPill(entry.tier) }
                if let marks = entry.marks { tagPill("\(marks) marks") }
            }
            if !entry.topics.isEmpty {
                FlowTags(tags: entry.topics)
            }
            if let last = entry.lastUse {
                Label(
                    "Used \(entry.uses.count)× · last with \(last.student), \(last.date.formatted(date: .abbreviated, time: .omitted))",
                    systemSymbol: usedByCurrent ? .exclamationmarkTriangle : .clock
                )
                .font(.caption)
                .foregroundStyle(usedByCurrent ? .orange : .secondary)
            } else {
                Label("Never used", systemSymbol: .circleDashed).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button {
                    Task { await insert(entry) }
                } label: {
                    if insertingID == entry.id {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Insert", systemSymbol: .plusSquareOnSquare)
                    }
                }
                .disabled(fileState.currentActiveFile == nil || insertingID != nil)
                Spacer()
                Menu {
                    Button("Edit…") { editingEntry = entry }
                    if !entry.uses.isEmpty {
                        Menu("Remove use") {
                            ForEach(entry.uses) { use in
                                Button("\(use.student) · \(use.date.formatted(date: .abbreviated, time: .omitted))") {
                                    do { try store.removeUse(use, from: entry.id) } catch { alertToast(error) }
                                }
                            }
                        }
                    }
                    Divider()
                    Button("Delete…", role: .destructive) { deletingEntry = entry }
                } label: {
                    Image(systemSymbol: .ellipsisCircle)
                }
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
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.15), in: Capsule())
    }

    private var activeCanvasCoordinator: ExcalidrawCanvasView.Coordinator? {
        switch fileState.currentActiveFile {
            case .collaborationFile: fileState.excalidrawCollaborationWebCoordinator
            case .file, .localFile, .temporaryFile, .cloudStorageFile: fileState.excalidrawWebCoordinator
            case nil: nil
        }
    }

    private func insert(_ entry: QuestionBankEntry) async {
        guard let coordinator = activeCanvasCoordinator else { return }
        insertingID = entry.id
        defer { insertingID = nil }
        do {
            try await QuestionBankCanvasBridge.insert(entry, from: store, into: coordinator)
            try store.recordUse(of: entry.id, student: currentStudent ?? "Unknown", lessonFileID: currentFileID)
            alertToast(.init(displayMode: .hud, type: .complete(.green), title: "Inserted “\(entry.title)”"))
        } catch {
            alertToast(error)
        }
    }
}
