import Lottie
import Testing
import UIKit
@testable import Mivu

@MainActor struct CompanionSurfaceTests {
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
            let name = ["resting", "attentive", "thinking", "saved", "reviewed", "recovery", "greeting"][pose.rawValue]
            let reaction = [.saved, .reviewed, .greeting].contains(pose) ? UUID() : nil
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
