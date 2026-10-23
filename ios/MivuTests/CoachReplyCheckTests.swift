import Foundation
import Testing
@testable import Mivu

@Suite struct CoachReplyCheckTests {
    private func meal(_ state: SubmissionState = .saved) -> CoachCommittedReceipt {
        CoachCommittedReceipt(operationKey: "meal", turnID: UUID(), mealID: UUID(), committedRevision: 1, targetLocalDate: "2026-10-23",
            items: [CoachCommittedItem(itemID: UUID(), name: "Synthetic chicken", quantity: 180, unit: "g", nutrition: NutritionValues(kcal: 320, carbs: 0, protein: 50, fat: 12)),
                    CoachCommittedItem(itemID: UUID(), name: "Synthetic rice", quantity: 1, unit: "cup", nutrition: NutritionValues(kcal: 240, carbs: 52, protein: 4, fat: 1))],
            submissionState: state)
    }

    @Test func groundedProsePassesWithGroupingAndRounding() {
        let allowed = CoachReplyCheck.allowedNumbers(in: ["{\"kcal\":1240,\"remaining\":458}"], receipts: [])
        #expect(CoachReplyCheck.passes("About **1,240** kcal, roughly 460 left.", allowed: allowed, receipts: []))
    }

    @Test func inventedNumberFails() {
        let allowed = CoachReplyCheck.allowedNumbers(in: ["{\"kcal\":420}"], receipts: [])
        #expect(!CoachReplyCheck.passes("You have 9999 kcal left.", allowed: allowed, receipts: []))
    }

    @Test func percentAndRangeNeedEveryNumberGrounded() {
        let allowed = CoachReplyCheck.allowedNumbers(in: ["{\"a\":450,\"b\":460}"], receipts: [])
        #expect(CoachReplyCheck.passes("Between 450–460 kcal.", allowed: allowed, receipts: []))
        #expect(!CoachReplyCheck.passes("About 30% of target.", allowed: allowed, receipts: []))
    }

    @Test func receiptSumsAndWeightAreAllowed() {
        var weight = CoachCommittedReceipt(operationKey: "weight", turnID: UUID(), weightID: UUID(), committedRevision: 1)
        weight.weightValue = 73.6; weight.weightUnit = "kg"
        let receipts = [meal(), weight]
        let allowed = CoachReplyCheck.allowedNumbers(in: [], receipts: receipts)
        #expect(CoachReplyCheck.passes("Dinner is about **560** kcal with 54 g protein, and 73.6 kg is saved.", allowed: allowed, receipts: receipts))
        #expect(!CoachReplyCheck.passes("Dinner is about 700 kcal.", allowed: allowed, receipts: receipts))
    }

    @Test func awaitingReviewForbidsLoggedOrSaved() {
        let receipts = [meal(.awaitingReview)]
        let allowed = CoachReplyCheck.allowedNumbers(in: [], receipts: receipts)
        #expect(!CoachReplyCheck.passes("Your lunch is saved.", allowed: allowed, receipts: receipts))
        #expect(CoachReplyCheck.passes("Your estimate is ready for review.", allowed: allowed, receipts: receipts))
    }

    @Test func datesAndTimesUseTheirParts() {
        let allowed = CoachReplyCheck.allowedNumbers(in: ["{\"date\":\"2026-10-23\",\"time\":\"20:12\"}"], receipts: [])
        #expect(CoachReplyCheck.passes("Logged for 2026-10-23 at 20:12.", allowed: allowed, receipts: []))
        #expect(!CoachReplyCheck.passes("Logged for 2026-11-02.", allowed: allowed, receipts: []))
    }

    @Test func emptyProseFails() {
        #expect(!CoachReplyCheck.passes("  \n", allowed: [], receipts: []))
    }

    @Test func identifierDigitsDoNotGroundNumbers() {
        let source = #"{"meals":[{"id":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F","kcal":620},{"id":"45000000-0000-0000-0000-000000000450"}]}"#
        let allowed = CoachReplyCheck.allowedNumbers(in: [source], receipts: [])
        #expect(!CoachReplyCheck.passes("About 450 kcal left.", allowed: allowed, receipts: []))
        #expect(CoachReplyCheck.passes("About 620 kcal so far.", allowed: allowed, receipts: []))
    }
}
