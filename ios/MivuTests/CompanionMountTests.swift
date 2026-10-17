import Lottie
import SwiftUI
import Testing
import UIKit
@testable import Mivu

@Suite(.serialized) @MainActor struct CompanionMountTests {
    @Test func currentSurfaceRemountResumesThinkingWithoutReplayingCanceledSuccess() async throws {
        for pose in [CompanionPose.thinking, .saved] {
            let runtime = CompanionRuntime()
            await runtime.select(CharacterCatalog.bundled.resolve("pip"))
            await runtime.attach(eligible: true)
            let output = CompanionOutput(pose: pose, playback: .animated,
                reactionID: pose == .saved ? UUID() : nil, nextDeadline: nil)
            let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 180, height: 180)
            let view = CompanionView(presentation: output, darkMode: false, size: 160, runtime: runtime)
            let host = UIHostingController(rootView: AnyView(view))
            window.rootViewController = host
            window.isHidden = false
            defer { runtime.stop(); window.isHidden = true }
            await runtime.apply(output, darkMode: false)
            try await Task.sleep(for: .milliseconds(60))
            #expect(runtime.player?.isAnimationPlaying == true)
            host.rootView = AnyView(Color.clear)
            try await Task.sleep(for: .milliseconds(60))
            #expect(runtime.player?.isAnimationPlaying == false)
            host.rootView = AnyView(view)
            try await Task.sleep(for: .milliseconds(100))
            if pose == .thinking {
                #expect(runtime.player?.isAnimationPlaying == true, "A remounted current surface must resume its still-current thinking loop")
            } else {
                #expect(runtime.displayedPose == .resting, "Remount must discard a canceled success rather than resume it")
                #expect(runtime.triggerCount == 1)
                #expect(runtime.player?.isAnimationPlaying == true, "A canceled success returns to living idle")
            }
        }
    }
    @Test func staleMountedPresentationCannotReplaceNewerRootReaction() async throws {
        let runtime = CompanionRuntime()
        await runtime.select(CharacterCatalog.bundled.resolve("pip"))
        await runtime.attach(eligible: true)
        let old = CompanionOutput(pose: .saved, playback: .animated, reactionID: UUID(), nextDeadline: nil)
        let newest = CompanionOutput(pose: .reviewed, playback: .animated, reactionID: UUID(), nextDeadline: nil)
        await runtime.apply(old, darkMode: false)
        await runtime.apply(newest, darkMode: false)
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 180, height: 180)
        window.rootViewController = UIHostingController(rootView:
            CompanionView(presentation: old, darkMode: false, size: 160, runtime: runtime))
        window.isHidden = false
        defer { runtime.stop(); window.isHidden = true }
        try await Task.sleep(for: .milliseconds(80))
        #expect(runtime.displayedPose == .reviewed, "A delayed mount must use the latest root output")
        #expect(runtime.triggerCount == 2, "Mounting must never resurrect an older reaction ID")
    }

}
