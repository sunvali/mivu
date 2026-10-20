// Cuts the waving Pip out of the approved painting for the widgets.
// Run from the repo root: swift design-system/mivu/characters/pip/widget/cut-widget-art.swift
import AppKit
import CoreImage
import Vision

let source = URL(fileURLWithPath: "design-system/mivu/characters/pip/reference.png")
let output = URL(fileURLWithPath: "ios/MivuWidgets/Assets.xcassets/PipWave.imageset/pip.png")
// The large waving pose on the light half of the sheet, in top-left pixel coordinates.
let crop = CGRect(x: 200, y: 15, width: 530, height: 610)

let image = CIImage(contentsOf: source)!
let flipped = CGRect(x: crop.minX, y: image.extent.height - crop.maxY, width: crop.width, height: crop.height)
let cropped = image.cropped(to: flipped).transformed(by: .init(translationX: -flipped.minX, y: -flipped.minY))

let request = VNGenerateForegroundInstanceMaskRequest()
let handler = VNImageRequestHandler(ciImage: cropped)
try handler.perform([request])
let observation = request.results!.first!
let masked = try observation.generateMaskedImage(ofInstances: observation.allInstances, from: handler, croppedToInstancesExtent: true)

let context = CIContext()
let cg = context.createCGImage(CIImage(cvPixelBuffer: masked), from: CIImage(cvPixelBuffer: masked).extent)!
let rep = NSBitmapImageRep(cgImage: cg)
try rep.representation(using: .png, properties: [:])!.write(to: output)
print("wrote \(output.path) \(cg.width)x\(cg.height)")
