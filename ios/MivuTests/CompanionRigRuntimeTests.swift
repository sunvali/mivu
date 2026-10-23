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
    /// When set, the next wait for an idle beat (2 s or longer) suspends until `release()`, then moves the clock by its length.
    var holdBeat = false
    private(set) var held: CheckedContinuation<TimeInterval, Never>?

    func release() { held?.resume(returning: 0); held = nil }

    func sleep(_ seconds: TimeInterval) async throws {
        sleeps += 1
        if holdBeat, seconds >= 2 {
            holdBeat = false
            _ = await withCheckedContinuation { held = $0 }
            now = now.addingTimeInterval(seconds)
        } else if fast {
            now = now.addingTimeInterval(seconds)
            await Task.yield()
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
        try await Task.sleep(for: .milliseconds(700)) // the cancelled gesture's later keys must never fire
        #expect(animationKeys(in: rig.layer).isEmpty)
        #expect(!runtime.isIdleScheduled && runtime.isPaused)
        #expect(runtime.displayedPose == .resting)
        let asset = try PipRigAsset.load(PipRigAssetTests.bundledData())
        #expect(rig.visibleRect == asset.frames["today"])
        #expect(rig.layer(named: "mouth.smallOpen@right")?.isHidden == false, "the static pose holds the semantic moment, not rest")
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
        await runtime.apply(output(.attentive, typing: 0.1), darkMode: false)
        #expect(await eventually { runtime.playedGestures.suffix(2) == ["wake", "attentive"] && !runtime.curled },
                "a sleeping Pip wakes before it reacts")
    }

    @Test func playedGesturesKeepOnlyTheLastEight() async {
        let runtime = await ready()
        for i in 0..<12 { await runtime.apply(output(.tapped, reaction: UUID(), tapLevel: i % 4), darkMode: false) }
        #expect(runtime.gestureStarts >= 12 && runtime.playedGestures.count == 8)
    }

    @Test func typingMovesTheEyesWithoutRestartingTheGesture() async {
        let runtime = await ready()
        await runtime.apply(output(.attentive, typing: 0), darkMode: false)
        let starts = runtime.gestureStarts
        for progress in [0.3, 0.6, 1.0] { await runtime.apply(output(.attentive, typing: progress), darkMode: false) }
        #expect(runtime.gestureStarts == starts, "same pose: only the gaze updates")
        #expect(runtime.gaze.x > 0.7)
    }

    @Test func interruptedGestureNeverLeavesIdleWaiting() async throws {
        let harness = IdleHarness()
        harness.fast = true
        let runtime = await ready(harness)
        let rig = try #require(runtime.rig)
        let window = try mount(rig)
        defer { runtime.stop(); window.isHidden = true }
        await runtime.apply(output(.saved, reaction: UUID()), darkMode: false)
        rig.removeAllMotion() // the rig is interrupted with no policy change, as when a view leaves the window
        let before = runtime.idleBeatCount
        #expect(await eventually { runtime.displayedPose == .resting })
        #expect(await eventually { runtime.idleBeatCount > before }, "idle resumes after the interruption")
    }

    @Test func everyReactionLivesAtLeastAsLongAsItsGesture() {
        let cases: [(PipMoment, TimeInterval)] =
            [(.curious, MivuMotion.curious), (.patted, MivuMotion.patted), (.welcomeBack, MivuMotion.welcomeBack),
             (.saved, MivuMotion.saved), (.reviewed, MivuMotion.reviewed), (.submitted, MivuMotion.submitted),
             (.firstMealToday, MivuMotion.firstMealToday), (.dayComplete, MivuMotion.dayComplete),
             (.progressEntrance(cheer: false), MivuMotion.progressEntrance), (.progressEntrance(cheer: true), MivuMotion.progressEntrance),
             (.progressRange, MivuMotion.progressRange)]
            + (0...5).map { (PipMoment.progressTap(level: $0), MivuMotion.progressTap) }
            + (0...5).map { (PipMoment.tapped(level: $0), MivuMotion.tapped) }
            + [3, 8, 14, 21].map { (PipMoment.greeting(hour: $0), MivuMotion.greeting) }
        for (moment, lifetime) in cases {
            let gesture = PipGestureLibrary.gesture(for: moment).duration
            #expect(lifetime >= gesture, "\(moment) is cut off: \(lifetime) < \(gesture)")
            #expect(lifetime - gesture <= 0.3, "\(moment) lingers: \(lifetime) vs \(gesture)")
        }
    }

    @Test func runtimeUpdateChangesWhenOnlyTheDraftGrows() {
        func update(_ typing: Double) -> DiaryRootView.RuntimeUpdate {
            DiaryRootView.RuntimeUpdate(output: output(.attentive, typing: typing), surface: .coach, characterID: "pip",
                                        darkMode: false, loaded: true, ready: true)
        }
        #expect(update(0.1) != update(0.5), "the root task must re-apply as the text grows, or the eyes freeze")
        #expect(update(0.5) == update(0.5))
    }

    /// Everything the rig shows: which parts are visible, where they are and how opaque.
    private func look(of rig: PipRigView, _ asset: PipRigAsset) -> [String] {
        asset.parts.map { part in
            let layer = rig.layer(named: part.id)
            return "\(part.id) \(layer?.isHidden == true) \(layer?.opacity ?? 0) \(String(describing: layer?.transform))"
        }
    }

    @Test func staticPlaybackShowsEachSemanticPoseWithoutMotion() async throws {
        for surface in [CompanionSurface.today, .coach] { try await checkStaticPoses(on: surface) }
    }

    private func checkStaticPoses(on surface: CompanionSurface) async throws {
        let runtime = await ready()
        let rig = try #require(runtime.rig)
        let window = try mount(rig)
        defer { runtime.stop(); window.isHidden = true }
        let asset = try PipRigAsset.load(PipRigAssetTests.bundledData())
        await runtime.apply(output(playback: .staticPose), darkMode: false, surface: surface)
        let rest = look(of: rig, asset)
        var seen: [[String]] = [rest]
        for pose in CompanionPose.allCases where pose != .resting {
            await runtime.apply(output(pose, playback: .staticPose), darkMode: false, surface: surface)
            let shown = look(of: rig, asset)
            #expect(animationKeys(in: rig.layer).isEmpty, "\(pose) must not animate")
            #expect(!runtime.isIdleScheduled && runtime.isPaused)
            #expect(!seen.contains(shown), "\(pose) must look different from rest and from every other pose")
            seen.append(shown)
        }
        await runtime.apply(output(playback: .staticPose), darkMode: false, surface: surface)
        #expect(look(of: rig, asset) == rest, "back to rest")
    }

    @Test func staleIdleBeatIsDroppedWhenInputArrivedAfterItWasChosen() async throws {
        let harness = IdleHarness()
        harness.fast = true
        harness.holdBeat = true
        let runtime = await ready(harness)
        defer { runtime.stop() }
        await runtime.apply(output(), darkMode: false)
        #expect(await eventually { harness.held != nil }, "the idle loop chose a beat and is waiting for it")
        harness.now.addTimeInterval(1)
        await runtime.apply(output(.tapped, reaction: UUID()), darkMode: false) // a touch while the beat waits
        #expect(await eventually { runtime.displayedPose == .resting }, "the reaction plays out inside the wait")
        let sleeps = harness.sleeps
        harness.fast = false
        harness.release()
        #expect(await eventually { harness.sleeps > sleeps }, "the loop chose a fresh beat instead")
        #expect(runtime.idleBeatCount == 0, "the beat chosen before the touch must not play after it")
    }

    @Test func idleBeatIsDroppedWhenTheSurfaceChangedWhileItWaited() async throws {
        let harness = IdleHarness()
        harness.fast = true
        harness.holdBeat = true
        let runtime = await ready(harness)
        defer { runtime.stop() }
        await runtime.apply(output(), darkMode: false)
        #expect(await eventually { harness.held != nil })
        await runtime.apply(output(), darkMode: false, surface: .coach)
        try await Task.sleep(for: .milliseconds(500)) // let the surface change's own rest gesture finish
        let sleeps = harness.sleeps
        harness.fast = false
        harness.release()
        #expect(await eventually { harness.sleeps > sleeps })
        #expect(runtime.idleBeatCount == 0)
    }

    @Test func wakeEndsInTheSurfacesRestingSet() async throws {
        #expect(PipGestureLibrary.wake(endingIn: .seated).endSet == .seated)
        #expect(PipGestureLibrary.wake(endingIn: .standing).endSet == .standing)
        let harness = IdleHarness()
        harness.fast = true
        let runtime = await ready(harness)
        let rig = try #require(runtime.rig)
        await runtime.apply(output(), darkMode: false)
        #expect(await eventually(60) { runtime.curled })
        harness.fast = false
        await runtime.apply(output(.attentive), darkMode: false)
        #expect(await eventually { !runtime.curled && runtime.playedGestures.last == "attentive" })
        let asset = try PipRigAsset.load(PipRigAssetTests.bundledData())
        let standing = try #require(asset.parts.first { $0.set == "standing" })
        let curledBody = try #require(asset.parts.first { $0.set == "curled" })
        #expect(rig.layer(named: standing.id)?.isHidden == false && rig.layer(named: curledBody.id)?.isHidden == true)
        runtime.stop()
    }
}
