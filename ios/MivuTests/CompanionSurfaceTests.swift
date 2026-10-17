import Lottie
import Testing
@testable import Mivu

@MainActor struct CompanionSurfaceTests {
    @Test func coachPeekSurvivesAHiddenAttachmentWithoutReplayingFeedback() async throws {
        let runtime = CompanionRuntime()
        await runtime.select(CharacterCatalog.bundled.resolve("pip"))
        await runtime.attach(eligible: true)
        let rest = CompanionOutput(pose: .resting, playback: .animated, reactionID: nil, nextDeadline: nil)
        await runtime.apply(rest, darkMode: true, surface: .coach)
        let player = try #require(runtime.player)
        let peek = try #require(player.animation?.frameTime(forMarker: "coach-resting"))
        #expect(player.currentFrame == peek)
        await runtime.attach(eligible: false)
        await runtime.attach(eligible: true)
        await runtime.apply(rest, darkMode: false, surface: .coach)
        #expect(player.currentFrame == peek, "The Coach surface must retain the approved seated peek after a cover or background return")
        #expect(runtime.triggerCount == 0)
        await runtime.apply(rest, darkMode: false, surface: .today)
        #expect(player.currentFrame == player.animation?.frameTime(forMarker: "resting"))
        runtime.stop()
    }
}
