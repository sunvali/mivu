import SwiftUI
import Testing
import UIKit
@testable import Mivu

@Suite(.serialized) @MainActor struct CompanionMountTests {
    @Test func currentSurfaceRemountKeepsThinkingWithoutReplayingSuccess() async throws {
        for pose in [CompanionPose.thinking, .saved, .submitted] {
            let runtime = CompanionRuntime()
            await runtime.select(CharacterCatalog.bundled.resolve("pip"))
            await runtime.attach(eligible: true)
            let output = CompanionOutput(pose: pose, playback: .animated,
                reactionID: pose == .thinking ? nil : UUID(), nextDeadline: nil)
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
            let rig = try #require(runtime.rig)
            #expect(rig.window != nil && !animationKeys(in: rig.layer).isEmpty)
            host.rootView = AnyView(Color.clear)
            try await Task.sleep(for: .milliseconds(60))
            #expect(rig.window == nil)
            host.rootView = AnyView(view)
            try await Task.sleep(for: .milliseconds(100))
            #expect(rig.window != nil)
            if pose == .thinking {
                #expect(runtime.displayedPose == .thinking && runtime.lastGestureName == "thinking",
                        "A remounted current surface must keep its still-current thinking loop")
            } else {
                #expect(runtime.triggerCount == 1, "Remount must never replay a consumed success")
                try await Task.sleep(for: .milliseconds(1000))
                #expect(runtime.displayedPose == .resting && runtime.triggerCount == 1)
                #expect(animationKeys(in: rig.layer).contains("breath"), "A canceled success returns to gentle breathing")
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
