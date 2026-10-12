import Foundation

/// A deterministic fixture, never food recognition or a dietary claim.
struct SampleAnalyzer: Sendable {
    func analyze(_ input: AnalysisInput) throws -> AnalysisOutput {
        guard input.schemaVersion == 1, input.baseRevision >= 0, input.text.count <= 20_000,
              ["en", "he"].contains(input.language), input.preferences.count <= 10_000 else { throw DiaryError.invalidData }
        try validateItems(input.currentItems)
        var items = input.currentItems
        if items.isEmpty {
            let nutrition = NutritionValues(kcal: 95, carbs: 25, protein: 0.5, fat: 0.3)
            items = [FoodItem(name: "Apple (sample)", nutrition: nutrition,
                nutrientSources: ["kcal": .sample, "carbs": .sample, "protein": .sample, "fat": .sample], nutritionBasis: nutrition)]
        } else {
            let text = input.text.lowercased()
            if text.contains("half") || text.contains("חצי") {
                items = items.map { scale($0, by: 0.5) }
            } else if let number = text.split(whereSeparator: { !$0.isNumber && $0 != "." }).compactMap({ Double($0) }).first {
                guard number.isFinite, number >= 0, number <= 100_000 else { throw DiaryError.invalidData }
                if let basis = items[0].nutritionBasis {
                    items[0].quantity = number
                    items[0].nutrition = basis.scaled(by: number)
                } else {
                    guard items[0].quantity > 0 else { throw DiaryError.invalidData }
                    items[0] = scale(items[0], by: number / items[0].quantity)
                }
            }
        }
        try validateItems(items)
        return AnalysisOutput(profileID: input.profileID, mealID: input.mealID, submissionID: input.submissionID,
                              baseRevision: input.baseRevision, items: items)
    }

    private func scale(_ item: FoodItem, by factor: Double) -> FoodItem {
        var result = item
        result.quantity *= factor
        result.nutrition = item.nutrition.scaled(by: factor)
        return result
    }
}
