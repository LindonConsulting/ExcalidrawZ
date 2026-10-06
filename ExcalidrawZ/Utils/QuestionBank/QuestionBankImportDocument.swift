//
//  QuestionBankImportDocument.swift
//  ExcalidrawZ
//
//  Renders PDF pages / image files for the crop-to-question importer and
//  turns a crop into a capture draft (image element + binary file).
//

import Foundation
import CoreGraphics
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import CryptoKit

struct QuestionBankImportDocument: Identifiable {
    let id = UUID()
    enum ImportError: LocalizedError {
        case unsupported
        case unreadable
        case emptyCrop

        var errorDescription: String? {
            switch self {
                case .unsupported: return "Only PDF, PNG and JPEG files can be imported."
                case .unreadable: return "The file could not be read."
                case .emptyCrop: return "Drag a rectangle around a question first."
            }
        }
    }

    let name: String
    let pageCount: Int
    private let source: Source

    private enum Source {
        case pdf(PDFDocument)
        case image(CGImage)
    }

    init(url: URL) throws {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        guard let type = UTType(filenameExtension: url.pathExtension) else { throw ImportError.unsupported }
        try self.init(data: data, type: type, name: url.deletingPathExtension().lastPathComponent)
    }

    init(data: Data, type: UTType, name: String) throws {
        self.name = name
        if type.conforms(to: .pdf) {
            guard let document = PDFDocument(data: data), document.pageCount > 0 else { throw ImportError.unreadable }
            source = .pdf(document)
            pageCount = document.pageCount
        } else if type.conforms(to: .image) {
            guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
            else { throw ImportError.unreadable }
            source = .image(image)
            pageCount = 1
        } else {
            throw ImportError.unsupported
        }
    }

    /// Renders a page at roughly `scale`× its point size (PDF) or returns the image.
    func renderPage(_ index: Int, scale: CGFloat = 2) -> CGImage? {
        switch source {
            case .image(let image):
                return image
            case .pdf(let document):
                guard let page = document.page(at: index) else { return nil }
                let bounds = page.bounds(for: .mediaBox)
                let width = Int(bounds.width * scale), height = Int(bounds.height * scale)
                guard width > 0, height > 0,
                      let context = CGContext(
                        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                      )
                else { return nil }
                context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
                context.fill(CGRect(x: 0, y: 0, width: width, height: height))
                context.saveGState()
                context.scaleBy(x: scale, y: scale)
                context.translateBy(x: -bounds.origin.x, y: -bounds.origin.y)
                page.draw(with: .mediaBox, to: context)
                context.restoreGState()
                return context.makeImage()
        }
    }

    /// Crops `rect` (pixel coordinates, top-left origin) out of a rendered page
    /// and builds a capture draft containing one image element.
    static func makeDraft(from page: CGImage, crop rect: CGRect, pixelsPerPoint: CGFloat) throws -> QuestionBankCaptureDraft {
        let clamped = rect.integral.intersection(CGRect(x: 0, y: 0, width: page.width, height: page.height))
        guard clamped.width >= 8, clamped.height >= 8, let cropped = page.cropping(to: clamped),
              let png = pngData(from: cropped)
        else { throw ImportError.emptyCrop }
        return try makeDraft(png: png, pointSize: CGSize(width: Double(cropped.width) / Double(pixelsPerPoint),
                                                         height: Double(cropped.height) / Double(pixelsPerPoint)))
    }

    /// Builds a one-image draft from PNG data shown at `pointSize` on the canvas.
    static func makeDraft(png: Data, pointSize: CGSize) throws -> QuestionBankCaptureDraft {
        let fileID = Insecure.SHA1.hash(data: png).map { String(format: "%02x", $0) }.joined()
        let width = Double(pointSize.width)
        let height = Double(pointSize.height)
        let now = Date().timeIntervalSince1970 * 1000

        let element: [String: Any] = [
            "type": "image", "id": ExcalidrawNanoID.make(), "fileId": fileID, "status": "saved",
            "x": 0, "y": 0, "width": width, "height": height, "angle": 0, "scale": [1, 1],
            "strokeColor": "transparent", "backgroundColor": "transparent", "fillStyle": "solid",
            "strokeWidth": 1, "strokeStyle": "solid", "roughness": 1, "opacity": 100, "roundness": NSNull(),
            "groupIds": [], "frameId": NSNull(), "boundElements": NSNull(), "link": NSNull(), "locked": false,
            "seed": Int.random(in: 1...Int(Int32.max)), "version": 1, "versionNonce": Int.random(in: 1...Int(Int32.max)),
            "isDeleted": false, "updated": now,
        ]
        let file: [String: Any] = [
            "id": fileID, "mimeType": "image/png", "created": Int(now),
            "dataURL": "data:image/png;base64," + png.base64EncodedString(),
        ]
        return QuestionBankCaptureDraft(
            elementsJSON: try JSONSerialization.data(withJSONObject: [element]),
            filesJSON: try JSONSerialization.data(withJSONObject: [fileID: file]),
            thumbnailPNG: png,
            elementCount: 1,
            textContent: []
        )
    }

    static func pngData(from image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
