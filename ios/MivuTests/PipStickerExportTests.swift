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

    /// A loop's wrap (last frame back to the first) is no bigger a step than its ordinary frame-to-frame steps,
    /// and it fits WhatsApp's timing: at most 10 s, no frame shorter than 8 ms.
    @Test func loopClosesWithinTolerance() throws {
        for sticker in PipStickerCatalog.all {
            guard case .animated(let frames, let fps) = sticker.kind else { continue }
            #expect(frames.count >= 12, "\(sticker.id) is barely animated")
            #expect(Double(frames.count) / fps <= 10 && 1000 / fps >= 8, "\(sticker.id)")
            let alphas = try frames.map { try Self.alpha(renderSticker($0, hidden: sticker.hidden)) }
            let steps = zip(alphas, alphas.dropFirst()).map(Self.difference)
            let mean = steps.reduce(0, +) / Double(steps.count)
            let seam = Self.difference(alphas[alphas.count - 1], alphas[0])
            #expect(mean > 0 && seam <= mean * 1.5, "\(sticker.id): seam \(seam), mean step \(mean)")
        }
    }

    /// Writes every sticker's raw frames for design-system/mivu/stickers/pack.py, but only when
    /// `build/pip-stickers/frames/` exists (`mkdir -p` it first); otherwise it just checks the frames render.
    @Test func exportFrames() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let out = repo.appendingPathComponent("build/pip-stickers/frames")
        let exporting = FileManager.default.fileExists(atPath: out.path)
        for sticker in PipStickerCatalog.all {
            let (frames, fps): ([PipPose], Double) = switch sticker.kind {
            case .still(let pose): ([pose], 0)
            case .animated(let frames, let fps): (frames, fps)
            }
            let folder = out.appendingPathComponent(sticker.id)
            if exporting {
                try? FileManager.default.removeItem(at: folder)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            }
            for (n, pose) in frames.enumerated() {
                let png = try #require(try renderSticker(pose, hidden: sticker.hidden).pngData())
                #expect(UIImage(data: png)?.cgImage.map { ($0.width, $0.height, $0.alphaInfo != .none) } ?? (0, 0, false) == (512, 512, true), "\(sticker.id) \(n)")
                if exporting { try png.write(to: folder.appendingPathComponent(String(format: "%04d.png", n))) }
            }
            if exporting {
                let meta: [String: Any] = ["id": sticker.id, "emoji": sticker.emoji, "animated": fps > 0, "fps": fps]
                try JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted, .sortedKeys])
                    .write(to: folder.appendingPathComponent("meta.json"))
            }
        }
    }

    private static func alpha(_ image: UIImage) -> [UInt8] {
        guard let cg = image.cgImage else { return [] }
        var pixels = [UInt8](repeating: 0, count: cg.width * cg.height)
        pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: cg.width, height: cg.height, bitsPerComponent: 8,
                                    bytesPerRow: cg.width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue)
            context?.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        }
        return pixels
    }

    /// Mean absolute alpha change per pixel, 0...255.
    private static func difference(_ a: [UInt8], _ b: [UInt8]) -> Double {
        Double(zip(a, b).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }) / Double(max(a.count, 1))
    }

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
