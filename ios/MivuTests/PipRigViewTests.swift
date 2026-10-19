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
            let animation = try #require(layer.animation(forKey: "blink") as? CAKeyframeAnimation)
            #expect(abs(animation.duration - 0.2) <= 0.02)
            #expect(CATransform3DIsIdentity(layer.transform), "model stays open")
            // Close 70 ms, hold 40 ms, open 90 ms.
            #expect(animation.keyTimes == [0, 0.35, 0.55, 1])
            let closed = try #require((animation.values?[1] as? NSValue)?.caTransform3DValue)
            let lidBox = (layer.sublayers!.first as! CAShapeLayer).path!.boundingBoxOfPath
            #expect(abs(lidBox.maxY + closed.m42 - whiteBox(view, side).maxY) < 0.5, "the lid sweeps down to the lower edge of the eye white")
            let rim = try #require((view.layer(named: "eye-\(side).open@right")?.animation(forKey: "blink") as? CAKeyframeAnimation)?.values?[1] as? NSValue)
            #expect(abs(rim.caTransform3DValue.m22 - 0.97) < 0.001, "3% eye squash")
        }
    }

    @Test func doubleBlinkPlaysTwoLidCycles() throws {
        let view = try rig()
        view.blink(double: true)
        let lid = try #require(view.layer(named: "lid-upper-l@right"))
        let first = try #require(lid.animation(forKey: "blink"))
        let second = try #require(lid.animation(forKey: "blink2"))
        #expect(second.beginTime > first.beginTime + first.duration, "second cycle starts after the first ends")
        #expect(abs(second.duration - 0.2) <= 0.02)
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
        // Freeze the timeline so the comparison cannot drift under load.
        view.layer.timeOffset = view.layer.convertTime(CACurrentMediaTime(), from: nil)
        view.layer.speed = 0
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

    @Test(arguments: [(PipPose.BodySet.seated, PipMoment.saved), (.curled, .earTwitch)])
    func gesturesKeepTheActiveBodySet(set: PipPose.BodySet, moment: PipMoment) async throws {
        let view = PipRigView(asset: try PipRigAsset.load(PipRigAssetTests.bundledData()), set: set)
        view.frame = CGRect(x: 0, y: 0, width: 200, height: 200)
        let gesture = PipGesture.for(moment)
        var finished = false
        view.play(gesture) { _ in finished = true }
        func check(_ when: String) throws {
            let suffix = "@\(set.rawValue)"
            #expect(view.layer(named: "body\(suffix)")?.isHidden == false, "\(when): \(set) body shown")
            #expect(view.layer(named: "body")?.isHidden == true, "\(when): standing body hidden")
            var ancestor = view.layer(named: "head@right")?.superlayer
            while let layer = ancestor, layer !== view.layer(named: "body\(suffix)") { ancestor = layer.superlayer }
            #expect(ancestor != nil, "\(when): head rides the \(set) body")
        }
        try await Task.sleep(for: .milliseconds(Int(gesture.duration * 500)))
        try check("mid-flight")
        try await Task.sleep(for: .milliseconds(Int(gesture.duration * 700) + 100))
        #expect(finished)
        try check("after completion")
    }

    @Test func eyesReachTheTurnBeforeTheHeadSwaps() async throws {
        let view = try rig()
        let turn = PipGesture("turn") { $0.at(0.4) { $0.turn(-1) }; $0.settle(at: 0.8) }
        view.play(turn) { _ in }
        let iris = try #require(view.layer(named: "iris-l@right"))
        let glance = try #require(iris.animation(forKey: "pip.x") as? CABasicAnimation)
        #expect((glance.toValue as? CGFloat ?? 0) < 0, "eyes glance toward the turn first")
        #expect(view.visibleViews == ["right"], "head has not turned yet")
        try await Task.sleep(for: .milliseconds(160))
        #expect(view.visibleViews == ["left"], "head follows about 80 ms later")
    }

    @Test func zeroDurationLoopPlaysOnce() async throws {
        let view = try rig()
        var results: [Bool] = []
        view.play(PipGesture(name: "empty-loop", keys: [], loops: true)) { results.append($0) }
        try await Task.sleep(for: .milliseconds(100))
        #expect(results == [true])
    }

    @Test func removeAllMotionClearsBreathAndGestures() throws {
        let view = try rig()
        view.setBreathing(true)
        view.play(PipGesture.for(.saved)) { _ in }
        view.blink()
        view.removeAllMotion()
        func keys(_ layer: CALayer) -> [String] {
            (layer.animationKeys() ?? []) + (layer.sublayers ?? []).flatMap(keys)
        }
        #expect(keys(view.layer).isEmpty)
    }

    @Test func breathingIsOneAdditiveAnimationThatSurvivesGestures() async throws {
        let view = try rig()
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = view.frame
        window.addSubview(view)
        window.isHidden = false
        view.setBreathing(true)
        let head = try #require(view.layer(named: "head@right"))
        let breath = try #require(head.animation(forKey: "breath") as? CABasicAnimation)
        #expect(breath.isAdditive && breath.autoreverses && breath.repeatCount == .infinity)
        #expect(abs(breath.duration - 4.5) < 0.001)
        #expect(view.layer(named: "chest@seated")?.animation(forKey: "breath") != nil)
        var done = false
        view.play(PipGesture.for(.earTwitch)) { _ in done = true }
        try await Task.sleep(for: .milliseconds(400))
        #expect(done)
        #expect(head.animation(forKey: "breath") != nil)
        view.setBreathing(false)
        #expect(head.animation(forKey: "breath") == nil)
    }
}
