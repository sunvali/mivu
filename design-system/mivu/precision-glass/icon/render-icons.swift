import AppKit
import Foundation

let iconDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let repoRoot = iconDirectory
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let catalog = repoRoot.appendingPathComponent("ios/Mivu/Assets.xcassets/AppIcon.appiconset")

let variants = [
    ("icon-default.svg", "AppIcon.png"),
    ("icon-dark.svg", "AppIcon-dark.png"),
    ("icon-tinted.svg", "AppIcon-tinted.png")
]

for (source, destination) in variants {
    let sourceURL = iconDirectory.appendingPathComponent(source)
    guard let image = NSImage(contentsOf: sourceURL) else {
        fatalError("Could not load vector source: \(sourceURL.path)")
    }

    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: 1024,
        pixelsHigh: 1024,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    bitmap.size = NSSize(width: 1024, height: 1024)
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    image.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024), from: .zero, operation: .copy, fraction: 1)
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    let outputURL = catalog.appendingPathComponent(destination)
    guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Could not encode PNG: \(outputURL.path)")
    }
    try pngData.write(to: outputURL)
    print("Rendered \(outputURL.path)")
}
