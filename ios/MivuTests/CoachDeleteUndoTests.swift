import Foundation
import Testing
@testable import Mivu

private final class TestClock: @unchecked Sendable { var now = Date(timeIntervalSince1970: 1_800_000_000) }

/// Coach deletes stay instant but keep a short-lived, unexported copy for Undo.
@Suite @MainActor struct CoachDeleteUndoTests {
    private let clock = TestClock()
    private let photoBytes = Data([1, 2, 3])

    private func fixture() async throws -> (DiaryStore, DiaryProfile, DiaryMeal, URL) {
        let root = URL.temporaryDirectory.appending(path: "CoachDeleteUndo-" + UUID().uuidString)
        let clock = clock
        let store = DiaryStore(directory: root, currentTime: { clock.now })
        let profile = DiaryProfile(name: "Synthetic owner")
        _ = try await store.createProfile(profile)
        let day = try await store.startDay(at: clock.now)
        let meal = try await capturedMeal(store, text: "Synthetic lunch", photos: [], reviewFirst: false, dayID: day.id, at: clock.now)
        let items = [FoodItem(name: "Rice", quantity: 1, unit: "cup", nutrition: NutritionValues(kcal: 200), provenance: .estimate, reference: "Synthetic"),
                     FoodItem(name: "Beans", quantity: 1, unit: "cup", nutrition: NutritionValues(kcal: 220), provenance: .estimate, reference: "Synthetic")]
        try await store.applyAnalysis(AnalysisOutput(profileID: profile.id, mealID: meal.id, submissionID: meal.submissions[0].id, baseRevision: 0, items: items), expectedProfileID: profile.id)
        try await store.addPhotos(mealID: meal.id, photos: [MealPhoto(data: photoBytes)], expectedProfileID: profile.id)
        return (store, profile, try #require(await store.snapshotForExport().meals.first), root)
    }

    /// Captures a fresh turn and applies `writes` the way the Coach engine does.
    private func coach(_ store: DiaryStore, _ profile: DiaryProfile, _ writes: [CoachWrite], text: String = "Synthetic request") async throws -> [CoachReceipt] {
        let turn = try await capturedTurn(store, text: text, photos: [], at: clock.now, expectedProfileID: profile.id)
        let epoch = try await store.selectionEpoch(expectedProfileID: profile.id)
        return try await store.applyCoachWrites(writes, turnID: turn.id, epoch: epoch, expectedProfileID: profile.id)
    }

    private func available(_ store: DiaryStore, _ profile: DiaryProfile, _ receipt: CoachReceipt) async throws -> Bool {
        try await store.coachUndoAvailable(operationKey: receipt.operationKey, expectedProfileID: profile.id)
    }

    @Test func deleteMealHoldsSnapshotWithPhotos() async throws {
        let (store, profile, meal, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let receipt = try #require(try await coach(store, profile, [.manual(.deleteMeal(mealID: meal.id, revision: meal.revision))]).first)
        #expect(try await available(store, profile, receipt))
        let exported = try await store.snapshotForExport()
        #expect(!exported.meals.contains { $0.id == meal.id })
        // The held photo never travels with an export or backup.
        let archive = try JSONEncoder().encode(exported)
        #expect(!String(decoding: archive, as: UTF8.self).contains(photoBytes.base64EncodedString()))
    }

    @Test func deleteWeightAndWorkoutHoldSnapshots() async throws {
        let (store, profile, meal, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let weight = try await store.setWeight(dayID: meal.dayID, value: 70, expectedRevision: nil, expectedProfileID: profile.id)
        let draft = WorkoutDraft(kind: .cardio, durationMinutes: 30, exercises: [], estimatedBurnKcal: nil, burnSource: nil)
        let workout = try await store.createWorkout(dayID: meal.dayID, draft: draft, expectedProfileID: profile.id)
        let receipts = try await coach(store, profile, [.deleteWeight(id: weight.id, revision: weight.revision), .deleteWorkout(id: workout.id, revision: workout.revision)])
        #expect(receipts.count == 2)
        for receipt in receipts { #expect(try await available(store, profile, receipt)) }
    }

    @Test func undoOfLoggedMealHoldsSnapshot() async throws {
        let (store, profile, _, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let turn = try await capturedTurn(store, text: "Synthetic apple", photos: [], at: clock.now, expectedProfileID: profile.id)
        let apple = FoodItem(name: "Apple", quantity: 1, unit: "piece", nutrition: NutritionValues(kcal: 95), provenance: .estimate, reference: "Synthetic")
        let logged = try await store.applyCoachFood(turnID: turn.id, targetLocalDate: diaryDateLabel(turn.capturedAt, zone: turn.captureTimeZoneID), items: [apple], expectedProfileID: profile.id)
        let undo = try #require(try await coach(store, profile, [.manual(.undo(operationKey: logged.operationKey))]).first)
        #expect(try await available(store, profile, undo))
    }
}
