import CoreGraphics
import QuartzCore
import Testing
import UIKit
@testable import Mivu

@Suite @MainActor struct PipRigViewTests {
    private func rig(_ pose: PipPose = .rest) throws -> PipRigView {
        let view = PipRigView(asset: try PipRigAsset.load(PipRigAssetTests.bundledData()), set: .seated)
        view.frame = CGRect(x: 0, y: 0, width: 200, height: 200)
        view.apply(pose, animated: false)
        return view
    }

    @Test func restPoseShowsDefaultFaceShapesOnly() throws {
        let view = try rig()
        #expect(view.layer(named: "mouth.closedSmile@right")?.isHidden == false)
        #expect(view.layer(named: "mouth.bigOpen@right")?.isHidden == true)
        #expect(view.layer(named: "eye-l.open@right")?.isHidden == false)
    }

    @Test func headTurnSwapsViewsAndSlidesFeatures() throws {
        var pose = PipPose.rest
        for (turn, shown) in [(1.0, "right"), (-1.0, "left"), (0.0, "front")] {
            pose.headTurn = turn
            let view = try rig(pose)
            #expect(view.visibleViews == [shown])
        }
        let right = try rig(.rest)
        pose.headTurn = 0.8
        let near = try rig(pose)
        let dx = near.layer(named: "nose@right")!.transform.m41 - right.layer(named: "nose@right")!.transform.m41
        #expect(abs(dx - 0.4 * 20 * (-0.2 / 0.65)) < 0.01)
        #expect(near.layer(named: "head@right")!.transform.m41 == 0)
    }

    @Test func gazeMovesPupilsWithinIris() throws {
        let rest = try rig()
        var pose = PipPose.rest
        pose.gaze = CGPoint(x: 1, y: 0)
        let view = try rig(pose)
        func frame(_ v: PipRigView, _ id: String) -> CGRect {
            let layer = v.layer(named: id)!
            let box = (layer.sublayers!.first as! CAShapeLayer).path!.boundingBoxOfPath
            return box.offsetBy(dx: layer.transform.m41, dy: layer.transform.m42)
        }
        let iris = view.layer(named: "iris-l@right")!.transform
        let pupil = frame(view, "pupil-l@right").offsetBy(dx: iris.m41, dy: iris.m42)
        #expect(pupil.minX > frame(rest, "pupil-l@right").minX)
        #expect(frame(view, "iris-l@right").contains(pupil))
    }

    private func whiteBox(_ view: PipRigView, _ side: String) -> CGRect {
        (view.layer(named: "eye-\(side)@right")!.sublayers!.first as! CAShapeLayer).path!.boundingBoxOfPath
    }

    private func irisCentre(_ view: PipRigView, _ side: String) -> CGPoint {
        let layer = view.layer(named: "iris-\(side)@right")!
        let box = (layer.sublayers!.first as! CAShapeLayer).path!.boundingBoxOfPath
        return CGPoint(x: box.midX + layer.transform.m41, y: box.midY + layer.transform.m42)
    }

    @Test func gazeMovesIrisAcrossEyeWhite() throws {
        let view = try rig()
        for side in ["l", "r"] {
            view.look(at: .zero, animated: false)
            let rest = irisCentre(view, side)
            let width = whiteBox(view, side).width
            #expect(view.layer(named: "iris-\(side)@right")?.superlayer?.mask != nil, "iris is masked by the eye white")
            view.look(at: CGPoint(x: 1, y: 0), animated: false)
            #expect(irisCentre(view, side).x - rest.x >= 0.25 * width)
            view.look(at: CGPoint(x: -1, y: 0), animated: false)
            #expect(irisCentre(view, side).x - rest.x <= -0.25 * width)
        }
    }

    @Test func blinkAnimatesUpperLid() throws {
        let view = try rig()
        view.blink()
        for side in ["l", "r"] {
            let layer = try #require(view.layer(named: "lid-upper-\(side)@right"))
            let animation = try #require(layer.animation(forKey: "blink"))
            #expect(abs(animation.duration - 0.2) <= 0.02)
            #expect(CATransform3DIsIdentity(layer.transform), "model stays open")
        }
    }

    @Test func interruptStartsFromPresentationValue() async throws {
        let view = try rig()
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = view.frame
        window.addSubview(view)
        window.isHidden = false
        view.play(PipGesture.for(.saved)) { _ in }
        try await Task.sleep(for: .milliseconds(200))
        let head = try #require(view.layer(named: "head@right"))
        let live = try #require(head.presentation()?.value(forKeyPath: "transform.rotation.z") as? CGFloat)
        view.play(PipGesture.for(.tapped(level: 0))) { _ in }
        let from = try #require((head.animation(forKey: "pip.rotation") as? CABasicAnimation)?.fromValue as? CGFloat)
        #expect(abs(from - live) < 0.001)
    }

    @Test func playCompletionReportsInterruption() async throws {
        let view = try rig()
        var results: [Bool] = []
        view.play(PipGesture.for(.saved)) { results.append($0) }
        view.play(PipGesture.for(.earTwitch)) { results.append($0) }
        try await Task.sleep(for: .milliseconds(900))
        #expect(results == [false, true])
    }

    @Test func heartsAndBlushAreShownByPose() throws {
        var pose = PipPose.rest
        pose.hearts = 2
        pose.blush = true
        let view = try rig(pose)
        #expect(view.layer(named: "heart-2")?.opacity == 1)
        #expect(view.layer(named: "heart-3")?.opacity == 0)
        #expect(view.layer(named: "cheek-blush-l@right")?.isHidden == false)
        #expect(try rig().layer(named: "heart-1")?.opacity == 0)
    }
}
