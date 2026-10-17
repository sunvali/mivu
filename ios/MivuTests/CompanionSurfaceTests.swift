import Lottie
import Testing
import UIKit
@testable import Mivu

@Suite(.serialized) @MainActor struct CompanionSurfaceTests {
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
        for pose in CompanionPose.allCases {
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
