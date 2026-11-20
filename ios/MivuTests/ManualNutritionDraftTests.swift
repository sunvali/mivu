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
    @Test func amountScalesKnownNutrientsWithoutDrift() {
        var draft = ManualNutritionDraft()
        #expect(draft.unit == "g" && draft.quantity == "100" && !draft.isDirty)
        draft.name = "Synthetic yogurt"; draft.kcal = "120"; draft.fat = "12.4"; draft.protein = "0"
        draft.setAmount("5")
        #expect(draft.kcal == "6" && draft.fat == "0.6" && draft.protein == "0" && draft.carbs.isEmpty)
        draft.setAmount("250")
        #expect(draft.kcal == "300" && draft.fat == "31")
        draft.setAmount("100")
        #expect(draft.kcal == "120" && draft.fat == "12.4")
        draft.setAmount("")
        #expect(draft.kcal == "120" && draft.quantity.isEmpty)
        draft.setAmount("200")
        #expect(draft.kcal == "240")
    }
    @Test func typedNutrientIsForTheCurrentAmount() {
        var draft = ManualNutritionDraft(); draft.name = "Synthetic oats"; draft.kcal = "100"
        draft.setAmount("200"); #expect(draft.kcal == "200")
        draft.kcal = "50"
        draft.setAmount("400"); #expect(draft.kcal == "100")
        draft.setAmount(""); draft.kcal = "60"
        draft.setAmount("800"); #expect(draft.kcal == "120")
    }
    @Test func unitSwitchKeepsTotalsAndRebases() {
        var draft = ManualNutritionDraft(); draft.name = "Synthetic bar"; draft.kcal = "120"
        draft.setAmount("250"); #expect(draft.kcal == "300")
        draft.setUnit("piece")
        #expect(draft.unit == "piece" && draft.quantity == "1" && draft.kcal == "300")
        draft.setAmount("2"); #expect(draft.kcal == "600")
    }
    @Test func recentFoodKeepsItsSourcesUntilEdited() throws {
        let recent = FoodItem(name: "Synthetic rice", quantity: 150, unit: "g", nutrition: NutritionValues(kcal: 195, carbs: 42, protein: 4),
            provenance: .estimate, reference: "Synthetic estimate", uncertain: true, nutrientSources: ["kcal": .estimate, "carbs": .identifiedSource])
        var draft = ManualNutritionDraft(); draft.use(recent)
        #expect(draft.name == "Synthetic rice" && draft.unit == "g" && draft.quantity == "150" && draft.kcal == "195")
        draft.setAmount("300")
        var item = try draft.item()
        #expect(item.id != recent.id && item.nutrition.kcal == 390 && item.nutrition.carbs == 84 && item.nutrition.fat == nil)
        #expect(item.nutrientSources == ["kcal": .estimate, "carbs": .identifiedSource, "protein": .estimate])
        #expect(item.provenance == .estimate && item.reference == "Synthetic estimate" && item.uncertain)
        draft.kcal = "400"
        item = try draft.item()
        #expect(item.nutrientSources["kcal"] == .user && item.nutrientSources["carbs"] == .identifiedSource)
        draft.carbs = "80"; draft.protein = "9"
        item = try draft.item()
        #expect(item.provenance == .user && item.reference == "Entered manually" && !item.uncertain)
    }
}
