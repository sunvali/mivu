import Foundation
import Testing
@testable import Mivu

private actor CaptureOptionReplies {
    var results: [CoachInferenceResult]
    init(_ calls: [CoachToolCall]) {
        results = [CoachInferenceResult(model: "fixture", text: "", calls: calls, outputItems: []), CoachInferenceResult(model: "fixture", text: "Done", calls: [], outputItems: [])]
    }
    func next() throws -> CoachInferenceResult {
        guard !results.isEmpty else { throw CoachError.limitExceeded }; return results.removeFirst()
    }
}

@Suite @MainActor struct CoachCaptureOptionsTests {
    private func command(_ name: String, _ args: [String: Any]) throws -> CoachToolCall {
        CoachToolCall(id: "action", callID: "action", name: name, namespace: "mivu", arguments: String(decoding: try JSONSerialization.data(withJSONObject: args), as: UTF8.self))
    }
    @Test func conversationalReviewFirstLeavesNutritionOutOfTotals() async throws {
        let path = URL.temporaryDirectory.appending(path: "CoachReview-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: path) }
        let store = DiaryStore(directory: path), profile = DiaryProfile(name: "Synthetic")
        _ = try await store.createProfile(profile)
        let day = try await store.startDay()
        let turn = try await capturedTurn(store, text: "Review my soup before saving totals", photos: [], expectedProfileID: profile.id)
        let call = try command("log_food", ["target_local_date": day.localDate, "review_first": true, "items": [["name": "Soup", "quantity": 1, "unit": "bowl", "kcal": 150, "carbs": 20, "protein": 6, "fat": 4]]])
        let replies = CaptureOptionReplies([call])
        let done = try await CoachEngine(store: store, infer: { _, _ in try await replies.next() }).run(turnID: turn.id, expectedProfileID: profile.id)
        let snapshot = try await store.snapshotForExport()
        let meal = try #require(snapshot.meals.first)
        #expect(meal.state == .awaitingReview && !meal.isSaved)
        #expect(snapshot.totals(dayID: day.id).kcal == nil)
        #expect(meal.submissions.first?.proposal?.items.first?.nutrition.kcal == 150)
        #expect(done.assistantText?.contains("review") == true)
    }
    @Test func retryMealRequeuesItsOriginalCaptureWithoutCreatingFood() async throws {
        let path = URL.temporaryDirectory.appending(path: "CoachRetry-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: path) }
        let store = DiaryStore(directory: path), profile = DiaryProfile(name: "Synthetic")
        _ = try await store.createProfile(profile)
        let day = try await store.startDay()
        let meal = try await capturedMeal(store, text: "Synthetic pending soup", photos: [], reviewFirst: true, dayID: day.id, forCoach: true, expectedProfileID: profile.id)
        let original = try #require(await store.snapshotForExport().coachTurns.first)
        try await store.setCoachTurnState(turnID: original.id, state: .needsRetry, expectedProfileID: profile.id)
        let turn = try await capturedTurn(store, text: "Retry that meal", photos: [], expectedProfileID: profile.id)
        let replies = CaptureOptionReplies([try command("retry_meal", ["meal_id": meal.id.uuidString, "expected_revision": meal.revision])])
        let done = try await CoachEngine(store: store, infer: { _, _ in try await replies.next() }).run(turnID: turn.id, expectedProfileID: profile.id)
        let snapshot = try await store.snapshotForExport()
        #expect(snapshot.meals.count == 1 && snapshot.meals[0].items.isEmpty)
        #expect(snapshot.coachTurns.first { $0.id == original.id }?.state == .captured)
        #expect(snapshot.coachTurns.first { $0.id == original.id }?.text == original.text)
        #expect(done.assistantText == "Trying that meal again.")
    }
    @Test func manualPreferenceSaveRejectsAConcurrentCoachChange() async throws {
        let path = URL.temporaryDirectory.appending(path: "CoachPreferenceRace-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: path) }
        let store = DiaryStore(directory: path), original = DiaryProfile(name: "Synthetic")
        _ = try await store.createProfile(original)
        var coachEdit = original; coachEdit.preferences = "New saved preference"
        try await store.updateProfile(coachEdit, expectedProfileID: original.id)
        var manualEdit = original; manualEdit.preferences = "Old form draft"
        await #expect(throws: DiaryError.staleRevision) {
            try await store.updateProfile(manualEdit, expectedProfile: original, expectedProfileID: original.id)
        }
        #expect(try await store.snapshotForExport().profile == coachEdit)
    }
}
