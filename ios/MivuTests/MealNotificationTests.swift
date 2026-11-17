import Foundation
import Testing
import UIKit
@testable import Mivu

@Suite struct MealNotificationTests {
    private func meal(_ items: [FoodItem], state: SubmissionState = .saved, proposal: [FoodItem]? = nil) -> MealReadModel {
        let id = UUID()
        let output = proposal.map { AnalysisOutput(profileID: UUID(), mealID: id, submissionID: UUID(), baseRevision: 0, items: $0) }
        return MealReadModel(id: id, dayID: UUID(), capturedAt: Date(), eatenAt: Date(), revision: items.isEmpty ? 0 : 1, items: items,
                             submissions: [MealSubmission(baseRevision: 0, text: "", photoIDs: [], reviewFirst: false, state: state, proposal: output)], photos: [])
    }
    private func food(_ name: String, kcal: Double?) -> FoodItem { FoodItem(name: name, nutrition: NutritionValues(kcal: kcal)) }

    @Test func recognisedFoodNamesTheMealAndItsCalories() {
        let text = MealNotification.text(for: meal([food("Apple", kcal: 94.6)]))
        #expect(text?.title == "Apple logged")
        #expect(text?.body == "95 kcal\nProtein — · Carbs — · Fat —")
    }

    @Test func severalFoodsAreShortenedAndUnknownCaloriesSaySo() {
        let text = MealNotification.text(for: meal([food("Rice", kcal: nil), food("Chicken", kcal: 200), food("Salad", kcal: 40)]))
        #expect(text?.title == "Rice, Chicken and 1 more logged")
        #expect(text?.body == "At least 240 kcal\nProtein — · Carbs — · Fat —")
    }

    @Test func estimateAwaitingReviewAsksForReview() {
        // The app keeps an estimate awaiting review in the submission's proposal, not in the meal's saved items.
        let text = MealNotification.text(for: meal([], state: .awaitingReview, proposal: [food("Pasta", kcal: 610)]))
        #expect(text?.title == "Pasta is ready to review")
        #expect(text?.body == "About 610 kcal · Tap to review\nProtein — · Carbs — · Fat —")
    }

    @Test func macrosAreRoundedAndPartialAmountsAreMarked() {
        let items = [FoodItem(name: "Chicken", nutrition: NutritionValues(kcal: 200, carbs: 0, protein: 24.6, fat: 12.2)),
                     FoodItem(name: "Rice", nutrition: NutritionValues(kcal: 100, carbs: 40.4, protein: nil, fat: 0))]
        let text = MealNotification.text(for: meal(items))
        #expect(text?.body == "300 kcal\nProtein ≥25g · Carbs 40g · Fat 12g")
    }

    @Test func reviewUsesProposalMacros() {
        let proposal = [FoodItem(name: "Pasta", nutrition: NutritionValues(kcal: 610, carbs: 80, protein: 25, fat: 20))]
        let text = MealNotification.text(for: meal([], state: .awaitingReview, proposal: proposal))
        #expect(text?.body == "About 610 kcal · Tap to review\nProtein 25g · Carbs 80g · Fat 20g")
    }

    @Test @MainActor func macroLineFitsSmallPhoneAndWrapsAtAccessibilitySizes() throws {
        let item = FoodItem(name: String(repeating: "Long meal name ", count: 20),
                            nutrition: NutritionValues(kcal: 610, carbs: 80, protein: 25, fat: 20))
        let text = try #require(MealNotification.text(for: meal([item])))
        let line = try #require(text.body.split(separator: "\n").last).description
        // 280 points conservatively allows notification margins on a 375-point phone.
        for size in [UIContentSizeCategory.large, .accessibilityExtraExtraExtraLarge] {
            let font = UIFont.preferredFont(forTextStyle: .subheadline, compatibleWith: UITraitCollection(preferredContentSizeCategory: size))
            let bounds = (line as NSString).boundingRect(with: CGSize(width: 280, height: CGFloat.greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font], context: nil)
            #expect(bounds.width <= 280)
            #expect(bounds.height <= font.lineHeight * (size == .large ? 1 : 3))
        }
    }

    @Test func unknownCaloriesStillShowKnownMacros() {
        let item = FoodItem(name: "Synthetic meal", nutrition: NutritionValues(protein: 25))
        #expect(MealNotification.text(for: meal([item]))?.body == "Calories not known yet\nProtein 25g · Carbs — · Fat —")
        #expect(MealNotification.text(for: meal([], state: .awaitingReview, proposal: [item]))?.body == "Tap to review\nProtein 25g · Carbs — · Fat —")
    }

    @Test func noFoodFoundAsksForANote() {
        let text = MealNotification.text(for: meal([], state: .captured))
        #expect(text?.title == "Couldn't recognize your meal")
        #expect(text?.body == "Tap to add a note so Mivu can log it.")
    }

    @Test(arguments: [SubmissionState.needsRetry, .waitingForConnection, .cancelled])
    func retryableOrStoppedMealsStayQuiet(state: SubmissionState) {
        #expect(MealNotification.text(for: meal([], state: state)) == nil)
    }

    @Test func oneNotificationPerMeal() {
        let id = UUID()
        #expect(MealNotification.identifier(for: id) == MealNotification.identifier(for: id))
        #expect(MealNotification.mealID(from: [MealNotification.mealKey: id.uuidString]) == id)
        #expect(MealNotification.mealID(from: [:]) == nil)
    }
}
