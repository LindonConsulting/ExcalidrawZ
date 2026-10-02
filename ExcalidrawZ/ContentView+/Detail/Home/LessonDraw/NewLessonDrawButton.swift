//
//  NewLessonDrawButton.swift
//  ExcalidrawZ
//
//  Home-screen entry point for "New Lesson Draw". Also listens for the
//  File menu notification, in the key window only (same pattern as
//  NewFileButton).
//

import SwiftUI

extension Notification.Name {
    static let shouldHandleNewLessonDraw = Notification.Name("ShouldHandleNewLessonDraw")
}

struct NewLessonDrawButton: View {
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
            Label("New Lesson Draw", systemImage: "calendar.badge.plus")
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
        }
        .controlSize(.large)
        .keyboardShortcut("N", modifiers: [.command, .shift])
        .help("Create today's lesson file for the student in your calendar right now, with a recap of the previous lesson.")
        .bindWindow($window)
        .onReceive(NotificationCenter.default.publisher(for: .shouldHandleNewLessonDraw)) { _ in
            guard window?.isKeyWindow == true else { return }
            isSheetPresented = true
        }
        .sheet(isPresented: $isSheetPresented) {
            NewLessonDrawSheet()
        }
    }
}
