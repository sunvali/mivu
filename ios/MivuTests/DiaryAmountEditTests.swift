import Testing
@testable import Mivu

struct DiaryAmountEditTests {
    // Catches scaling the numeric amount without converting its physical unit.
    @Test func supportedMassConversionsUsePhysicalQuantity() throws {
        let previous = FoodItem(name: "Rice", quantity: 100, unit: "g", nutrition: NutritionValues(kcal: 200))
        var edited = previous
        edited.quantity = 1
        edited.unit = "kg"
        let result = try diaryCorrectedItem(edited, previous: previous, explicitNutrients: [])
        #expect(result.nutrition.kcal == 2_000)
    }

    private func food(quantity: Double = 2, unit: String = "pieces") -> FoodItem {
        FoodItem(name: "Bread", quantity: quantity, unit: unit, nutrition: NutritionValues(kcal: 160, protein: 20), provenance: .estimate, reference: "Synthetic", uncertain: true)
    }
    @Test func quantityOnlyScalesEachKnownNutrient() throws {
        let previous = food(); var edited = previous; edited.quantity = 4
        let result = try diaryCorrectedItem(edited, previous: previous, explicitNutrients: [])
        #expect(result.nutrition.kcal == 320 && result.nutrition.protein == 40 && result.nutrition.carbs == nil)
        #expect(result.provenance == previous.provenance)
        #expect(result.nutrientSources == previous.nutrientSources && result.reference == previous.reference && result.uncertain)
    }
    @Test func equalExplicitTotalOverridesScaling() throws {
        let previous = food(); var edited = previous; edited.quantity = 4
        let result = try diaryCorrectedItem(edited, previous: previous, explicitNutrients: ["kcal"])
        #expect(result.nutrition.kcal == 160 && result.nutrition.protein == 40)
        #expect(result.nutrientSources["kcal"] == .user && result.nutrientSources["protein"] == .estimate)
    }
    @Test func explicitNullClearsWhileOtherNutrientsScale() throws {
        let previous = food(); var edited = previous; edited.quantity = 4; edited.nutrition.kcal = nil
        let result = try diaryCorrectedItem(edited, previous: previous, explicitNutrients: ["kcal"])
        #expect(result.nutrition.kcal == nil && result.nutrition.protein == 40)
    }
    @Test func compatibleAliasesUsePhysicalQuantityWithoutRewritingLabels() throws {
        let fixtures: [(String, Double, String, Double, Double)] = [
            ("ml", 250, "l", 1, 500), (" GrAmS ", 100, " KILOGRAMS ", 1, 1250),
            ("kg", 1, "g", 100, 12.5), ("mg", 1000, "gram", 2, 250),
            ("millilitres", 250, "LITERS", 1, 500), ("large bowl", 2, "large bowl", 4, 250)
        ]
        for (unit, quantity, nextUnit, nextQuantity, expected) in fixtures {
            var previous = food(quantity: quantity, unit: unit); previous.nutrition = NutritionValues(kcal: 125)
            var edited = previous; edited.unit = nextUnit; edited.quantity = nextQuantity
            let result = try diaryCorrectedItem(edited, previous: previous, explicitNutrients: [])
            #expect(result.nutrition.kcal == expected && result.unit == nextUnit)
        }
    }
    @Test func unrelatedUnitRequiresEveryKnownNutrient() throws {
        let previous = food(unit: "serving"); var edited = previous; edited.unit = "g"; edited.quantity = 150; edited.nutrition.kcal = 240
        #expect(throws: DiaryError.invalidAmountUnitChange) { try diaryCorrectedItem(edited, previous: previous, explicitNutrients: ["kcal"]) }
        edited.nutrition.protein = nil
        let result = try diaryCorrectedItem(edited, previous: previous, explicitNutrients: ["kcal", "protein"])
        #expect(result.nutrition.kcal == 240 && result.nutrition.protein == nil && result.nutritionBasis?.kcal == 1.6)
        var mass = food(unit: "g"); mass.nutritionBasis = NutritionValues(kcal: 80, protein: 10)
        var volume = mass; volume.unit = "ml"
        #expect(throws: DiaryError.invalidAmountUnitChange) { try diaryCorrectedItem(volume, previous: mass, explicitNutrients: []) }
    }
    @Test func rejectsUnsupportedKeysAndUnmarkedChangedValues() throws {
        let previous = food(); var edited = previous; edited.nutrition.kcal = 200
        #expect(throws: DiaryError.invalidData) { try diaryCorrectedItem(edited, previous: previous, explicitNutrients: []) }
        #expect(throws: DiaryError.invalidData) { try diaryCorrectedItem(previous, previous: previous, explicitNutrients: ["sodium"]) }
    }
    @Test func zeroRetainsAndConvertsCompatibleBasis() throws {
        var previous = food(quantity: 100, unit: "g"); previous.nutrition = NutritionValues(kcal: 200)
        var edited = previous; edited.quantity = 0
        let zero = try diaryCorrectedItem(edited, previous: previous, explicitNutrients: [])
        edited = zero; edited.unit = "kg"
        let kilograms = try diaryCorrectedItem(edited, previous: zero, explicitNutrients: [])
        #expect(kilograms.nutritionBasis?.kcal == 2_000)
        edited = kilograms; edited.quantity = 0.1
        let result = try diaryCorrectedItem(edited, previous: kilograms, explicitNutrients: [])
        #expect(result.nutrition.kcal == 200)
    }
    @Test func explicitZeroTotalClearsOnlyItsBasisAndRequiresReplacement() throws {
        let previous = food(); var edited = previous; edited.quantity = 0; edited.nutrition.kcal = 0
        let zero = try diaryCorrectedItem(edited, previous: previous, explicitNutrients: ["kcal"])
        #expect(zero.nutritionBasis?.kcal == nil && zero.nutritionBasis?.protein == 10)
        edited = zero; edited.quantity = 2
        #expect(throws: DiaryError.invalidAmountUnitChange) { try diaryCorrectedItem(edited, previous: zero, explicitNutrients: []) }
        edited.nutrition.kcal = 100
        let result = try diaryCorrectedItem(edited, previous: zero, explicitNutrients: ["kcal"])
        #expect(result.nutrition.kcal == 100 && result.nutrition.protein == 20)
    }
    @Test func incompatibleZeroChangeDiscardsOldUnitBasis() throws {
        var previous = food(quantity: 0, unit: "g"); previous.nutrition = NutritionValues(kcal: 0); previous.nutritionBasis = NutritionValues(kcal: 2)
        var edited = previous; edited.unit = "serving"
        #expect(throws: DiaryError.invalidAmountUnitChange) { try diaryCorrectedItem(edited, previous: previous, explicitNutrients: []) }
        let result = try diaryCorrectedItem(edited, previous: previous, explicitNutrients: ["kcal"])
        #expect(result.nutritionBasis?.kcal == nil)
    }
    @Test func positiveQuantityUsesCurrentTotalsOverStaleBasis() throws {
        var previous = food(); previous.nutritionBasis = NutritionValues(kcal: 999, protein: 999)
        var edited = previous; edited.quantity = 4
        let result = try diaryCorrectedItem(edited, previous: previous, explicitNutrients: [])
        #expect(result.nutrition.kcal == 320 && result.nutrition.protein == 40)
    }
}
