// Frames a 6.9-inch capture (1320 × 2868) for the App Store, like docs/app-store/screenshots:
// a teal gradient, a white caption on top and the screen in a rounded phone shape.
// Usage: swift scripts/app-store/frame.swift <capture.png> <out.png> "<caption>"
// The caption's direction follows its own letters, so a Hebrew caption reads right to left.
import AppKit

let args = CommandLine.arguments
guard args.count == 4, let capture = NSImage(contentsOfFile: args[1]) else {
    FileHandle.standardError.write(Data("Usage: frame.swift <capture.png> <out.png> \"<caption>\"\n".utf8)); exit(2)
}
// Measured from the English set.
let size = CGSize(width: 1320, height: 2868)
let phone = CGRect(x: 160, y: 580, width: 1000, height: 2180), corner: CGFloat = 140
let captionBox = CGRect(x: 110, y: 200, width: 1100, height: 260)

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = size  // one point per pixel
// A top-left origin, like the measurements; AppKit must be told so that text is drawn upright.
let cg = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
cg.translateBy(x: 0, y: size.height); cg.scaleBy(x: 1, y: -1)
NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)

NSGradient(starting: NSColor(srgbRed: 0, green: 127 / 255, blue: 136 / 255, alpha: 1),
           ending: NSColor(srgbRed: 0, green: 157 / 255, blue: 160 / 255, alpha: 1))!.draw(in: CGRect(origin: .zero, size: size), angle: 90)

let rightToLeft = args[3].unicodeScalars.contains { (0x0590...0x08FF).contains($0.value) }
let style = NSMutableParagraphStyle(); style.alignment = .center; style.lineHeightMultiple = 0.92
style.baseWritingDirection = rightToLeft ? .rightToLeft : .leftToRight
let caption = NSAttributedString(string: args[3], attributes: [.font: NSFont.systemFont(ofSize: 98, weight: .bold), .foregroundColor: NSColor.white, .paragraphStyle: style])
let height = caption.boundingRect(with: captionBox.size, options: [.usesLineFragmentOrigin]).height
caption.draw(with: CGRect(x: captionBox.minX, y: captionBox.midY - height / 2, width: captionBox.width, height: height), options: [.usesLineFragmentOrigin])

NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.25); shadow.shadowBlurRadius = 40; shadow.shadowOffset = CGSize(width: 0, height: -12)
shadow.set()
let shape = NSBezierPath(roundedRect: phone, xRadius: corner, yRadius: corner)
NSColor.white.setFill(); shape.fill()
NSGraphicsContext.restoreGraphicsState()
shape.addClip()
capture.draw(in: phone, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)

NSGraphicsContext.current = nil
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
