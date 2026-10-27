//
//  ExcalidrawZApp.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2022/12/25.
//

import Foundation
import SwiftUI
import Logging
#if os(macOS)
import ServiceManagement
#endif

import SwiftyAlert
import ChocofordUI

extension Notification.Name {
    static let shouldHandleImport = Notification.Name("ShouldHandleImport")
    static let didImportToExcalidrawZ = Notification.Name("DidImportToExcalidrawZ")
    static let togglePrintModalSheet = Notification.Name("TogglePrintModalSheet")
    static let toggleSidebar = Notification.Name("ToggleSidebar")
    static let toggleInspector = Notification.Name("ToggleInspector")
    static let toggleShare = Notification.Name("ToggleShare")
    static let lockedContentDidReset = Notification.Name("LockedContentDidReset")
    static let lockedContentDidDeleteFile = Notification.Name("LockedContentDidDeleteFile")
}

@main
@MainActor
struct ExcalidrawZApp: App {
    @Environment(\.managedObjectContext) private var viewContext
#if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
#elseif os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
#endif
        
#if os(macOS)
    @Environment(\.openWindow) private var openWindow
#endif
    init() {
        // Configure logging level
        LoggingSystem.bootstrap { label in
            var stdoutHandler = StreamLogHandler.standardOutput(label: label)
#if DEBUG
            stdoutHandler.logLevel = .debug
#else
            stdoutHandler.logLevel = .info
#endif
            return stdoutHandler
        }
        FeatureDiscoveryTips.configureIfAvailable()
        // Cloud storage synchronization follows the process lifecycle, not a
        // WindowGroup lifecycle. This also keeps queued offline work moving
        // while the app has no open windows on macOS.
        CloudStorageSyncService.shared.start()

        // Setting Folder Structure Type
        if #available(macOS 13.0, *) {} else {
            UserDefaults.standard.set(1, forKey: "FolderStructureStyle")
        }
        
        // refresh spotlight index if expired, or after changing the indexer implementation
        var shouldRefreshSpotlightIndex = false
        let storedSpotlightIndexImplementationVersion = UserDefaults.standard.integer(
            forKey: SpotlightIndexingService.implementationVersionDefaultsKey
        )
        if storedSpotlightIndexImplementationVersion < SpotlightIndexingService.implementationVersion {
            shouldRefreshSpotlightIndex = true
        }
        let dateString = UserDefaults.standard.string(
            forKey: SpotlightIndexingService.lastRefreshDefaultsKey
        )
        if let dateString,
           let date = try? Date(dateString, strategy: .iso8601),
           date < Date.now - SpotlightIndexingService.periodicRebuildInterval {
            shouldRefreshSpotlightIndex = true
        } else if dateString == nil {
            shouldRefreshSpotlightIndex = true
        }
        if shouldRefreshSpotlightIndex {
            let startupLogger = Logging.Logger(label: "ExcalidrawApp")
            Task {
                do {
                    try await PersistenceController.shared.refreshIndices()
                } catch {
                    startupLogger.error("Failed to refresh Spotlight index: \(error)")
                }
            }
        }
    }

    @StateObject private var appPrefernece = AppPreference()
    @StateObject private var lockedContentState = LockedContentStateStore()

    @State private var isArchiveFilesExporterPresented = false


    let server = ExcalidrawServer()
    let logger = Logging.Logger(label: "ExcalidrawApp")
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(appPrefernece.appearance.colorScheme)
                .archiveFilesExporter(
                    isPresented: $isArchiveFilesExporterPresented,
                    context: PersistenceController.shared.container.viewContext,
                ) { _ in }
                .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
                .environmentObject(appPrefernece)
                .environmentObject(lockedContentState)
                .lockedContentAutoRelock(lockedContentState: lockedContentState)
        }
        // prevent window being open by urls.
        .handlesExternalEvents(matching: ["*"])
#if os(macOS)
        .defaultSizeIfAvailable(CGSize(width: 1200, height: 700))
        .commands {
            CommandGroup(replacing: .newItem) {
                Button {
                    NotificationCenter.default.post(
                        name: .shouldHandleNewDraw,
                        object: nil
                    )
                } label: {
                    Text(.localizable(.generalButtonCreateNewFile))
                }
                .keyboardShortcut("N", modifiers: .command)

                Button {
                    NotificationCenter.default.post(
                        name: .shouldHandleNewLessonDraw,
                        object: nil
                    )
                } label: {
                    Text("New Lesson Draw")
                }
                .keyboardShortcut("N", modifiers: [.command, .shift])

                Button {
                    NotificationCenter.default.post(
                        name: .shouldHandleImportMyTutorLesson,
                        object: nil
                    )
                } label: {
                    Text("Import MyTutor Lesson…")
                }
                
                Button {
                    NotificationCenter.default.post(
                        name: .shouldHandleNewDrawFromClipboard,
                        object: nil
                    )
                } label: {
                    Text(.localizable(.whatsNewNewDrawFromClipboardTitle))
                }
                .keyboardShortcut("N", modifiers: [.command, .option, .shift])
                
//                Divider()
                
//                Button("New Window") {
//                    // openWindow(id: "Some ID")
//                }
//                .keyboardShortcut("N", modifiers: [.command, .shift])
            }
            
            CommandGroup(after: .printItem) {
                Button {
                    NotificationCenter.default.post(name: .togglePrintModalSheet, object: nil)
                } label: {
                    Text(.localizable(.menubarButtonPrint))
                }
                .keyboardShortcut("p", modifiers: .command)
            }
            
            CommandGroup(after: .importExport) {
                Button {
                    let panel = ExcalidrawOpenPanel.importPanel
                    if panel.runModal() == .OK {
                        NotificationCenter.default.post(name: .shouldHandleImport, object: panel.urls)
                    }
                } label: {
                    Label(.localizable(.menubarButtonImport), systemSymbol: .squareAndArrowDown)
                }
                Button {
                    // MUST USE THIS INSTEAD OF VIEWCONTEXT
//                    Task {
//                        try? await archiveAllFiles(context: PersistenceController.shared.container.viewContext)
//                    }
                    isArchiveFilesExporterPresented.toggle()
                } label: {
                    Label(.localizable(.menubarButtonExportAll), systemSymbol: .squareAndArrowUp)
                }
                
                
            }
            
            // MARK: View
            CommandGroup(before: .sidebar) {
                Button {
                    NotificationCenter.default.post(name: .toggleSidebar, object: nil)
                } label: {
                    Text(.localizable(.menubarToggleSidebar))
                }
                .keyboardShortcut("0", modifiers: [.command])
                
                Button {
                    NotificationCenter.default.post(name: .toggleInspector, object: nil)
                } label: {
                    Text(.localizable(.menubarToggleLibrary))
                }
                .keyboardShortcut("0", modifiers: [.command, .option])
                
                Button {
                    NotificationCenter.default.post(name: .toggleShare, object: nil)
                } label: {
                    Text(.localizable(.menubarToggleShare))
                }
                .keyboardShortcut("S", modifiers: [.command, .shift])

                Button {
                    openWindow(id: ViewerMirrorController.windowID)
                } label: {
                    Text(.localizable(.menubarOpenViewerWindow))
                }
                .keyboardShortcut("V", modifiers: [.command, .shift])

                ViewerFollowEditorCommand()

                Button {
                    openWindow(id: ViewerMirrorController.shareWindowID)
                } label: {
                    Text(.localizable(.menubarViewerShareLink))
                }
            }

        }
#endif
        
#if os(macOS)
        // documentGroup()

        // Read-only mirror of the editor canvas for a second display.
        Window(Text(.localizable(.viewerWindowTitle)), id: ViewerMirrorController.windowID) {
            ViewerWindowView()
                .preferredColorScheme(appPrefernece.appearance.colorScheme)
        }
        .defaultSize(width: 960, height: 600)

        // Share the Viewer with browsers on the local network.
        Window(Text(.localizable(.viewerShareWindowTitle)), id: ViewerMirrorController.shareWindowID) {
            ViewerShareWindowView()
                .preferredColorScheme(appPrefernece.appearance.colorScheme)
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
                .swiftyAlert(logs: true)
                .containerSizeClassInjection()
                .preferredColorScheme(appPrefernece.appearance.colorScheme)
                .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
                .environmentObject(appPrefernece)
                .environmentObject(lockedContentState)
        }
#endif
    }

}

fileprivate extension Scene {
    func defaultSizeIfAvailable(_ size: CGSize) -> some Scene {
        if #available(macOS 13.0, iOS 17.0, *) {
            return self.defaultSize(size)
        }
        else {
            return self
        }
    }
}
