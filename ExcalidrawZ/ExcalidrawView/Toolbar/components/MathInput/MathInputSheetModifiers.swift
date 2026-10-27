//
//  MathInputSheetModifiers.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/06/19.
//

import SwiftUI

struct MathInputSheetViewModifier: ViewModifier {
    @Environment(\.alertToast) private var alertToast
    @EnvironmentObject private var fileState: FileState
    @EnvironmentObject private var canvasPreferencesState: CanvasPreferencesState

    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) {
                MathInputSheetView { renderedSVG in
                    LatexMathSVGRenderer.debugPrintSVGBeforeInsert(renderedSVG.svg, source: "toolbar")
                    Task {
                        do {
                            _ = try await fileState.excalidrawWebCoordinator?.insertMathImage(
                                params: renderedSVG.mathImageParams,
                                options: .init(
                                    position: .auto,
                                    focus: .mode(.center),
                                    captureUpdate: .immediately
                                )
                            )
                        } catch {
                            alertToast(error)
                        }
                    }
                }
                .mathInputNavigationContainer()
                .swiftyAlert(logs: true)
                .task {
                    await syncMathInputCanvasAppearance(
                        from: fileState.excalidrawWebCoordinator,
                        into: canvasPreferencesState
                    )
                }
            }
    }
}

struct MathImageEditSheetViewModifier: ViewModifier {
    @EnvironmentObject private var canvasPreferencesState: CanvasPreferencesState

    @ObservedObject var coordinator: ExcalidrawCore
    var onError: (Error) -> Void

    private var editRequest: Binding<ExcalidrawCore.MathImageEditRequest?> {
        Binding {
            coordinator.mathImageEditRequest
        } set: { newValue in
            if newValue == nil {
                coordinator.clearMathImageEditRequest()
            }
        }
    }

    func body(content: Content) -> some View {
        content
            .sheet(item: editRequest) { request in
                MathInputSheetView(
                    mode: .edit,
                    initialLatex: request.initialLatex,
                    initialSVGColor: request.preferredSVGColor ?? "#1e1e1e"
                ) { renderedSVG in
                    LatexMathSVGRenderer.debugPrintSVGBeforeInsert(renderedSVG.svg, source: "edit_math")
                    Task {
                        do {
                            _ = try await coordinator.updateMathImage(
                                elementId: request.elementId,
                                params: renderedSVG.mathImageParams,
                                options: .init(
                                    focus: .enabled(false),
                                    captureUpdate: .immediately
                                )
                            )
                            coordinator.clearMathImageEditRequest()
                        } catch {
                            onError(error)
                        }
                    }
                }
                .mathInputNavigationContainer()
                .swiftyAlert(logs: true)
                .task {
                    await syncMathInputCanvasAppearance(
                        from: coordinator,
                        into: canvasPreferencesState
                    )
                }
            }
    }
}

private extension View {
    @ViewBuilder
    func mathInputNavigationContainer() -> some View {
#if os(iOS)
        NavigationStack {
            self
        }
#else
        self
#endif
    }
}

@MainActor
private func syncMathInputCanvasAppearance(
    from coordinator: ExcalidrawCore?,
    into canvasPreferencesState: CanvasPreferencesState
) async {
    guard let coordinator else {
        return
    }

    let preferences = try? await coordinator.fetchCanvasPreferences()
    if let preferences {
        canvasPreferencesState.apply(preferences)
    } else if let isDark = try? await coordinator.getIsDark() {
        var snapshot = CanvasPreferencesSnapshot()
        snapshot.theme = isDark ? .dark : .light
        canvasPreferencesState.apply(snapshot)
    }
}
