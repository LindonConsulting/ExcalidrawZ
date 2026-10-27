//
//  LibraryItemCanvasElementPreprocessor.swift
//  ExcalidrawZ
//
//  Prepares library item elements for insertion on the canvas.
//

import Foundation

enum LibraryItemCanvasElementPreprocessor {
    enum Placement {
        case original
        case topLeft(x: Double?, y: Double?)
        case center(x: Double, y: Double)
    }

    enum PreparationError: LocalizedError {
        case emptyElements
        case invalidElementsJSON

        var errorDescription: String? {
            switch self {
                case .emptyElements:
                    return "Library item has no elements."
                case .invalidElementsJSON:
                    return "Library item elements data is not a JSON array."
            }
        }
    }

    static func prepare(
        elements: [ExcalidrawElement],
        placement: Placement
    ) throws -> [ExcalidrawElement] {
        guard !elements.isEmpty else {
            throw PreparationError.emptyElements
        }
        let data = try JSONEncoder().encode(elements)
        return try prepare(blob: data, placement: placement)
    }

    static func prepare(
        blob: Data,
        placement: Placement
    ) throws -> [ExcalidrawElement] {
        let transformedData = try transformElements(blob: blob, placement: placement)
        return try JSONDecoder().decode([ExcalidrawElement].self, from: transformedData)
    }

    /// Apply (translate + id-regen) to the raw elements JSON. We work
    /// at the JSON-dict level rather than going through `ExcalidrawElement`
    /// because the enum's value-type variants make in-place mutation
    /// awkward (you'd reconstruct each shape variant by hand).
    private static func transformElements(
        blob: Data,
        placement: Placement
    ) throws -> Data {
        guard var elements = try JSONSerialization.jsonObject(with: blob) as? [[String: Any]] else {
            throw PreparationError.invalidElementsJSON
        }
        guard !elements.isEmpty else {
            throw PreparationError.emptyElements
        }

        let offset = computeOffset(elements: elements, placement: placement)
        let idMapping = makeElementIDMapping(elements)
        let groupIDMapping = makeGroupIDMapping(elements)

        for index in elements.indices {
            elements[index] = remapIDs(
                in: elements[index],
                idMapping: idMapping,
                groupIDMapping: groupIDMapping
            )
            if let dx = offset?.dx, let x = number(elements[index]["x"]) {
                elements[index]["x"] = x + dx
            }
            if let dy = offset?.dy, let y = number(elements[index]["y"]) {
                elements[index]["y"] = y + dy
            }
        }

        return try JSONSerialization.data(withJSONObject: elements)
    }

    private static func computeOffset(
        elements: [[String: Any]],
        placement: Placement
    ) -> (dx: Double, dy: Double)? {
        switch placement {
            case .original:
                return nil
            case .topLeft(let x, let y):
                guard x != nil || y != nil else { return nil }
                guard let bounds = bounds(of: elements) else {
                    return (x ?? 0, y ?? 0)
                }
                return (
                    dx: (x ?? bounds.minX) - bounds.minX,
                    dy: (y ?? bounds.minY) - bounds.minY
                )
            case .center(let x, let y):
                guard let bounds = bounds(of: elements) else {
                    return (x, y)
                }
                return (
                    dx: x - bounds.midX,
                    dy: y - bounds.midY
                )
        }
    }

    private static func makeElementIDMapping(_ elements: [[String: Any]]) -> [String: String] {
        var mapping: [String: String] = [:]
        for element in elements {
            if let id = element["id"] as? String {
                mapping[id] = mapping[id] ?? ExcalidrawNanoID.make()
            }
        }
        return mapping
    }

    private static func makeGroupIDMapping(_ elements: [[String: Any]]) -> [String: String] {
        var mapping: [String: String] = [:]
        for element in elements {
            guard let groupIDs = element["groupIds"] as? [String] else { continue }
            for groupID in groupIDs {
                mapping[groupID] = mapping[groupID] ?? ExcalidrawNanoID.make()
            }
        }
        return mapping
    }

    /// Walk a single element's JSON dict and substitute ids using the
    /// supplied mappings. Foreign refs (ids not in our mapping) are left
    /// untouched.
    private static func remapIDs(
        in element: [String: Any],
        idMapping: [String: String],
        groupIDMapping: [String: String]
    ) -> [String: Any] {
        var output = element

        if let id = output["id"] as? String,
           let newID = idMapping[id] {
            output["id"] = newID
        }

        for key in ["containerId", "frameId"] {
            if let id = output[key] as? String,
               let newID = idMapping[id] {
                output[key] = newID
            }
        }

        if var boundElements = output["boundElements"] as? [[String: Any]] {
            for index in boundElements.indices {
                if let id = boundElements[index]["id"] as? String,
                   let newID = idMapping[id] {
                    boundElements[index]["id"] = newID
                }
            }
            output["boundElements"] = boundElements
        }

        for key in ["startBinding", "endBinding"] {
            if var binding = output[key] as? [String: Any],
               let id = binding["elementId"] as? String,
               let newID = idMapping[id] {
                binding["elementId"] = newID
                output[key] = binding
            }
        }

        if let groupIDs = output["groupIds"] as? [String] {
            output["groupIds"] = groupIDs.map { groupIDMapping[$0] ?? $0 }
        }

        return output
    }

    private struct Bounds {
        var minX: Double
        var minY: Double
        var maxX: Double
        var maxY: Double

        var midX: Double { (minX + maxX) / 2 }
        var midY: Double { (minY + maxY) / 2 }
    }

    private static func bounds(of elements: [[String: Any]]) -> Bounds? {
        var result: Bounds?
        for element in elements {
            guard let x = number(element["x"]),
                  let y = number(element["y"]) else {
                continue
            }
            let width = number(element["width"]) ?? 0
            let height = number(element["height"]) ?? 0
            let minX = min(x, x + width)
            let minY = min(y, y + height)
            let maxX = max(x, x + width)
            let maxY = max(y, y + height)

            if let current = result {
                result = Bounds(
                    minX: Swift.min(current.minX, minX),
                    minY: Swift.min(current.minY, minY),
                    maxX: Swift.max(current.maxX, maxX),
                    maxY: Swift.max(current.maxY, maxY)
                )
            } else {
                result = Bounds(minX: minX, minY: minY, maxX: maxX, maxY: maxY)
            }
        }
        return result
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }
}
