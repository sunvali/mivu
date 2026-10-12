import Foundation
import UIKit
import ImageIO
import Testing
@testable import Mivu

@Suite @MainActor struct CoachPhotoTests {
    @Test func highEntropyPhotosKeepEveryOriginalAndFitActualRequestBody() throws {
        let side = 1024
        var state: UInt32 = 42
        var pixels = [UInt8](repeating: 255, count: side * side * 4)
        for i in pixels.indices where i % 4 != 3 {
            state = state &* 1664525 &+ 1013904223; pixels[i] = UInt8(truncatingIfNeeded: state >> 16)
        }
        let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
        let image = try #require(CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent))
        let original = try #require(UIImage(cgImage: image).jpegData(compressionQuality: 1))
        let originals = Array(repeating: original, count: 8)
        #expect(originals.reduce(0) { $0 + $1.count } > 4_194_304)
        let copies = try PhotoImport.visionCopies(originals)
        #expect(copies.count == originals.count)
        #expect(copies.reduce(0) { $0 + $1.count } <= 4_194_304)
        #expect(originals.allSatisfy { $0 == original })
        #expect(copies.allSatisfy { CGImageSourceCreateWithData($0 as CFData, nil) != nil })
        let input = try CoachInferenceInput.message(role: .user, text: "Synthetic eight-photo capture", images: copies).object()
        let body = try JSONSerialization.data(withJSONObject: ["model": "fixture", "input": [input], "store": false, "stream": true])
        #expect(body.count <= 8_388_608)
    }
}
