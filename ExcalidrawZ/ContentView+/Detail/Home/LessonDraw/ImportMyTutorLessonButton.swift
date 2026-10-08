//
//  ImportMyTutorLessonButton.swift
//  ExcalidrawZ
//
//  Home-screen entry point for "Import MyTutor lesson…", shown beside
//  New Lesson Draw. Also listens for the File menu notification in the key
//  window only.
//

import SwiftUI

extension Notification.Name {
    static let shouldHandleImportMyTutorLesson = Notification.Name("ShouldHandleImportMyTutorLesson")
}

struct ImportMyTutorLessonButton: View {
    @State private var isSheetPresented = false

#if canImport(AppKit)
    @State private var window: NSWindow?
#elseif canImport(UIKit)
    @State private var window: UIWindow?
#endif

    var body: some View {
        Button {
            isSheetPresented = true
        } label: {
            Label("Import MyTutor lesson…", systemImage: "square.and.arrow.down.on.square")
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
        }
        .controlSize(.large)
        .help("Convert a Lessonspace Room Export ZIP from MyTutor's classroom into today's lesson file, with editable strokes, shapes, text and images.")
        .bindWindow($window)
        .onReceive(NotificationCenter.default.publisher(for: .shouldHandleImportMyTutorLesson)) { _ in
            guard window?.isKeyWindow == true else { return }
            isSheetPresented = true
        }
        .sheet(isPresented: $isSheetPresented) {
            ImportMyTutorLessonSheet()
        }
    }
}
