import CoreGraphics
import Foundation
import Testing
@testable import Mivu

struct CompanionArtworkMatteTests {
    @Test func originalPaintIsPreservedWhileWhiteMatteIsRemoved() throws {
        let artwork = try image([200,140,80,255, 228,178,128,255, 255,255,255,255, 252,251,250,255])
        let alpha = try image([255,255,255,255, 128,128,128,255, 0,0,0,255, 64,64,64,255])
        let result = try #require(CompanionArtworkImageProvider.applyingMatte(artwork, alpha: alpha))
        let data = try #require(result.dataProvider?.data)
        let pointer = try #require(CFDataGetBytePtr(data))
        let bytes = Array(UnsafeBufferPointer(start: pointer, count: 16))
        #expect(Array(bytes[0..<4]) == [200,140,80,255])
        #expect(Array(bytes[4..<8]) == [101,51,1,128], "Premultiplied paint reconstructs the original edge on white")
        #expect(Array(bytes[8..<12]) == [0,0,0,0])
        #expect(Array(bytes[12..<16]) == [0,0,0,0], "Neutral background glow must not become a visible fringe")
    }

    @Test func missingRequiredPaintedLayersRejectsThePack() throws {
        let directory = URL.temporaryDirectory.appendingPathComponent("PipMissingLayers-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for name in ["pip-artwork", "pip-artwork-alpha"] {
            let source = try #require(Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Characters/pip"))
            try FileManager.default.copyItem(at: source, to: directory.appendingPathComponent(name + ".png"))
        }
        #expect(throws: (any Error).self) {
            try CompanionArtworkImageProvider(artworkURL: directory.appendingPathComponent("pip-artwork.png"),
                matteURL: directory.appendingPathComponent("pip-artwork-alpha.png"))
        }
    }

    private func image(_ bytes: [UInt8]) throws -> CGImage {
        let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
        return try #require(CGImage(width: 4, height: 1, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: 16, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent))
    }
}
