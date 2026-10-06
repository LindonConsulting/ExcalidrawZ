//
//  SpecificationsSheet.swift
//  ExcalidrawZ
//
//  Imported exam specifications: list, import from PDF (AI extraction with
//  review), delete.
//

import SwiftUI
import ChocofordUI
import UniformTypeIdentifiers
import TutorModels
import TutorStore
import TutorAI

struct SpecificationsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.alertToast) private var alertToast
    @ObservedObject private var container = TutorKitContainer.shared

    @State private var isImporterPresented = false
    @State private var importTask: Task<Void, Never>?
    @State private var progressText: String?
    @State private var draft: SpecificationDraft?
    @State private var draftFileName = ""
    @State private var deleting: Specification?
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Specifications").font(.title2.bold())
                Spacer()
                Button { isImporterPresented = true } label: { Label("Import PDF…", systemSymbol: .docBadgePlus) }
                    .disabled(progressText != nil || !AnthropicAPIKeyStore.hasKey())
            }
            if !AnthropicAPIKeyStore.hasKey() {
                Text("Importing needs the Anthropic API key (Settings → Lessons).").font(.callout).foregroundStyle(.secondary)
            }

            if let draft {
                reviewView(draft)
            } else {
                listView
            }

            if let progressText {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(progressText).font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel import") { importTask?.cancel(); importTask = nil; self.progressText = nil }
                }
            }
            if let errorText {
                Text(errorText).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                if draft != nil {
                    Button("Discard") { draft = nil }
                    Button("Save specification") { saveDraft() }.keyboardShortcut(.defaultAction)
                } else {
                    Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 680, minHeight: 520)
        .onAppear { container.openIfNeeded() }
        .fileImporterWithAlert(isPresented: $isImporterPresented, allowedContentTypes: [.pdf], allowsMultipleSelection: false) { urls in
            guard let url = urls.first else { return }
            await MainActor.run { startImport(url: url) }
        }
        .confirmationDialog("Delete \(deleting?.displayName ?? "")? Questions keep their other tags; students lose their checklist.", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let spec = deleting { do { try container.deleteSpecification(id: spec.id) } catch { alertToast(error) } }
                deleting = nil
            }
        }
    }

    @ViewBuilder
    private var listView: some View {
        if container.specifications.isEmpty {
            Center {
                VStack(spacing: 8) {
                    Image(systemSymbol: .listBulletRectangle).font(.largeTitle).foregroundStyle(.secondary)
                    Text("No specifications yet").font(.headline)
                    Text("Import the board's specification PDF (e.g. Edexcel GCSE Maths 1MA1). The spec points become tags for questions and a coverage checklist per student.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 440)
                }
            }
        } else {
            List(container.specifications) { spec in
                let tree = container.specificationTree(id: spec.id)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(spec.title).font(.headline)
                        Text("\(spec.displayName) · \(tree?.sections.count ?? 0) sections · \(tree?.points.count ?? 0) points · imported \(spec.importedAt.formatted(date: .abbreviated, time: .omitted)) from \(spec.sourceFileName)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(container.students.filter { $0.specificationID == spec.id }.count) students").font(.caption).foregroundStyle(.secondary)
                    Button(role: .destructive) { deleting = spec } label: { Image(systemSymbol: .trash) }.buttonStyle(.borderless)
                }
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private func reviewView(_ draft: SpecificationDraft) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Review: \(draft.title.isEmpty ? draftFileName : draft.title)").font(.headline)
            Text("\(draft.board) · \(draft.level) · \(draft.subject) · code \(draft.code.isEmpty ? "?" : draft.code) · \(draft.sections.count) sections · \(draft.pointCount) points")
                .font(.callout).foregroundStyle(.secondary)
            List {
                ForEach(Array(draft.sections.enumerated()), id: \.offset) { _, section in
                    Section(section.code.isEmpty ? section.title : "\(section.code) · \(section.title)") {
                        ForEach(Array(section.points.enumerated()), id: \.offset) { _, point in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(point.code).font(.caption.monospaced()).foregroundStyle(.secondary).frame(width: 56, alignment: .leading)
                                Text(point.text).font(.callout)
                                if let tier = point.tier, !tier.isEmpty { Spacer(); Text(tier).font(.caption2).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
            }
        }
    }

    private func startImport(url: URL) {
        errorText = nil
        draftFileName = url.lastPathComponent
        progressText = "Reading PDF…"
        importTask = Task {
            do {
                let pages = try SpecificationPDFText.pages(from: url)
                guard let client = try AnthropicAPIKeyStore.makeClient() else { throw TutorAIError.noAPIKey }
                let importer = SpecificationImporter(client: client)
                let result = try await importer.importSpecification(pages: pages) { done, total in
                    Task { @MainActor in progressText = "Extracting spec points… chunk \(min(done + 1, total)) of \(total)" }
                }
                guard !Task.isCancelled else { return }
                if result.pointCount == 0 { throw TutorAIError.unparseable("No spec points were found in this PDF.") }
                draft = result
            } catch is CancellationError {
            } catch {
                errorText = error.localizedDescription
            }
            progressText = nil
            importTask = nil
        }
    }

    private func saveDraft() {
        guard let draft else { return }
        do {
            try container.saveSpecification(from: draft, sourceFileName: draftFileName)
            self.draft = nil
            alertToast(.init(displayMode: .hud, type: .complete(.green), title: "Specification saved"))
        } catch {
            alertToast(error)
        }
    }
}
