//
//  TodaysNoteSidebarRow.swift
//  ExcalidrawZ
//
//  Sidebar shortcut to today's Daily Board file: the dated
//  `yyyy-MM-dd EEE.excalidraw` that the daily_board.py build writes into a
//  linked folder. Falls back to the newest dated board when today's is not
//  built yet.
//

import SwiftUI
import CoreData
import ChocofordUI
import SFSafeSymbols

struct TodaysNoteSidebarRow: View {
    @EnvironmentObject private var fileState: FileState
    @EnvironmentObject private var localFolderState: LocalFolderState
    @Environment(\.managedObjectContext) private var viewContext

    @State private var noteURL: URL?
    @State private var folderID: NSManagedObjectID?
    @State private var isToday = true

    private static let nameFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd EEE"
        return f
    }()

    private var isSelected: Bool {
        guard let noteURL, case .localFile(let url) = fileState.currentActiveFile else { return false }
        return url.resolvingSymlinksInPath().path == noteURL.resolvingSymlinksInPath().path
    }

    var body: some View {
        Button {
            open()
        } label: {
            HStack {
                Image(systemSymbol: .sunMax)
                    .frame(width: 30, alignment: .leading)
                Text("Today's Note")
                Spacer()
                if let noteURL, !isToday {
                    Text(noteURL.deletingPathExtension().lastPathComponent.prefix(10))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 4)
                }
            }
        }
        .buttonStyle(.excalidrawSidebarRow(isSelected: isSelected, isMultiSelected: false))
        .disabled(noteURL == nil)
        .help(noteURL == nil ? "No daily board found in a linked folder yet" : (isToday ? "Open today's board" : "Today's board isn't built yet; opens the latest one"))
        .onAppear(perform: locate)
        .onChange(of: fileState.currentActiveFile) { _ in locate() }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in locate() }
        .onReceive(localFolderState.itemCreatedPublisher) { _ in locate() }
        .onReceive(localFolderState.itemRemovedPublisher) { _ in locate() }
        .onReceive(localFolderState.refreshFilesPublisher) { _ in locate() }
    }

    private func open() {
        guard let noteURL else { return }
        fileState.showsStudentsPage = false
        fileState.setActiveFile(.localFile(noteURL))
        if let folderID, let folder = try? viewContext.existingObject(with: folderID) as? LocalFolder {
            withOpenFileDelay {
                fileState.currentActiveGroup = .localFolder(folder)
            }
        }
    }

    /// Today's file in any top-level linked folder, else the newest dated board anywhere.
    private func locate() {
        let request = NSFetchRequest<LocalFolder>(entityName: "LocalFolder")
        request.predicate = NSPredicate(format: "parent == nil")
        let folders = (try? viewContext.fetch(request)) ?? []
        let todayName = Self.nameFormatter.string(from: .now) + ".excalidraw"
        let fm = FileManager.default

        for folder in folders {
            guard let url = folder.url else { continue }
            let candidate = url.appendingPathComponent(todayName)
            if fm.fileExists(atPath: candidate.path) {
                noteURL = candidate; folderID = folder.objectID; isToday = true
                return
            }
        }

        var newest: (URL, NSManagedObjectID)?
        for folder in folders {
            guard let url = folder.url,
                  let names = try? fm.contentsOfDirectory(atPath: url.path) else { continue }
            for name in names where Self.isDatedBoard(name) {
                if newest == nil || name > newest!.0.lastPathComponent {
                    newest = (url.appendingPathComponent(name), folder.objectID)
                }
            }
        }
        noteURL = newest?.0
        folderID = newest?.1
        isToday = false
    }

    private static func isDatedBoard(_ name: String) -> Bool {
        // "2026-10-09 Fri.excalidraw" is 25 characters.
        guard name.hasSuffix(".excalidraw"), name.count == 25 else { return false }
        let scalars = Array(name.utf8)
        return scalars[4] == UInt8(ascii: "-") && scalars[7] == UInt8(ascii: "-") && scalars[10] == UInt8(ascii: " ")
            && name.prefix(4).allSatisfy(\.isNumber)
    }
}
