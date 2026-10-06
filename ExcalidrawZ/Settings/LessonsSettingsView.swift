//
//  LessonsSettingsView.swift
//  ExcalidrawZ
//
//  Settings for "New Lesson Draw": calendar title rule and recap backends.
//

import SwiftUI
import TutorAI
import TutorStore
import UniformTypeIdentifiers
import ChocofordUI

struct LessonsSettingsView: View {
    @ObservedObject private var preferences = LessonDrawPreferences.shared
    @Environment(\.alertToast) private var alertToast


    @State private var apiKeyDraft = ""
    @State private var hasStoredKey = false
    @State private var patternSample = "Frankie (CMT) - Maths GCSE"
    @State private var appleAvailability = "Checking…"
    @ObservedObject private var tutorKit = TutorKitContainer.shared
    @State private var isBackupDestinationPresented = false
    @State private var isRestoreSourcePresented = false
    @State private var isRestoreConfirmPresented = false
    @State private var pendingRestoreURL: URL?
    @State private var backupMessage: String?
    @State private var isTestingKey = false
    @State private var keyTestResult: String?

    var body: some View {
        SettingsFormContainer(legacyAlignment: .leading, legacySpacing: 18) {
            content()
        }
        .fileImporterWithAlert(isPresented: $isBackupDestinationPresented, allowedContentTypes: [.folder], allowsMultipleSelection: false) { urls in
            guard let url = urls.first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let created = try await MainActor.run { try tutorKit.exportBackup(to: url) }
            await MainActor.run { backupMessage = "Backed up to \(created.path)" }
        }
        .fileImporterWithAlert(isPresented: $isRestoreSourcePresented, allowedContentTypes: [.folder], allowsMultipleSelection: false) { urls in
            guard let url = urls.first else { return }
            await MainActor.run { pendingRestoreURL = url; isRestoreConfirmPresented = true }
        }
        .confirmationDialog(
            "Replace all tutor data with the backup\(pendingRestoreURL.flatMap { TutorBackupManager.manifest(of: $0) }.map { " from \($0.createdAt.formatted(date: .abbreviated, time: .shortened)) (\($0.questionCount) questions, \($0.studentCount) students)" } ?? "")?",
            isPresented: $isRestoreConfirmPresented, titleVisibility: .visible
        ) {
            Button("Restore", role: .destructive) {
                guard let url = pendingRestoreURL else { return }
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                do {
                    try tutorKit.restoreBackup(from: url)
                    backupMessage = "Restored from \(url.lastPathComponent). A safety copy of the previous data was added to the automatic backups."
                } catch {
                    alertToast(error)
                }
            }
        }
        .onAppear {
            tutorKit.openIfNeeded()
            hasStoredKey = AnthropicAPIKeyStore.hasKey()
            appleAvailability = Self.appleAvailabilityDescription()
        }
    }

    @ViewBuilder
    private func content() -> some View {
        Section {
            TextField("Title pattern (regex)", text: $preferences.titlePattern)
                .font(.body.monospaced())
            Stepper("Count an event as “now” \(preferences.lookbackMinutes) min before it starts", value: $preferences.lookbackMinutes, in: 0...120, step: 5)
            TextField("Try a title", text: $patternSample)
            LabeledContent("Result", value: sampleResult)
            Button("Reset to default") { preferences.resetTitlePattern() }
        } header: {
            Text("Calendar")
        } footer: {
            Text("Capture group 1 is the student (a trailing parenthetical such as an agency tag is dropped), group 2 is the subject. The group in ExcalidrawZ is named after the student; the file is named “YYYY-MM-DD Student – Subject”.")
                .foregroundStyle(.secondary)
        }

        Section {
            Picker("Recap backend", selection: $preferences.backend) {
                ForEach(LessonRecapBackendPreference.allCases) { backend in
                    Text(backend.title).tag(backend)
                }
            }
            LabeledContent("Apple Intelligence", value: appleAvailability)
        } header: {
            Text("Recap")
        } footer: {
            Text("Automatic prefers the on-device Apple model when available, then the Anthropic API. The file is still created when no backend is available.")
                .foregroundStyle(.secondary)
        }

        Section {
            Toggle("Automatic daily backup (keeps the last 7)", isOn: Binding(
                get: { tutorKit.automaticBackupsEnabled },
                set: { tutorKit.automaticBackupsEnabled = $0 }
            ))
            LabeledContent("Last automatic backup", value: tutorKit.automaticBackups.first.map { $0.manifest.createdAt.formatted(date: .abbreviated, time: .shortened) } ?? "None yet")
            HStack {
                Button("Back up to folder…") { isBackupDestinationPresented = true }
                Button("Restore from backup…") { isRestoreSourcePresented = true }
#if os(macOS)
                if let dir = tutorKit.backupsDirectory {
                    Button("Show backups in Finder") { NSWorkspace.shared.activateFileViewerSelecting([dir]) }
                }
#endif
            }
            if let backupMessage {
                Text(backupMessage).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("Tutor data (students, questions, specifications, results)")
        } footer: {
            Text("A backup is a folder named TutorKit-Backup-<date> holding the database and question images. To move to another Mac, back up to a shared folder or drive there, then Restore on the other machine. Restoring replaces the current data (a safety copy is kept in the automatic backups).")
                .foregroundStyle(.secondary)
        }

        Section {
            TextField("Model", text: $preferences.anthropicModelID)
                .font(.body.monospaced())
            SecureField(hasStoredKey ? "API key saved – enter a new one to replace it" : "sk-ant-…", text: $apiKeyDraft)
                .onSubmit(saveKey)
            HStack {
                Button("Save key", action: saveKey)
                    .disabled(apiKeyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                if hasStoredKey {
                    Button("Remove key", role: .destructive, action: removeKey)
                    Button(isTestingKey ? "Testing…" : "Test key") { Task { await testKey() } }
                        .disabled(isTestingKey)
                }
                Spacer()
                Text(hasStoredKey ? "Key stored in Keychain" : "No key stored")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            if let keyTestResult {
                Text(keyTestResult)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("Anthropic API")
        } footer: {
            Text("The key is stored only in this Mac's Keychain and sent only to api.anthropic.com. Usage is billed to your own Anthropic account.")
                .foregroundStyle(.secondary)
        }
    }

    private var sampleResult: String {
        do {
            guard let match = try LessonTitleParser(pattern: preferences.titlePattern).parse(patternSample) else {
                return "No match"
            }
            return "Student “\(match.student)”" + (match.subject.map { ", subject “\($0)”" } ?? "")
        } catch {
            return error.localizedDescription
        }
    }

    private func saveKey() {
        do {
            try AnthropicAPIKeyStore.save(apiKeyDraft)
            apiKeyDraft = ""
            hasStoredKey = AnthropicAPIKeyStore.hasKey()
        } catch {
            alertToast(error)
        }
    }

    private func testKey() async {
        isTestingKey = true
        defer { isTestingKey = false }
        do {
            guard let client = try AnthropicAPIKeyStore.makeClient(preferences: preferences) else {
                keyTestResult = "No key stored."
                return
            }
            let summarizer = AnthropicRecapSummarizer(client: client)
            let input = LessonRecapInput(
                student: "Test",
                subject: "Maths",
                previousLessonDate: .now,
                texts: ["Expanding brackets", "(x+2)(x+3) = x² + 5x + 6", "Homework: Q1–5"],
                elementCounts: ["text": 3, "rectangle": 1]
            )
            let started = Date()
            let reply = try await summarizer.summarize(input)
            let seconds = String(format: "%.1f", Date().timeIntervalSince(started))
            keyTestResult = "OK (\(preferences.anthropicModelID), \(seconds)s):\n\(reply)"
        } catch {
            keyTestResult = "Failed: \(error.localizedDescription)"
        }
    }

    private func removeKey() {
        do {
            try AnthropicAPIKeyStore.remove()
            hasStoredKey = false
            keyTestResult = nil
        } catch {
            alertToast(error)
        }
    }

    private static func appleAvailabilityDescription() -> String {
        LessonRecapSummarizer.appleAvailabilityDescription
    }
}
