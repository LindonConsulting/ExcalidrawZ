//
//  ContentView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2022/12/25.
//

import SwiftUI
import CoreData
import CloudKit
import Combine

import ChocofordUI
import ChocofordEssentials
import SwiftyAlert
import SFSafeSymbols

struct ContentView: View {
    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var appPreference: AppPreference
    @EnvironmentObject private var lockedContentState: LockedContentStateStore
    @ObservedObject private var cloudStorageConnections = CloudStorageConnectionStore.shared
#if os(macOS)
    @ObservedObject private var applicationTerminationPresentation = ApplicationTerminationPresentationCoordinator.shared
#endif
    
    @AppStorage("DisableCloudSync") var isICloudDisabled: Bool = false
    
    @State private var hideContent: Bool = false
    
    @StateObject private var fileState = FileState()
    @StateObject private var exportState = ExportState()
    @StateObject private var layoutState = LayoutState()
    @StateObject private var shareFileState = ShareFileState()
    @StateObject private var canvasPreferencesState = CanvasPreferencesState()

#if canImport(AppKit)
    @State private var window: NSWindow?
#elseif canImport(UIKit)
    @State private var window: UIWindow?
#endif
    
    @State private var cloudContainerEventChangeListener: AnyCancellable?
    @State private var cloudContainerImportCleanupTask: Task<Void, Never>?
    
    @State private var isFirstAppear = true

    private static let activeFileCloseInspectorDismissalDelay: UInt64 = 400_000_000
    private static let cloudKitImportSettleDelay: UInt64 = 4_000_000_000
    
    var body: some View {
        content()
            .navigationTitle("")
            .modifier(PrintModifier())
            .modifier(SettingsSheetPresentationModifier())
            .modifier(SearchableModifier())
            .modifier(OpenFromURLModifier())
            .modifier(UserActivityHandlerModifier())
            .modifier(ShareFileModifier())
            .modifier(LocalFolderMonitorModifier())
            .modifier(PDFViewerModifier())
            .modifier(MenuBarImportHandlerModifier())
            .modifier(DragStateModifier())
            .modifier(StartupSyncModifier())
            .modifier(CoreDataMigrationModifier())
            .environmentObject(fileState)
            .environmentObject(exportState)
            .environmentObject(layoutState)
            .environmentObject(shareFileState)
            .environmentObject(canvasPreferencesState)
            .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
            .swiftyAlert(logs: true)
            .bindWindow($window)
#if os(macOS)
            .sheet(isPresented: applicationTerminationSheetBinding) {
                ApplicationTerminationSheet(
                    stage: applicationTerminationPresentation.stage,
                    cancelAction: {
                        applicationTerminationPresentation.cancelTermination()
                    },
                    forceQuitAction: {
                        applicationTerminationPresentation.forceQuit()
                    }
                )
            }
#endif
            .containerSizeClassInjection()
            .onReceive(NotificationCenter.default.publisher(for: .toggleSidebar)) { notification in
                handleToggleSidebar(notification)
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleInspector)) { notification in
                handleToggleInspector(notification)
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: .cloudStorageItemIdentityDidChange
                )
            ) { notification in
                guard let change = notification.object as? CloudStorageItemIdentityChange else {
                    return
                }
                fileState.applyCloudStorageIdentityChange(change)
            }
            .modifier(LockedContentEventModifier(fileState: fileState))
            .modifier(ActiveFileAvailabilityModifier(fileState: fileState))
            .watch(value: fileState.currentActiveFile) { newValue in
                // Going back to Home: nothing to inspect, so collapse the panel.
                if newValue == nil, layoutState.isInspectorPresented {
                    layoutState.isInspectorPresented = false
                }
            }
            .watch(value: colorScheme) { newValue in
                FileCoverCacheCoordinator.shared.scheduleRecentCoverPrewarm(colorScheme: newValue)
            }
            .watch(value: lockedContentState.filePreviewLockStateRevision) { _ in
                FileCoverCacheCoordinator.shared.refreshLibraryCoversForLockStateChange(
                    colorScheme: colorScheme
                )
            }
            .task(id: connectedCloudStorageLocationIDs) {
                await fileState.reconcileCloudStorageLocations(
                    connectedCloudStorageLocationIDs
                )
            }
            .withContainerSize()
            .task {
#if os(macOS)
                await MainActor.run {
                    ApplicationTerminationCanvasFlushCoordinator.shared.register(fileState: fileState)
                }
#endif
                await MainActor.run {
                    fileState.prepareActiveFileCloseTransition = {
                        guard layoutState.isInspectorPresented else { return }
                        layoutState.isInspectorPresented = false
                        try? await Task.sleep(nanoseconds: Self.activeFileCloseInspectorDismissalDelay)
                    }
                    FileCoverCacheCoordinator.shared.register(
                        fileState: fileState,
                        lockedContentState: lockedContentState,
                        context: viewContext
                    )
                    LibraryItemPreviewCoordinator.shared.register(fileState: fileState)
                    FileCoverCacheCoordinator.shared.scheduleRecentCoverPrewarm(colorScheme: colorScheme)
                }
                await prepare()
            }
    }

#if os(macOS)
    private var applicationTerminationSheetBinding: Binding<Bool> {
        Binding(
            get: {
                guard let window else { return false }
                return applicationTerminationPresentation.targetWindowNumber == window.windowNumber
            },
            set: { _ in }
        )
    }
#endif

    private var connectedCloudStorageLocationIDs: Set<UUID> {
        Set(cloudStorageConnections.locations.map(\.id))
    }
    
    @ViewBuilder
    private func content() -> some View {
        ZStack {
            if horizontalSizeClass == .regular {
                contentView()
                    .modifier(InspectorPresentationModifier())
            } else {
                // Compact uses TabView, can not use library here.
                contentView()
            }
        }
    }
    
    @ViewBuilder
    private func contentView() -> some View {
        if #available(macOS 13.0, *),
            appPreference.sidebarLayout == .sidebar {
            ContentViewModern()
        } else {
            ContentViewLagacy()
        }
    }
    
    private func handleToggleSidebar(_ notification: Notification) {
        guard window?.isKeyWindow == true else { return }
        layoutState.isSidebarPresented.toggle()
    }
    private func handleToggleInspector(_ notification: Notification) {
        guard window?.isKeyWindow == true else { return }
        layoutState.toggleInspector()
    }

    // Check if it is first launch by checking the files count.
    private func prepare() async {
        self.cloudContainerEventChangeListener?.cancel()
        self.cloudContainerEventChangeListener = NotificationCenter.default.publisher(
            for: NSPersistentCloudKitContainer.eventChangedNotification
        ).sink { notification in
            guard let event = notification.userInfo?["event"] as? NSPersistentCloudKitContainer.Event,
                  event.type == .import,
                  event.succeeded else {
                return
            }

            Task { @MainActor in
                cloudContainerImportCleanupTask?.cancel()
                cloudContainerImportCleanupTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: Self.cloudKitImportSettleDelay)
                    guard !Task.isCancelled else { return }
                    try? await fileState.mergeDefaultGroupAndTrashIfNeeded(context: viewContext)
                }
            }
        }

        try? await fileState.mergeDefaultGroupAndTrashIfNeeded(context: viewContext)
    }
}

#if os(macOS)
private struct ApplicationTerminationSheet: View {
    let stage: ApplicationTerminationStage
    let cancelAction: () -> Void
    let forceQuitAction: () -> Void

    @State private var forceQuitDelayRemaining = 3

    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .controlSize(.small)

            VStack(spacing: 6) {
                Text(.localizable(.applicationTerminationTitle))
                    .font(.headline)

                stageDescription
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack {
                Spacer()

                Button(.localizable(.generalButtonCancel), action: cancelAction)
                    .keyboardShortcut(.cancelAction)
                    .modernButtonStyle(
                        style: .glass,
                        size: .regular,
                        shape: .capsule
                    )

                Button(
                    .localizable(.applicationTerminationForceQuitButton),
                    role: .destructive,
                    action: forceQuitAction
                )
                .disabled(forceQuitDelayRemaining > 0)
                .modernButtonStyle(
                    style: .glassProminent,
                    size: .regular,
                    shape: .capsule
                )
                .tint(.red)
            }
        }
        .padding(24)
        .frame(width: 360)
        .interactiveDismissDisabled()
        .task {
            forceQuitDelayRemaining = 3
            while forceQuitDelayRemaining > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                forceQuitDelayRemaining -= 1
            }
        }
    }

    @ViewBuilder
    private var stageDescription: some View {
        switch stage {
            case .backgroundDocumentOperations:
                Text(.localizable(.applicationTerminationStageBackgroundDocumentOperations))
            case .currentDrawing:
                Text(.localizable(.applicationTerminationStageCurrentDrawing))
            case .applicationData:
                Text(.localizable(.applicationTerminationStageApplicationData))
            case .backup:
                Text(.localizable(.applicationTerminationStageBackup))
        }
    }
}
#endif
