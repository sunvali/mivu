import Lottie
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
        let player = try #require(runtime.player)
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 160, height: 160)
        window.rootViewController = UIViewController()
        player.frame = window.bounds
        window.rootViewController?.view.addSubview(player)
        window.isHidden = false
        defer { runtime.stop(); window.isHidden = true }
        player.layoutIfNeeded()
        let reaction = CompanionOutput(pose: pose, playback: .animated, reactionID: UUID(), nextDeadline: nil)
        await runtime.apply(reaction, darkMode: false, surface: .coach)
        let triggers = runtime.triggerCount
        #expect(triggers == 1)
        // Coverage can arrive before the submit snapshot's completion callback.
        await runtime.apply(CompanionOutput(pose: .resting, playback: .hidden, reactionID: nil, nextDeadline: nil),
                            darkMode: false, surface: .coach)
        #expect(runtime.isPaused && !player.isAnimationPlaying)
        #expect(player.subviews.allSatisfy { !$0.accessibilityElementsHidden }, "Coverage must remove the continuity snapshot immediately")
        for _ in 0..<3 {
            await runtime.attach(eligible: false)
            await runtime.attach(eligible: true)
            await runtime.apply(reaction, darkMode: true, surface: .coach)
            await runtime.reconcileMount(player)
            #expect(runtime.triggerCount == triggers, "Coverage, return and remount cannot replay a consumed reaction")
            #expect(runtime.displayedPose == .resting)
        }
        let fresh = CompanionOutput(pose: .saved, playback: .animated, reactionID: UUID(), nextDeadline: nil)
        await runtime.apply(fresh, darkMode: true, surface: .coach)
        #expect(runtime.triggerCount == triggers + 1, "A genuinely new durable capture remains eligible after camera return")
    }

    @Test func submittedStartsImmediatelyWithABriefSnapshotAcrossBreathingPhase() async throws {
        let runtime = CompanionRuntime()
        await runtime.select(CharacterCatalog.bundled.resolve("pip"))
        await runtime.attach(eligible: true)
        let player = try #require(runtime.player)
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 160, height: 160)
        window.rootViewController = UIViewController()
        player.frame = window.bounds
        window.rootViewController?.view.addSubview(player)
        window.isHidden = false
        defer { runtime.stop(); window.isHidden = true }
        for surface in [CompanionSurface.today, .coach] {
            await runtime.apply(CompanionOutput(pose: .resting, playback: .animated, reactionID: nil, nextDeadline: nil),
                darkMode: false, surface: surface)
            let rest = surface == .coach ? "coach-resting" : "resting"
            player.pause()
            player.currentFrame = try #require(player.animation?.frameTime(forMarker: rest)) + 120
            player.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
            let reaction = UUID()
            let inheritedDuration = UIView.inheritedAnimationDuration
            let began = ContinuousClock.now
            await runtime.apply(CompanionOutput(pose: .submitted, playback: .animated, reactionID: reaction, nextDeadline: nil),
                darkMode: false, surface: surface)
            CATransaction.flush()
            let marker = surface == .coach ? "coach-submitted" : "submitted"
            let start = try #require(player.animation?.frameTime(forMarker: marker))
            let snapshot = try #require(player.subviews.first { $0.accessibilityElementsHidden },
                "An arbitrary breathing phase must bridge to the submit pose without a visible jump")
            #expect(!snapshot.isUserInteractionEnabled)
            try await Task.sleep(for: .milliseconds(50))
            #expect(player.isAnimationPlaying)
            let firstFrame = player.realtimeAnimationFrame
            #expect(firstFrame >= start && firstFrame < start + 6,
                "Gesture playback must advance within its first100ms under the continuity snapshot")
            try await Task.sleep(for: .milliseconds(50))
            let opacity = snapshot.layer.presentation()?.opacity ?? Float(snapshot.alpha)
            print("Submit bridge surface=\(surface) elapsed=\(began.duration(to: .now)) inherited=\(inheritedDuration) opacity=\(opacity)")
            #expect(opacity <= 0.02, "The previous breathing pose must be invisible at the first100ms sample")
            let cleanupDeadline = began.advanced(by: .milliseconds(500))
            while snapshot.superview != nil, ContinuousClock.now < cleanupDeadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(snapshot.superview == nil, "An invisible bridge must release its view even if UIKit completion is delayed")
            #expect(runtime.displayedPose == .submitted)
        }
        #expect(runtime.triggerCount == 2)
    }

    @Test func coachPeekSurvivesAHiddenAttachmentWithoutReplayingFeedback() async throws {
        let runtime = CompanionRuntime()
        await runtime.select(CharacterCatalog.bundled.resolve("pip"))
        await runtime.attach(eligible: true)
        let player = try #require(runtime.player)
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 160, height: 160)
        window.rootViewController = UIViewController()
        player.frame = window.bounds
        window.rootViewController?.view.addSubview(player)
        window.isHidden = false
        defer { runtime.stop(); window.isHidden = true }
        player.layoutIfNeeded()
        let rest = CompanionOutput(pose: .resting, playback: .animated, reactionID: nil, nextDeadline: nil)
        for reattach in [false, true] {
            if reattach { await runtime.attach(eligible: false); await runtime.attach(eligible: true) }
            await runtime.apply(rest, darkMode: reattach, surface: .coach)
            try await Task.sleep(for: .milliseconds(80))
            let peek = try #require(player.animation?.frameTime(forMarker: "coach-resting"))
            #expect(player.realtimeAnimationFrame >= peek)
            #expect(player.realtimeAnimationFrame < peek + 480)
            #expect(player.isAnimationPlaying)
            #expect(runtime.triggerCount == 0)
        }
        for pose in CompanionPose.allCases where pose.rawValue <= CompanionPose.submitted.rawValue {
            let name = ["resting", "attentive", "thinking", "saved", "reviewed", "recovery", "greeting", "submitted"][pose.rawValue]
            let reaction = [.submitted, .saved, .reviewed, .greeting].contains(pose) ? UUID() : nil
            await runtime.apply(CompanionOutput(pose: pose, playback: .animated, reactionID: reaction, nextDeadline: nil), darkMode: false, surface: .coach)
            try await Task.sleep(for: .milliseconds(60))
            let start = try #require(player.animation?.frameTime(forMarker: "coach-" + name))
            let duration = try #require(player.animation?.durationFrameTime(forMarker: "coach-" + name))
            #expect(player.realtimeAnimationFrame >= start && player.realtimeAnimationFrame <= start + duration,
                    "Every Coach state must stay on its seated rig")
        }
        await runtime.apply(rest, darkMode: false, surface: .today)
        try await Task.sleep(for: .milliseconds(60))
        #expect(player.realtimeAnimationFrame < 480)
    }
}
