import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

let iconDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let repoRoot = iconDirectory
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let catalog = repoRoot.appendingPathComponent("ios/Mivu/Assets.xcassets/AppIcon.appiconset")

let variants = [
    ("icon-default.png", "AppIcon.png"),
    ("icon-dark.png", "AppIcon-dark.png"),
    ("icon-tinted.png", "AppIcon-tinted.png")
]

for (source, destination) in variants {
    let sourceURL = iconDirectory.appendingPathComponent(source)
    guard let image = NSImage(contentsOf: sourceURL),
          let sourceImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        fatalError("Could not load icon source: \(sourceURL.path)")
    }

    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
            data: nil, width: 1024, height: 1024, bitsPerComponent: 8,
            bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
          ) else {
        fatalError("Could not create opaque sRGB drawing context")
    }
    context.interpolationQuality = .high
    context.draw(sourceImage, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))

    let outputURL = catalog.appendingPathComponent(destination)
    guard let renderedImage = context.makeImage(),
          let encoder = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("Could not encode PNG: \(outputURL.path)")
    }
    CGImageDestinationAddImage(encoder, renderedImage, nil)
    guard CGImageDestinationFinalize(encoder) else {
        fatalError("Could not write PNG: \(outputURL.path)")
    }
    print("Rendered \(outputURL.path)")
}
