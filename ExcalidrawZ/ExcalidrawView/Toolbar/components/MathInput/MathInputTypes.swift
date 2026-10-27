//
//  MathInputTypes.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/06/19.
//

import CoreGraphics
import Foundation

enum MathInputSheetMode {
    case insert
    case edit
}

enum MathInputWorkspace: CaseIterable, Hashable, Identifiable {
    case equation
    case function
    case geometry

    var id: Self { self }

    static var visibleCases: [Self] {
        [.equation, .function]
    }

    var symbol: String {
        switch self {
            case .equation:
                "Σ"
            case .function:
                "ƒ"
            case .geometry:
                "△"
        }
    }

    var title: String {
        switch self {
            case .equation:
                String(localizable: .toolbarLatexMathWorkspaceFormula)
            case .function:
                String(localizable: .toolbarLatexMathWorkspaceFunction)
            case .geometry:
                String(localizable: .toolbarLatexMathWorkspaceGeometry)
        }
    }

    var shortTitle: String {
        switch self {
            case .equation:
                String(localizable: .toolbarLatexMathWorkspaceFormula)
            case .function:
                String(localizable: .toolbarLatexMathWorkspaceFunction)
            case .geometry:
                String(localizable: .toolbarLatexMathWorkspaceGeometry)
        }
    }

    var pickerTitle: String {
        "\(symbol) \(shortTitle)"
    }
}

enum MathFormulaTab: CaseIterable, Hashable, Identifiable {
    case editor
    case library

    var id: Self { self }

    var title: String {
        switch self {
            case .editor:
                String(localizable: .toolbarLatexMathFormulaTabQuickInput)
            case .library:
                String(localizable: .toolbarLatexMathFormulaTabLibrary)
        }
    }
}

enum MathFunctionPanelTab: CaseIterable, Hashable, Identifiable {
    case input
    case preferences

    var id: Self { self }

    var title: String {
        switch self {
            case .input:
                String(localizable: .toolbarLatexMathFunctionPanelInput)
            case .preferences:
                String(localizable: .toolbarLatexMathFunctionPanelPreferences)
        }
    }
}

struct MathSnippet: Identifiable, Hashable {
    let id = UUID()
    var display: String
    var latex: String
}

struct MathFunctionExpression: Identifiable, Hashable {
    let id: UUID
    var expression: String
    var colorHex: String

    init(id: UUID = UUID(), expression: String, colorHex: String) {
        self.id = id
        self.expression = expression
        self.colorHex = colorHex
    }
}

struct MathFunctionPreviewConfiguration: Hashable {
    var expressions: [MathFunctionExpression]
    var xMin: String
    var xMax: String
    var yMin: String
    var yMax: String
    var xLabel: String
    var yLabel: String
    var showGrid: Bool
    var backgroundColor: String?
}

struct MathInputSheetSnapshot: Hashable {
    var inputText: String
    var selectedSVGColor: String
    var usesThemeDefaultSVGColor: Bool
    var activeWorkspace: MathInputWorkspace
    var formulaTab: MathFormulaTab
    var functionPanelTab: MathFunctionPanelTab
    var templateSearchText: String
    var functionExpressions: [MathFunctionExpression]
    var functionXMin: String
    var functionXMax: String
    var functionYMin: String
    var functionYMax: String
    var functionXLabel: String
    var functionYLabel: String
    var functionShowGrid: Bool
    var functionBackgroundColor: String?
    var clipboardText: String
}

struct MathSnippetSection: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var minimumItemWidth: CGFloat = 52
    var snippets: [MathSnippet]
}

struct MathTemplate: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var category: String
    var latex: String
}
