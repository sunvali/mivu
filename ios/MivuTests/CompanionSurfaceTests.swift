import Testing
import UIKit
@testable import Mivu

@MainActor private final class CompanionCoveredLoadGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    private(set) var waiting = false
    func pause() async {
        guard !released else { return }
        await withCheckedContinuation { continuation = $0; waiting = true }
    }
    func release() { released = true; continuation?.resume(); continuation = nil }
}

@Suite(.serialized) @MainActor struct CompanionSurfaceTests {
    @Test func cameraCoverageRejectsAColdLoadAndConsumedReaction() async throws {
        let descriptor = CharacterCatalog.bundled.resolve("pip")
        let path = try #require(Bundle.main.url(forResource: descriptor.animationResourcePath, withExtension: nil))
        let bytes = try Data(contentsOf: path)
        let gate = CompanionCoveredLoadGate()
        var firstLoad = true
        let runtime = CompanionRuntime(load: { _ in
            if firstLoad { firstLoad = false; await gate.pause() }
            return bytes
        })
        await runtime.select(descriptor)
        let loading = Task { await runtime.attach(eligible: true) }
        defer { gate.release(); loading.cancel(); runtime.stop() }
        let limit = ContinuousClock.now.advanced(by: .seconds(5))
        while !gate.waiting, ContinuousClock.now < limit { await Task.yield() }
        try #require(gate.waiting)
        let reaction = CompanionOutput(pose: .submitted, playback: .animated, reactionID: UUID(), nextDeadline: nil)
        await runtime.apply(reaction, darkMode: false, surface: .coach)
        await runtime.attach(eligible: false)
        gate.release()
        await loading.value
        #expect(!runtime.isReady && runtime.isPaused && runtime.triggerCount == 0,
                "Canceled asset preparation must not install a playing surface under the camera")
        await runtime.attach(eligible: true)
        await runtime.apply(reaction, darkMode: false, surface: .coach)
        #expect(runtime.isReady && runtime.displayedPose == .resting && runtime.triggerCount == 0,
                "Camera return must not replay acceptance consumed during cold loading")
    }

    @Test(arguments: [CompanionPose.submitted, .saved, .reviewed])
    func cameraCoverPausesWithoutReplayingSaved(pose: CompanionPose) async throws {
        let runtime = CompanionRuntime()
        await runtime.select(CharacterCatalog.bundled.resolve("pip"))
        await runtime.attach(eligible: true)
        let rig = try #require(runtime.rig)
        let window = try mount(rig)
        defer { runtime.stop(); window.isHidden = true }
        let reaction = CompanionOutput(pose: pose, playback: .animated, reactionID: UUID(), nextDeadline: nil)
        await runtime.apply(reaction, darkMode: false, surface: .coach)
        let triggers = runtime.triggerCount
        #expect(triggers == 1)
        await runtime.apply(CompanionOutput(pose: .resting, playback: .hidden, reactionID: nil, nextDeadline: nil),
                            darkMode: false, surface: .coach)
        #expect(runtime.isPaused && animationKeys(in: rig.layer).isEmpty && !runtime.isIdleScheduled)
        for _ in 0..<3 {
            await runtime.attach(eligible: false)
            await runtime.attach(eligible: true)
            await runtime.apply(reaction, darkMode: true, surface: .coach)
            await runtime.reconcileMount(rig)
            #expect(runtime.triggerCount == triggers, "Coverage, return and remount cannot replay a consumed reaction")
            #expect(runtime.displayedPose == .resting)
        }
        let fresh = CompanionOutput(pose: .saved, playback: .animated, reactionID: UUID(), nextDeadline: nil)
        await runtime.apply(fresh, darkMode: true, surface: .coach)
        #expect(runtime.triggerCount == triggers + 1, "A genuinely new durable capture remains eligible after camera return")
    }

    @Test func submittedStartsImmediatelyOnBothSurfaces() async throws {
        let runtime = CompanionRuntime()
        await runtime.select(CharacterCatalog.bundled.resolve("pip"))
        await runtime.attach(eligible: true)
        let rig = try #require(runtime.rig)
        let window = try mount(rig)
        defer { runtime.stop(); window.isHidden = true }
        for surface in [CompanionSurface.today, .coach] {
            await runtime.apply(CompanionOutput(pose: .resting, playback: .animated, reactionID: nil, nextDeadline: nil),
                darkMode: false, surface: surface)
            await runtime.apply(CompanionOutput(pose: .submitted, playback: .animated, reactionID: UUID(), nextDeadline: nil),
                darkMode: false, surface: surface)
            #expect(runtime.lastGestureName == "submitted" && runtime.displayedPose == .submitted)
            #expect(!animationKeys(in: rig.layer).isEmpty, "The submit gesture starts in the same turn")
        }
        #expect(runtime.triggerCount == 2)
    }

    @Test func coachKeepsTheSeatedCropAcrossStatesAndTodayRestoresItsOwn() async throws {
        let runtime = CompanionRuntime()
        await runtime.select(CharacterCatalog.bundled.resolve("pip"))
        await runtime.attach(eligible: true)
        let rig = try #require(runtime.rig)
        let window = try mount(rig)
        defer { runtime.stop(); window.isHidden = true }
        let asset = try PipRigAsset.load(PipRigAssetTests.bundledData())
        let seated = try #require(asset.parts.first { $0.set == "seated" })
        for reattach in [false, true] {
            if reattach { await runtime.attach(eligible: false); await runtime.attach(eligible: true) }
            await runtime.apply(CompanionOutput(pose: .resting, playback: .animated, reactionID: nil, nextDeadline: nil),
                                darkMode: reattach, surface: .coach)
            #expect(rig.visibleRect == asset.frames["coach"] && runtime.triggerCount == 0)
        }
        for pose in CompanionPose.allCases {
            let reaction = ![.resting, .attentive, .thinking, .recovery].contains(pose) ? UUID() : nil
            await runtime.apply(CompanionOutput(pose: pose, playback: .animated, reactionID: reaction, nextDeadline: nil),
                                darkMode: false, surface: .coach)
            #expect(rig.visibleRect == asset.frames["coach"] && rig.layer(named: seated.id)?.isHidden == false,
                    "Every Coach state must stay on its seated rig")
        }
        await runtime.apply(CompanionOutput(pose: .resting, playback: .animated, reactionID: nil, nextDeadline: nil),
                            darkMode: false, surface: .today)
        #expect(rig.visibleRect == asset.frames["today"] && rig.layer(named: seated.id)?.isHidden == true)
    }

    private func mount(_ rig: PipRigView) throws -> UIWindow {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 160, height: 160)
        window.rootViewController = UIViewController()
        rig.frame = window.bounds
        window.rootViewController?.view.addSubview(rig)
        window.isHidden = false
        rig.layoutIfNeeded()
        return window
    }
}
