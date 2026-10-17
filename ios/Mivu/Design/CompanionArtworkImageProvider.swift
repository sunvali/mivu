import CoreGraphics
import Foundation
import ImageIO
import Lottie

/// Prepares the approved white-backed painting once; animation only transforms cached pixels.
final class CompanionArtworkImageProvider: AnimationImageProvider {
    private let image: CGImage
    private let extras: [String: CGImage]
    private let imageName: String

    init(artworkURL: URL, matteURL: URL) throws {
        func decode(_ url: URL) throws -> CGImage {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw ArtworkError.invalidImage }
            return image
        }
        guard let image = Self.applyingMatte(try decode(artworkURL), alpha: try decode(matteURL)) else {
            throw ArtworkError.invalidImage
        }
        self.image = image
        imageName = artworkURL.lastPathComponent
        let prefix = artworkURL.lastPathComponent.replacingOccurrences(of: "-artwork.png", with: "")
        var extras: [String: CGImage] = [:]
        for suffix in ["eyelids", "coach", "coach-eyelids"] {
            let name = prefix + "-" + suffix + ".png"
            let url = artworkURL.deletingLastPathComponent().appendingPathComponent(name)
            extras[name] = try decode(url)
        }
        self.extras = extras
    }

    func imageForAsset(asset: ImageAsset) -> CGImage? {
        if asset.name == imageName { return image }
        return extras[asset.name]
    }

    static func applyingMatte(_ artwork: CGImage, alpha: CGImage) -> CGImage? {
        guard artwork.width == alpha.width, artwork.height == alpha.height,
              var paint = rgba(artwork), let mask = rgba(alpha) else { return nil }
        for index in stride(from: 0, to: paint.count, by: 4) {
            let red = Int(paint[index]), green = Int(paint[index + 1]), blue = Int(paint[index + 2])
            var opacity = Int(mask[index])
            if opacity >= 250 { opacity = 255 }
            if opacity < 200 && max(red, max(green, blue)) - min(red, min(green, blue)) < 18 && min(red, min(green, blue)) > 210 { opacity = 0 }
            for channel in 0..<3 {
                paint[index + channel] = UInt8(max(0, min(opacity, Int(paint[index + channel]) - (255 - opacity))))
            }
            paint[index + 3] = UInt8(opacity)
        }
        guard let provider = CGDataProvider(data: Data(paint) as CFData) else { return nil }
        return CGImage(width: artwork.width, height: artwork.height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: artwork.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    private static func rgba(_ image: CGImage) -> [UInt8]? {
        // Matte samples are linear coverage, so read grayscale bytes without color conversion.
        if image.bitsPerPixel == 8, image.colorSpace?.model == .monochrome,
           let data = image.dataProvider?.data, let pointer = CFDataGetBytePtr(data) {
            var output = [UInt8](repeating: 255, count: image.width * image.height * 4)
            for y in 0..<image.height {
                for x in 0..<image.width {
                    let offset = (y * image.width + x) * 4
                    for channel in 0..<3 { output[offset + channel] = pointer[y * image.bytesPerRow + x] }
                }
            }
            return output
        }
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let valid = bytes.withUnsafeMutableBytes { memory -> Bool in
            guard let context = CGContext(data: memory.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        return valid ? bytes : nil
    }

    private enum ArtworkError: Error { case invalidImage }
}
