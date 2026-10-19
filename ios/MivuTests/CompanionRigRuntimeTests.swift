import CoreGraphics
import Foundation
import QuartzCore
import Testing
import UIKit
@testable import Mivu

/// A hand-driven clock and sleeper so idle scheduling never waits in real time.
@MainActor final class IdleHarness {
    var now = Date(timeIntervalSinceReferenceDate: 1_000_000)
    var sleeps = 0
    /// While true each sleep jumps the clock to its due time and returns; otherwise it waits until cancelled.
    var fast = false

    func sleep(_ seconds: TimeInterval) async throws {
        sleeps += 1
        if fast {
            now = now.addingTimeInterval(seconds)
            try await Task.sleep(for: .milliseconds(1)) // keeps the loop from outrunning gestures that take real time
        } else {
            try await Task.sleep(for: .seconds(3600))
        }
    }

    func runtime(seed: UInt64 = 7) -> CompanionRuntime {
        CompanionRuntime(clock: { [self] in now }, sleep: { [self] in try await sleep($0) },
                         random: SeededGenerator(state: seed))
    }
}

func animationKeys(in layer: CALayer) -> [String] {
    (layer.animationKeys() ?? []) + (layer.sublayers ?? []).flatMap(animationKeys(in:))
}

@Suite(.serialized) @MainActor struct CompanionRigRuntimeTests {
    private let pip = CharacterCatalog.bundled.resolve("pip")

    private func output(_ pose: CompanionPose = .resting, reaction: UUID? = nil, tapLevel: Int = 0,
                        typing: Double = 0, playback: MotionPolicy.Playback = .animated) -> CompanionOutput {
        CompanionOutput(pose: pose, playback: playback, reactionID: reaction, nextDeadline: nil,
                        tapLevel: tapLevel, typingProgress: typing)
    }

    private func ready(_ harness: IdleHarness = IdleHarness()) async -> CompanionRuntime {
        let runtime = harness.runtime()
        await runtime.select(pip)
        await runtime.attach(eligible: true)
        return runtime
    }

    /// Animations only persist on layers that are in a window.
    private func mount(_ rig: PipRigView) throws -> UIWindow {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 160, height: 160)
        rig.frame = window.bounds
        window.addSubview(rig)
        window.isHidden = false
        return window
    }

    private func eventually(_ timeout: TimeInterval = 5, _ done: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !done(), Date() < deadline { try? await Task.sleep(for: .milliseconds(10)) }
        return done()
    }

    @Test func catalogResolvesPipRigSchemaTwo() {
        let descriptor = CharacterCatalog.bundled.resolve("pip")
        #expect(descriptor.schemaVersion == 2)
        #expect(descriptor.animationResourcePath == "Characters/pip/pip-rig.json")
        #expect(Bundle.main.url(forResource: descriptor.animationResourcePath, withExtension: nil) != nil)
    }

    @Test func policyChangeMidGestureLeavesNoAnimationsOrTimers() async throws {
        let runtime = await ready()
        let rig = try #require(runtime.rig)
        let window = try mount(rig)
        defer { window.isHidden = true }
        await runtime.apply(output(.dayComplete, reaction: UUID()), darkMode: false)
        #expect(!animationKeys(in: rig.layer).isEmpty && runtime.isIdleScheduled)
        await runtime.apply(output(.dayComplete, playback: .staticPose), darkMode: false)
        #expect(animationKeys(in: rig.layer).isEmpty)
        #expect(!runtime.isIdleScheduled && runtime.isPaused)
        #expect(runtime.displayedPose == .resting)
        let asset = try PipRigAsset.load(PipRigAssetTests.bundledData())
        #expect(rig.visibleRect == asset.frames["today"])
        #expect(rig.layer(named: "mouth.closedSmile@right")?.isHidden == false)
    }

    @Test func staticPoseShowsTheSeatedRestOnCoach() async throws {
        let runtime = await ready()
        let rig = try #require(runtime.rig)
        await runtime.apply(output(playback: .staticPose), darkMode: false, surface: .coach)
        let asset = try PipRigAsset.load(PipRigAssetTests.bundledData())
        #expect(rig.visibleRect == asset.frames["coach"])
        let seated = try #require(asset.parts.first { $0.set == "seated" })
        #expect(rig.layer(named: seated.id)?.isHidden == false)
        #expect(animationKeys(in: rig.layer).isEmpty)
    }

    @Test func hiddenRuntimeSchedulesNoIdleBeats() async {
        let harness = IdleHarness()
        harness.fast = true
        let runtime = await ready(harness)
        for playback in [MotionPolicy.Playback.hidden, .staticPose] {
            await runtime.apply(output(playback: playback), darkMode: false)
        }
        harness.now.addTimeInterval(60)
        for _ in 0..<20 { await Task.yield() }
        #expect(harness.sleeps == 0 && runtime.idleBeatCount == 0 && !runtime.isIdleScheduled)

        await runtime.apply(output(), darkMode: false)
        #expect(await eventually { runtime.idleBeatCount > 0 }, "an animated Pip does idle")
        runtime.stop()
        let sleeps = harness.sleeps, beats = runtime.idleBeatCount
        harness.now.addTimeInterval(60)
        for _ in 0..<20 { await Task.yield() }
        #expect(!runtime.isIdleScheduled && harness.sleeps == sleeps && runtime.idleBeatCount == beats)
    }

    @Test func oneShotReturnsToRestThenBreathes() async throws {
        let runtime = await ready()
        let rig = try #require(runtime.rig)
        let window = try mount(rig)
        defer { runtime.stop(); window.isHidden = true }
        await runtime.apply(output(.saved, reaction: UUID()), darkMode: false)
        #expect(runtime.displayedPose == .saved)

        #expect(await eventually { runtime.displayedPose == .resting })
        #expect(animationKeys(in: rig.layer).contains("breath"))
        #expect(runtime.triggerCount == 1)
    }

    @Test func greetingVariantFollowsHour() async throws {
        for (hour, name) in [(8, "greeting-morning"), (21, "greeting-evening")] {
            let harness = IdleHarness()
            harness.now = try #require(Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: harness.now))
            let runtime = await ready(harness)
            await runtime.apply(output(.greeting, reaction: UUID()), darkMode: false)
            #expect(runtime.lastGestureName == name)
            runtime.stop()
        }
    }

    @Test func momentsMapFromPoseTapLevelAndHour() {
        let moment = CompanionRuntime.moment
        #expect(moment(.resting, 0, 9) == nil)
        #expect(moment(.tapped, 3, 9) == .tapped(level: 3))
        #expect(moment(.greeting, 0, 21) == .greeting(hour: 21))
        #expect(moment(.patted, 0, 9) == .patted && moment(.welcomeBack, 0, 9) == .welcomeBack)
        #expect(moment(.firstMealToday, 0, 9) == .firstMealToday && moment(.dayComplete, 0, 9) == .dayComplete)
        #expect(moment(.curious, 0, 9) == .curious && moment(.submitted, 0, 9) == .submitted)
        for pose in CompanionPose.allCases where pose != .resting { #expect(moment(pose, 0, 9) != nil) }
    }

    @Test func attentiveEyesFollowTheGrowingText() async {
        let runtime = await ready()
        var xs: [CGFloat] = []
        for progress in [0.0, 0.5, 1.0] {
            await runtime.apply(output(.attentive, typing: progress), darkMode: false)
            xs.append(runtime.gaze.x)
        }
        #expect(xs[0] < xs[1] && xs[1] < xs[2] && xs[0] < 0 && xs[2] > 0)
        await runtime.apply(output(), darkMode: false)
        #expect(runtime.gaze == .zero)
    }

    @Test func sleepingPipWakesBeforeTheReaction() async throws {
        let harness = IdleHarness()
        harness.fast = true
        let runtime = await ready(harness)
        await runtime.apply(output(), darkMode: false)
        #expect(await eventually(60) { runtime.curled }, "a quiet Pip eventually curls up")
        harness.fast = false
        await runtime.apply(output(.attentive), darkMode: false)
        #expect(runtime.lastGestureName == "wake" || runtime.lastGestureName == "attentive")
        #expect(await eventually { runtime.lastGestureName == "attentive" && !runtime.curled })
    }

    @Test func sharedDurationsMatchTheLibrary() {
        #expect(abs(MivuMotion.saved - PipGestureLibrary.gesture(for: .saved).duration) <= 0.02)
        #expect(abs(MivuMotion.reviewed - PipGestureLibrary.gesture(for: .reviewed).duration) <= 0.02)
        #expect(abs(MivuMotion.greeting - PipGestureLibrary.gesture(for: .greeting(hour: 14)).duration) <= 0.02)
    }
}
