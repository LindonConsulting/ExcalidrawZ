//
//  QuestionImageHash.swift
//  ExcalidrawZ
//
//  64-bit difference hash (dHash) of a question thumbnail, used to flag
//  re-imports of the same scan. Small Hamming distance ⇒ likely duplicate.
//

import Foundation
import CoreGraphics
import ImageIO
import TutorStore

enum QuestionImageHash {
    static var duplicateThreshold: Int { ImageHashDistance.duplicateThreshold }

    static func hash(png: Data) -> String? {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return hash(image: image)
    }

    static func hash(image: CGImage) -> String? {
        let width = 9, height = 8
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var bits: UInt64 = 0
        for y in 0..<height {
            for x in 0..<(width - 1) {
                bits <<= 1
                if pixels[y * width + x] > pixels[y * width + x + 1] { bits |= 1 }
            }
        }
        return String(format: "%016llx", bits)
    }

    static func distance(_ a: String, _ b: String) -> Int { ImageHashDistance.hamming(a, b) }
}
