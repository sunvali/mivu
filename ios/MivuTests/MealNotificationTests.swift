import Foundation
import Testing
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
        #expect(text?.body == "95 kcal")
    }

    @Test func severalFoodsAreShortenedAndUnknownCaloriesSaySo() {
        let text = MealNotification.text(for: meal([food("Rice", kcal: nil), food("Chicken", kcal: 200), food("Salad", kcal: 40)]))
        #expect(text?.title == "Rice, Chicken and 1 more logged")
        #expect(text?.body == "Calories not known yet")
    }

    @Test func estimateAwaitingReviewAsksForReview() {
        // The app keeps an estimate awaiting review in the submission's proposal, not in the meal's saved items.
        let text = MealNotification.text(for: meal([], state: .awaitingReview, proposal: [food("Pasta", kcal: 610)]))
        #expect(text?.title == "Pasta is ready to review")
        #expect(text?.body == "About 610 kcal · Tap to review")
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
