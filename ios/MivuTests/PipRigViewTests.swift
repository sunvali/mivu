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

    /// A window for tests that need a live render tree; the caller hides and drops it when done.
    private func window(holding view: PipRigView) throws -> UIWindow {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = view.frame
        window.addSubview(view)
        window.isHidden = false
        return window
    }

    private func keys(_ layer: CALayer) -> [String] {
        (layer.animationKeys() ?? []) + (layer.sublayers ?? []).flatMap(keys)
    }

    /// Polls until `done` or a generous timeout, instead of sleeping a fixed time.
    private func spin(until done: () -> Bool) async {
        let deadline = Date().addingTimeInterval(5)
        while !done() && Date() < deadline { try? await Task.sleep(for: .milliseconds(5)) }
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
            for part in ["head", "muzzle", "nose", "eye-l.open", "mouth.closedSmile"] {
                #expect(view.layer(named: "\(part)@\(shown)")?.isHidden == false, "\(part)@\(shown) drawn")
            }
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
        var window: UIWindow? = try window(holding: view)
        defer { window?.isHidden = true; window = nil }
        view.play(PipGestureLibrary.gesture(for: .saved)) { _ in }
        try await Task.sleep(for: .milliseconds(200))
        // Freeze the timeline so the comparison cannot drift under load.
        view.layer.timeOffset = view.layer.convertTime(CACurrentMediaTime(), from: nil)
        view.layer.speed = 0
        let head = try #require(view.layer(named: "head@right"))
        let live = try #require(head.presentation()?.value(forKeyPath: "transform.rotation.z") as? CGFloat)
        view.play(PipGestureLibrary.gesture(for: .tapped(level: 0))) { _ in }
        let from = try #require((head.animation(forKey: "pip.rotation") as? CABasicAnimation)?.fromValue as? CGFloat)
        #expect(abs(from - live) < 0.001)
    }

    @Test func playCompletionReportsInterruption() async throws {
        let view = try rig()
        var results: [Bool] = []
        view.play(PipGestureLibrary.gesture(for: .saved)) { results.append($0) }
        view.play(PipGestureLibrary.gesture(for: .earTwitch)) { results.append($0) }
        await spin { results.count == 2 }
        #expect(results == [false, true])
    }

    private final class Probe {}

    /// Plays `gesture` holding a probe in its completion, so a leaked playback keeps the probe alive.
    private func play(_ gesture: PipGesture, on view: PipRigView, results: @escaping (Bool) -> Void = { _ in }) -> Probe? {
        weak var weakProbe: Probe?
        do {
            let probe = Probe()
            weakProbe = probe
            view.play(gesture) { finished in _ = probe; results(finished) }
        }
        return weakProbe
    }

    @Test func finishedGestureFreesItsPlayback() async throws {
        let view = try rig()
        var finished = false
        weak var probe = play(PipGestureLibrary.gesture(for: .earTwitch), on: view) { finished = $0 }
        await spin { finished && probe == nil }
        #expect(finished)
        #expect(probe == nil, "a played-out gesture must not stay alive through its own timers")
        #expect(view.pendingWorkCount == 0)
    }

    @Test func interruptedGestureFreesItsPlayback() async throws {
        let view = try rig()
        var results: [Bool] = []
        weak var probe = play(PipGestureLibrary.gesture(for: .reviewed), on: view) { results.append($0) }
        view.removeAllMotion()
        #expect(results == [false] && view.pendingWorkCount == 0)
        await spin { probe == nil }
        #expect(probe == nil, "an interrupted gesture must not stay alive through its cancelled timers")
    }

    @Test func deallocatedRigEndsItsGesture() async throws {
        var view: PipRigView? = try rig()
        var results: [Bool] = []
        weak var probe = play(PipGestureLibrary.gesture(for: .dayComplete), on: try #require(view)) { results.append($0) }
        view = nil
        #expect(results == [false], "deallocation reports the interruption")
        await spin { probe == nil }
        #expect(probe == nil)
    }

    @Test func loopsKeepOnlyOnePassOfTimers() async throws {
        let view = try rig()
        var results: [Bool] = []
        var pose = PipPose.rest
        pose.joints["head"] = .init(rotation: 0.05)
        let loop = PipGesture(name: "short-loop", keys: [(0.05, pose), (0.1, .rest)], loops: true)
        view.play(loop) { results.append($0) }
        var peak = 0
        for _ in 0..<30 {
            try await Task.sleep(for: .milliseconds(15))
            peak = max(peak, view.pendingWorkCount)
        }
        #expect(results.isEmpty && view.pendingWorkCount > 0, "still looping")
        #expect(peak <= 3, "two keys plus the loop end, never accumulating across passes")
        view.removeAllMotion()
        #expect(results == [false] && view.pendingWorkCount == 0)
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
        let gesture = PipGestureLibrary.gesture(for: moment)
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
        // No settle key: the head stays turned, so a loaded main queue cannot make the test miss a brief window.
        let turn = PipGesture("turn") { $0.at(0.4) { $0.turn(-1) } }
        view.play(turn) { _ in }
        let iris = try #require(view.layer(named: "iris-l@right"))
        // `play` queues the eyes' saccade synchronously; the head swaps later on the main queue.
        let glance = try #require(iris.animation(forKey: "pip.x") as? CABasicAnimation)
        #expect((glance.toValue as? CGFloat ?? 0) < 0, "eyes glance toward the turn first")
        #expect(view.visibleViews == ["right"], "head has not turned yet")
        await spin { view.visibleViews == ["left"] }
        #expect(view.visibleViews == ["left"], "head follows the eyes")
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
        var window: UIWindow? = try window(holding: view)
        defer { window?.isHidden = true; window = nil }
        view.setBreathing(true)
        view.play(PipGestureLibrary.gesture(for: .saved)) { _ in }
        view.blink()
        let head = try #require(view.layer(named: "head@right"))
        #expect(head.animation(forKey: "breath") != nil, "precondition: breathing is running")
        #expect(!keys(view.layer).isEmpty, "precondition: gesture, blink and breath animations exist")
        view.removeAllMotion()
        #expect(head.animation(forKey: "breath") == nil)
        #expect(keys(view.layer).isEmpty)
    }

    @Test func breathingIsOneAdditiveAnimationThatSurvivesGestures() async throws {
        let view = try rig()
        var window: UIWindow? = try window(holding: view)
        defer { window?.isHidden = true; window = nil }
        view.setBreathing(true)
        let head = try #require(view.layer(named: "head@right"))
        let breath = try #require(head.animation(forKey: "breath") as? CABasicAnimation)
        #expect(breath.isAdditive && breath.autoreverses && breath.repeatCount == .infinity)
        #expect(abs(breath.duration - 4.5) < 0.001)
        #expect(view.layer(named: "chest@seated")?.animation(forKey: "breath") != nil)
        var done = false
        view.play(PipGestureLibrary.gesture(for: .earTwitch)) { _ in done = true }
        await spin { done }
        #expect(done)
        #expect(head.animation(forKey: "breath") != nil)
        view.setBreathing(false)
        #expect(head.animation(forKey: "breath") == nil)
    }

    @Test func glanceMidGestureLeavesSpringsAndBreathAlone() async throws {
        let view = try rig()
        var window: UIWindow? = try window(holding: view)
        defer { window?.isHidden = true; window = nil }
        view.setBreathing(true)
        view.play(PipGestureLibrary.gesture(for: .saved)) { _ in }
        let head = try #require(view.layer(named: "head@right"))
        let chest = try #require(view.layer(named: "chest@seated"))
        await spin { head.animation(forKey: "pip.rotation") != nil }
        let spring = try #require(head.animation(forKey: "pip.rotation"))
        view.look(at: CGPoint(x: 0.5, y: 0))
        #expect(head.animation(forKey: "pip.rotation") === spring, "a gaze change does not respring the head")
        #expect(head.animation(forKey: "pip.scaleY") == nil && chest.animation(forKey: "pip.scaleY") == nil, "the breath is never flattened")
        #expect(head.animation(forKey: "breath") != nil && chest.animation(forKey: "breath") != nil)
    }

    @Test func curledIdleBeatsKeepTheSleepyFace() async throws {
        let view = PipRigView(asset: try PipRigAsset.load(PipRigAssetTests.bundledData()), set: .curled)
        view.frame = CGRect(x: 0, y: 0, width: 200, height: 200)
        var asleep = PipPose.rest
        asleep.set = .curled
        asleep.eyes = .closedSleepy
        view.apply(asleep, animated: false)
        var done = false
        view.play(try #require(PipGestureLibrary.gesture(forIdle: .earFlick, curled: true))) { _ in done = true }
        view.blink()
        view.blink(double: true)
        await spin { done }
        #expect(done)
        #expect(view.layer(named: "eye-l.closedSleepy@right")?.isHidden == false, "eyes stay sleepy")
        #expect(view.layer(named: "eye-l.open@right")?.isHidden == true, "eyes did not open")
        #expect(view.layer(named: "lid-upper-l@right")?.animation(forKey: "blink") == nil, "no blink on closed eyes")
    }
}
