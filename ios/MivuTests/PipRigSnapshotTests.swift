import CoreGraphics
import QuartzCore
import Testing
import UIKit
@testable import Mivu

@Suite @MainActor struct PipRigSnapshotTests {
    private static let safeArea = CGRect(x: 40, y: 32, width: 432, height: 440)

    private func rig(_ set: PipPose.BodySet, side: CGFloat = 200) throws -> PipRigView {
        let view = PipRigView(asset: try PipRigAsset.load(PipRigAssetTests.bundledData()), set: set)
        view.frame = CGRect(x: 0, y: 0, width: side, height: side)
        view.layoutIfNeeded()
        return view
    }

    /// Union of every drawn path, in the view's coordinates.
    private func drawnBounds(_ layer: CALayer, in root: CALayer) -> CGRect {
        guard !layer.isHidden, layer.opacity > 0 else { return .null }
        var box = CGRect.null
        if let shape = layer as? CAShapeLayer, let path = shape.path, !path.isEmpty {
            box = shape.convert(path.boundingBoxOfPath, to: root)
        }
        return (layer.sublayers ?? []).reduce(box) { $0.union(drawnBounds($1, in: root)) }
    }

    @Test(arguments: [PipPose.BodySet.standing, .seated, .curled])
    func allSetsFitArtboardInBothAppearances(set: PipPose.BodySet) throws {
        for dark in [false, true] {
            for side in [200.0, 40.0] as [CGFloat] {
                let view = try rig(set, side: side)
                view.isDark = dark
                var pose = PipPose.rest
                pose.set = set
                view.apply(pose, animated: false)
                let scale = side / 512
                let safe = CGRect(x: Self.safeArea.minX * scale, y: Self.safeArea.minY * scale,
                                  width: Self.safeArea.width * scale, height: Self.safeArea.height * scale)
                let drawn = drawnBounds(view.layer, in: view.layer)
                #expect(safe.insetBy(dx: -0.5, dy: -0.5).contains(drawn), "\(set) \(side) dark \(dark): \(drawn)")

                let head = try #require(view.layer(named: "head@right")?.sublayers?.first as? CAShapeLayer)
                let headRect = head.convert(head.path!.boundingBoxOfPath, to: view.layer).integral
                let image = UIGraphicsImageRenderer(bounds: view.bounds).image { view.layer.render(in: $0.cgContext) }
                #expect(Self.hasInk(image, in: headRect), "\(set) \(side) dark \(dark): empty head")
            }
        }
    }

    /// The chart card is held out to the side: every Progress pose must stay inside the safe area so the crop never cuts it.
    @Test func progressPosesKeepTheChartInsideTheArtboard() throws {
        let moments: [PipMoment] = [.presenting(cheer: true), .presenting(cheer: false), .progressEntrance(cheer: true),
                                    .progressEntrance(cheer: false), .progressRange, .progressTap]
        for moment in moments {
            for key in PipGestureLibrary.gesture(for: moment).keys where key.pose.chart {
                // Measured in pixels: nothing may be drawn right of x 472 on the 512 artboard.
                let view = try rig(.standing, side: 512)
                view.apply(key.pose, animated: false)
                let image = UIGraphicsImageRenderer(bounds: view.bounds).image { view.layer.render(in: $0.cgContext) }
                #expect(!Self.hasInk(image, in: CGRect(x: 474, y: 0, width: 38, height: 512)), "\(moment) at \(key.at)")
            }
        }
    }

    @Test func restPoseIsStanding() throws {
        #expect(PipPose.rest.set == .standing)
        let view = try rig(.seated)
        #expect(view.layer(named: "body@seated")?.isHidden == false)
        view.apply(.rest, animated: false)
        #expect(view.layer(named: "body")?.isHidden == false)
        #expect(view.layer(named: "body@seated")?.isHidden == true)
    }

    @Test func headRidesTheActiveSetsBody() throws {
        let view = try rig(.standing)
        for set in [PipPose.BodySet.seated, .curled, .standing] {
            var pose = PipPose.rest
            pose.set = set
            view.apply(pose, animated: false)
            let body = try #require(view.layer(named: set == .standing ? "body" : "body@\(set.rawValue)"))
            var ancestor = view.layer(named: "head@right")?.superlayer
            while let layer = ancestor, layer !== body { ancestor = layer.superlayer }
            #expect(ancestor === body, "\(set)")
            #expect(view.layer(named: "head@right")?.isHidden == false)
        }
    }

    private static func hasInk(_ image: UIImage, in rect: CGRect) -> Bool {
        guard let cg = image.cgImage else { return false }
        let s = image.scale
        let crop = CGRect(x: rect.minX * s, y: rect.minY * s, width: rect.width * s, height: rect.height * s)
        guard let part = cg.cropping(to: crop) else { return false }
        let w = part.width, h = part.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let drew = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(part, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return drew && stride(from: 3, to: pixels.count, by: 4).contains { pixels[$0] > 0 }
    }
}
