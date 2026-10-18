import Foundation
import Testing
@testable import Mivu

private actor ActivityInference {
    private var continuation: CheckedContinuation<CoachInferenceResult, Never>?
    var started = false

    func respond() async -> CoachInferenceResult {
        await withCheckedContinuation {
            continuation = $0
            started = true
        }
    }

    func finish() {
        continuation?.resume(returning: CoachInferenceResult(model: "fixture", text: "Synthetic guidance", calls: [], outputItems: []))
        continuation = nil
    }
}

@Suite @MainActor struct CoachActivityTests {
    @Test func thinkingTracksTheActualInferenceAndClearsOnCancellation() async throws {
        let path = URL.temporaryDirectory.appending(path: "CoachActivity-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: path) }
        let store = DiaryStore(directory: path)
        _ = try await store.createProfile(DiaryProfile(name: "Synthetic coach"))
        let diary = DiaryViewModel(store: store)
        await diary.load(createDefaultProfile: false)
        let suspended = ActivityInference()
        let coach = CoachViewModel(diary: diary, connection: ChatGPTConnection(), inference: { { _, _ in await suspended.respond() } })
        coach.draft.text = "Synthetic question"
        #expect(await coach.send())

        let deadline = ContinuousClock().now.advanced(by: .seconds(10))
        while !(await suspended.started) && ContinuousClock().now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        guard await suspended.started else {
            coach.cancel(); await suspended.finish(); await coach.waitForWorker()
            Issue.record("Inference did not start")
            return
        }

        #expect(coach.activity == .thinking)
        #expect(coach.activityTurnID == coach.turns.last?.id)
        coach.cancel()
        #expect(coach.activity == nil)
        await suspended.finish()
        await coach.waitForWorker()
        #expect(coach.activity == nil)
    }
}
