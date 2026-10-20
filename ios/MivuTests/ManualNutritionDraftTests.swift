import Foundation
import Testing
@testable import Mivu

@Suite struct ManualNutritionDraftTests {
    @Test func knownZeroAndBlankMacrosRemainDistinct() throws {
        var draft = ManualNutritionDraft(); draft.name = "Synthetic water"; draft.kcal = "0"
        #expect(try draft.item().nutrition.kcal == 0)
        #expect(try draft.item().nutrition.carbs == nil)
        let item = try draft.item()
        #expect(item.provenance == .user && item.nutrientSources == ["kcal": .user])
        #expect(item.reference == "Entered manually" && !item.uncertain)
    }
    @Test func commaDecimalsAndStableIdentities() throws {
        var draft = ManualNutritionDraft(); draft.name = "Synthetic oats"; draft.quantity = "1,5"; draft.protein = "3,25"
        let original = draft
        #expect(try draft.item().quantity == 1.5)
        #expect(try draft.item().nutrition.protein == 3.25)
        #expect(try draft.item().id == original.itemID)
        draft.name = "Synthetic porridge"
        #expect(try draft.item().id == original.itemID)
        #expect(draft.mealID == original.mealID && draft.submissionID == original.submissionID)
    }
    @Test func uncertainFrozenIdentityCannotBeReusedForEditedNutrition() throws {
        var draft = ManualNutritionDraft(); draft.name = "Synthetic oats"; draft.kcal = "100"
        let at = Date(timeIntervalSince1970: 1_792_368_000), owner = UUID()
        let target = ManualNutritionTarget.newCurrent(dayID: UUID(), localDate: "2026-10-19", timeZoneID: "UTC", previousActiveDayID: nil)
        let frozen = try draft.freeze(profileID: owner, target: target, at: at, appendingTo: nil)
        #expect(try draft.freeze(profileID: owner, target: target, at: at.addingTimeInterval(60), appendingTo: nil) == frozen)
        draft.kcal = "200"
        #expect(throws: DiaryError.staleRevision) { try draft.freeze(profileID: owner, target: target, at: at, appendingTo: nil) }
        #expect(draft.frozenPayload == frozen)
        draft.releaseUncommittedIdentity()
        let newPayload = try draft.freeze(profileID: owner, target: target, at: at, appendingTo: nil)
        #expect(newPayload.submissionID != frozen.submissionID && newPayload.mealID != frozen.mealID)
        #expect(newPayload.items[0].id != frozen.items[0].id && newPayload.items[0].nutrition.kcal == 200)
    }
    @Test func appendRetainsDateTimeAndEffectiveLegacyPrecision() throws {
        var draft = ManualNutritionDraft(); draft.name = "Synthetic food"; draft.kcal = "0"
        let captured = Date(timeIntervalSince1970: 100), eaten = Date(timeIntervalSince1970: 50), day = UUID()
        let meal = MealReadModel(id: UUID(), dayID: day, capturedAt: captured, eatenAt: eaten, revision: 4,
            timePrecision: nil, items: [], submissions: [], photos: [], sourceTurnID: nil)
        let payload = try draft.freeze(profileID: UUID(), target: .recorded(dayID: day, localDate: "2026-10-18", timeZoneID: "UTC"), at: captured, appendingTo: meal)
        #expect(payload.operation == .append && payload.mealID == meal.id && payload.expectedMealRevision == 4)
        #expect(payload.eatenAt == eaten && payload.timePrecision == .exact)
        #expect(meal.timePrecision == nil)
    }
    @Test func rejectsMissingNameUnknownTotalsAndNonpositiveAmount() {
        var draft = ManualNutritionDraft()
        #expect(throws: DiaryError.invalidData) { try draft.item() }
        draft.name = "Synthetic food"
        #expect(throws: DiaryError.invalidData) { try draft.item() }
        draft.kcal = "100"; draft.quantity = "0"
        #expect(throws: DiaryError.invalidData) { try draft.item() }
        draft.quantity = "-1"
        #expect(throws: DiaryError.invalidData) { try draft.item() }
    }
    @Test func rejectsInvalidNumbersAndBounds() {
        for value in ["nan", "inf", "-1", "10000001", "a"] {
            var draft = ManualNutritionDraft(); draft.name = "Synthetic food"; draft.kcal = value
            #expect(throws: DiaryError.invalidData) { try draft.item() }
        }
        var draft = ManualNutritionDraft(); draft.name = "Synthetic food"; draft.kcal = "100"; draft.quantity = "100001"
        #expect(throws: DiaryError.invalidData) { try draft.item() }
    }
}
