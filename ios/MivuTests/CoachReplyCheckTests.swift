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

    @Test func hedgedGeneralFoodFactPassesOnlyWhenAllowed() {
        let allowed = CoachReplyCheck.allowedNumbers(in: ["{\"kcal\":500}"], receipts: [])
        let prose = "Plain Greek yogurt has about 10 g protein per 100 g."
        #expect(CoachReplyCheck.passes(prose, allowed: allowed, receipts: [], generalFacts: true))
        #expect(!CoachReplyCheck.passes(prose, allowed: allowed, receipts: []))
    }

    @Test func generalFactsNeedAHedgeAndCannotDescribeTheDiary() {
        let allowed = CoachReplyCheck.allowedNumbers(in: ["{\"kcal\":500}"], receipts: [])
        #expect(!CoachReplyCheck.passes("Greek yogurt has 10 g protein per 100 g.", allowed: allowed, receipts: [], generalFacts: true))
        #expect(!CoachReplyCheck.passes("You have about 600 kcal left.", allowed: allowed, receipts: [], generalFacts: true))
        #expect(!CoachReplyCheck.passes("You’re at about 900 kcal.", allowed: allowed, receipts: [], generalFacts: true))
        #expect(CoachReplyCheck.passes("You're at **500** kcal today. A pot of Greek yogurt adds about 17 g protein.", allowed: allowed, receipts: [], generalFacts: true))
        // The comparison shape the rules teach passes; the same numbers in one sentence do not.
        #expect(CoachReplyCheck.passes("The salad is about 300 kcal. That fits the 500 left today.", allowed: allowed, receipts: [], generalFacts: true))
        #expect(!CoachReplyCheck.passes("The salad, about 300 kcal, fits the 500 you have left.", allowed: allowed, receipts: [], generalFacts: true))
    }

    @Test func savedTurnsStayStrictEvenWithGeneralFacts() {
        let receipts = [meal()]
        let allowed = CoachReplyCheck.allowedNumbers(in: [], receipts: receipts)
        #expect(!CoachReplyCheck.passes("Dinner is about 700 kcal.", allowed: allowed, receipts: receipts, generalFacts: true))
    }

    @Test func reviewOnlyTurnsMayUseGeneralFactsButNeverClaimALog() {
        let receipts = [meal(.awaitingReview)]
        let allowed = CoachReplyCheck.allowedNumbers(in: [], receipts: receipts)
        #expect(CoachReplyCheck.passes("A slice is typically about 280 kcal, fine as a treat.", allowed: allowed, receipts: receipts, generalFacts: true))
        #expect(!CoachReplyCheck.passes("I logged it, a slice is about 280 kcal.", allowed: allowed, receipts: receipts, generalFacts: true))
    }

    @Test func identifierDigitsDoNotGroundNumbers() {
        let source = #"{"meals":[{"id":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F","kcal":620},{"id":"45000000-0000-0000-0000-000000000450"}]}"#
        let allowed = CoachReplyCheck.allowedNumbers(in: [source], receipts: [])
        #expect(!CoachReplyCheck.passes("About 450 kcal left.", allowed: allowed, receipts: []))
        #expect(CoachReplyCheck.passes("About 620 kcal so far.", allowed: allowed, receipts: []))
    }

    @Test func commaDecimalReadsAsOneNumber() {
        #expect(CoachReplyCheck.numbers(in: "73,5 кг") == [Decimal(string: "73.5")!])
        #expect(CoachReplyCheck.numbers(in: "2,25") == [Decimal(string: "2.25")!])
        #expect(CoachReplyCheck.numbers(in: "1,240 kcal") == [1240])
        #expect(CoachReplyCheck.numbers(in: "1\u{202F}240 kcal") == [1240])
        #expect(CoachReplyCheck.numbers(in: "1\u{00A0}240,5") == [Decimal(string: "1240.5")!])
        #expect(CoachReplyCheck.numbers(in: "3, 4 and 5") == [3, 4, 5])
        #expect(CoachReplyCheck.numbers(in: "1 240 kcal") == [1240])
        #expect(CoachReplyCheck.numbers(in: "2 eggs, 300 g") == [2, 300])
    }

    @Test func hedgedGeneralFactPassesInAnyLanguage() {
        let receipts = [meal(.awaitingReview)]
        let allowed = CoachReplyCheck.allowedNumbers(in: [], receipts: receipts)
        #expect(CoachReplyCheck.passes("בתפוח יש ~95 קק״ל.", allowed: allowed, receipts: receipts, generalFacts: true))
        #expect(!CoachReplyCheck.passes("בתפוח יש 95 קק״ל.", allowed: allowed, receipts: receipts, generalFacts: true))
        #expect(!CoachReplyCheck.passes("בתפוח יש ~95 קק״ל.", allowed: allowed, receipts: [meal()], generalFacts: true))
        #expect(!CoachReplyCheck.passes("נשארו לך היום ~600 קק״ל.", allowed: allowed, receipts: receipts, generalFacts: true))
        // A language whose diary words aren't known grounds every number.
        #expect(!CoachReplyCheck.passes("Aujourd'hui une pomme contient environ ~95 kcal.", allowed: allowed, receipts: receipts, generalFacts: true))
    }

    @Test func hedgedGeneralFactPassesInSpanishAndRussian() {
        let receipts = [meal(.awaitingReview)]
        let allowed = CoachReplyCheck.allowedNumbers(in: [], receipts: receipts)
        #expect(CoachReplyCheck.passes("Una manzana mediana tiene aproximadamente 95 kcal.", allowed: allowed, receipts: receipts, generalFacts: true))
        #expect(!CoachReplyCheck.passes("Hoy llevas ~1800 kcal y te quedan ~200.", allowed: allowed, receipts: receipts, generalFacts: true))
        #expect(CoachReplyCheck.passes("В яблоке примерно 95 ккал.", allowed: allowed, receipts: receipts, generalFacts: true))
        #expect(!CoachReplyCheck.passes("Сегодня у тебя осталось ~600 ккал.", allowed: allowed, receipts: receipts, generalFacts: true))
        // The model may answer in Spain's perfect tense or in formal вы.
        #expect(!CoachReplyCheck.passes("Has comido aproximadamente 1800 kcal.", allowed: allowed, receipts: receipts, generalFacts: true))
        #expect(!CoachReplyCheck.passes("Вы набрали около 2000 ккал.", allowed: allowed, receipts: receipts, generalFacts: true))
    }

    @Test func readsDigitsInAnyScript() {
        #expect(CoachReplyCheck.numbers(in: "٧٤٠ kcal") == [740])
        #expect(CoachReplyCheck.numbers(in: "७४० kcal") == [740])
        #expect(CoachReplyCheck.numbers(in: "٧٣٫٦ كغ") == [Decimal(string: "73.6")!])
    }

    @Test func ungroundedForeignDigitsFail() {
        #expect(!CoachReplyCheck.passes("٧٤٠ kcal", allowed: [], receipts: [], claimsSave: false))
        #expect(CoachReplyCheck.passes("٧٤٠ kcal", allowed: [740], receipts: [], claimsSave: false))
    }

    @Test func markerIsStrippedAndReported() {
        let split = CoachReplyCheck.splitSaveClaim("נשמר.\n<saved/>\n")
        #expect(split.text == "נשמר.")
        #expect(split.claimsSave)
        #expect(!CoachReplyCheck.splitSaveClaim("Looks good.").claimsSave)
        #expect(CoachReplyCheck.splitSaveClaim("Looks good.").text == "Looks good.")
    }

    @Test func markerOnAnAwaitingReviewMealFails() {
        let receipts = [meal(.awaitingReview)]
        let allowed = CoachReplyCheck.allowedNumbers(in: [], receipts: receipts)
        #expect(!CoachReplyCheck.passes("הארוחה מחכה.", allowed: allowed, receipts: receipts, claimsSave: true))
        #expect(CoachReplyCheck.passes("הארוחה מחכה לבדיקה.", allowed: allowed, receipts: receipts, claimsSave: false))
    }

    @Test func markerSpellingsAreAllStripped() {
        for reply in ["Saved.\n<saved />", "Saved.\n<Saved/>", "Saved.\n`<saved/>`", "Saved. < saved >"] {
            let split = CoachReplyCheck.splitSaveClaim(reply)
            #expect(split.claimsSave, "\(reply)")
            #expect(split.text == "Saved.", "\(reply)")
        }
    }
}
