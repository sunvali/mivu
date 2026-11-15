import CoreGraphics
import Testing
import UIKit
@testable import Mivu

/// Renders the Pip sticker pack from the app's own rig. See design-system/mivu/stickers/README.md.
@Suite @MainActor struct PipStickerExportTests {
    private static let ids = ["hi", "thanks", "love-it", "lol", "ok", "oops", "good-night",
                              "yum", "hungry", "hydrate", "snack", "you-got-it"]
    private static let animated: Set = ["hi", "good-night", "you-got-it"]

    @Test func catalogHasTheApprovedLineup() {
        #expect(PipStickerCatalog.all.map(\.id) == Self.ids)
        for sticker in PipStickerCatalog.all {
            if case .animated = sticker.kind { #expect(Self.animated.contains(sticker.id), "\(sticker.id)") }
            else { #expect(!Self.animated.contains(sticker.id), "\(sticker.id)") }
            #expect((1...3).contains(sticker.emoji.count), "\(sticker.id)")
        }
    }

    /// The packer re-crops every sticker, so the bar is only that nothing reaches the canvas edge and gets cut.
    @Test func stillsRenderUncutOnTheCanvas() throws {
        for sticker in PipStickerCatalog.all {
            guard case .still(let pose) = sticker.kind else { continue }
            let image = try renderSticker(pose, hidden: sticker.hidden)
            #expect(image.size == CGSize(width: 512, height: 512), "\(sticker.id)")
            #expect(Self.ink(image).map { Self.uncut.contains($0) } == true, "\(sticker.id): \(String(describing: Self.ink(image)))")
        }
    }

    private static let uncut = CGRect(x: 1, y: 1, width: 510, height: 510)

    /// Bounding box of every pixel with any alpha, in points; nil when nothing is drawn.
    static func ink(_ image: UIImage) -> CGRect? {
        guard let cg = image.cgImage else { return nil }
        let w = cg.width, h = cg.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        var box = CGRect.null
        for y in 0..<h { for x in 0..<w where pixels[(y * w + x) * 4 + 3] > 0 { box = box.union(CGRect(x: x, y: y, width: 1, height: 1)) } }
        return box.isNull ? nil : box.applying(CGAffineTransform(scaleX: 1 / image.scale, y: 1 / image.scale))
    }
}
