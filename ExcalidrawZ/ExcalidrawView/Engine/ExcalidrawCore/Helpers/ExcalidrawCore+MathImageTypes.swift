//
//  ExcalidrawCore+MathImageTypes.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/06/18.
//

import Foundation

extension ExcalidrawCore {
    struct MathImageParams: Codable, Hashable {
        var svg: String?
        var svgBase64: String?
        var dataURL: String?
        var latex: String?
        var renderer: String?
        var width: Double?
        var height: Double?
        /// Inline LaTeX only: the text the image replaces, echoed back so the
        /// web side can drop a stale render if the text changed meanwhile.
        var originalText: String?
    }

    struct MathImageOptions: Codable, Hashable {
        var position: MermaidPosition?
        var focus: MermaidFocus?
        var captureUpdate: CaptureUpdate?
    }

    struct MathImageResult: Codable, Hashable {
        var elementId: String?
        var fileId: String?
        var elementCount: Int?
        var durationMs: Double?
        var bounds: MermaidBounds?
        var width: Double?
        var height: Double?
        var usedLegacyFallback: Bool?
    }

    /// Sent by the web bundle when a text element whose whole text is a LaTeX
    /// expression finishes editing (see `inlineMath.js`).
    struct InlineMathRenderRequest: Codable, Hashable {
        var textElementId: String
        var latex: String
        var originalText: String?
        var fontSize: Double?
        var strokeColor: String?
    }

    struct MathImageEditRequest: Codable, Hashable, Identifiable {
        var id: String { elementId }

        var elementId: String
        var fileId: String?
        var latex: String?
        var renderer: String?
        var version: JSONValue?
        var mathData: JSONValue?
        var customData: JSONValue?
        var bounds: JSONValue?
        var angle: JSONValue?
        var fileData: JSONValue?

        var initialLatex: String {
            latex?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? mathData?.firstString(forKeys: Self.latexKeys)
                ?? customData?.firstString(forKeys: Self.latexKeys)
                ?? fileData?.firstString(forKeys: Self.latexKeys)
                ?? ""
        }

        var preferredSVGColor: String? {
            mathData?.firstString(forKeys: Self.colorKeys)?.hexColorString
                ?? customData?.firstString(forKeys: Self.colorKeys)?.hexColorString
                ?? fileData?.firstString(forKeys: Self.colorKeys)?.hexColorString
        }

        private static let latexKeys = ["latex", "tex", "expression"]
        private static let colorKeys = ["color", "foregroundColor", "strokeColor", "fill", "stroke"]
    }
}

private extension ExcalidrawCore.JSONValue {
    func firstString(forKeys targetKeys: [String]) -> String? {
        firstString(forKeys: targetKeys, acceptsStringValue: false)
    }

    private func firstString(
        forKeys targetKeys: [String],
        acceptsStringValue: Bool
    ) -> String? {
        switch self {
            case .string(let value):
                guard acceptsStringValue else { return nil }
                return value.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            case .number, .bool, .null:
                return nil
            case .array(let values):
                for value in values {
                    if let string = value.firstString(
                        forKeys: targetKeys,
                        acceptsStringValue: acceptsStringValue
                    ) {
                        return string
                    }
                }
                return nil
            case .object(let object):
                for key in targetKeys {
                    if let value = object.first(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame })?.value,
                       let string = value.firstString(forKeys: targetKeys, acceptsStringValue: true) {
                        return string
                    }
                }
                for value in object.values {
                    if let string = value.firstString(forKeys: targetKeys, acceptsStringValue: false) {
                        return string
                    }
                }
                return nil
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    var hexColorString: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.hasPrefix("#") else { return nil }
        let hex = String(value.dropFirst())
        guard [3, 6, 8].contains(hex.count),
              hex.allSatisfy(\.isHexDigit) else {
            return nil
        }
        return value
    }
}
