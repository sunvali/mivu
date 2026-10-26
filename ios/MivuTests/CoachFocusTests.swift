import Foundation
import Testing
@testable import Mivu

@Suite @MainActor struct CoachFocusTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func fixture() async throws -> (DiaryStore, DiaryProfile, URL) {
        let root = URL.temporaryDirectory.appending(path: "CoachFocus-" + UUID().uuidString)
        let clock = now
        let store = DiaryStore(directory: root, currentTime: { clock }); let profile = adultProfile(name: "Synthetic")
        _ = try await store.createProfile(profile); _ = try await store.startDay(at: now)
        return (store, profile, root)
    }
    private func food(_ name: String) -> FoodItem {
        FoodItem(name: name, quantity: 1, unit: "portion", nutrition: NutritionValues(kcal: 100), provenance: .estimate, reference: "Synthetic estimate")
    }
    private func log(_ store: DiaryStore, _ profile: DiaryProfile, _ item: FoodItem) async throws -> CoachReceipt {
        let turn = try await capturedTurn(store, text: "Ate " + item.name, photos: [], at: now, expectedProfileID: profile.id)
        return try await store.applyCoachFood(turnID: turn.id, targetLocalDate: "2027-01-15", items: [item], expectedProfileID: profile.id)
    }

    @Test func lastChangedIsMostRecentMealToday() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let older = try await log(store, profile, food("Eggs")); _ = try await log(store, profile, food("Soup"))
        var edited = try #require(await store.snapshotForExport().meals.first { $0.id == older.mealID }?.items.first); edited.quantity = 2
        try await store.editItem(mealID: older.mealID!, item: edited, explicitNutrients: [], expectedRevision: 1, expectedProfileID: profile.id)
        let turn = try await capturedTurn(store, text: "Make that three", photos: [], at: now, expectedProfileID: profile.id)
        let last = try #require(await store.coachContext(turnID: turn.id, expectedProfileID: profile.id).focus?.lastChanged)
        #expect(last.mealID == older.mealID); #expect(last.itemNames == ["Eggs"]); #expect(last.localDate == "2027-01-15")
    }

    @Test func lastChangedAbsentAfterRollover() async throws {
        let (store, profile, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        _ = try await log(store, profile, food("Eggs"))
        let later = now.addingTimeInterval(86400); _ = try await store.startDay(at: later)
        let turn = try await capturedTurn(store, text: "Hello", photos: [], at: later, expectedProfileID: profile.id)
        #expect(try await store.coachContext(turnID: turn.id, expectedProfileID: profile.id).focus == nil)
    }

    @Test func stableRulesStateResolutionOrder() {
        #expect(CoachEngine.stableRules.contains("explicit mention, then replyTo, then pendingQuestion, then focus.lastChanged, then the newest matching meal"))
        #expect(CoachEngine.stableRules.contains("remove it means call delete_meal now without asking again"))
        #expect(!CoachEngine.stableRules.contains("Omitted or paginated evidence cannot establish uniqueness"))
        #expect(!CoachEngine.stableRules.contains("Ask when the matching food or serving is ambiguous."))
    }
}
