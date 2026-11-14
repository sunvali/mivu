import Foundation
import Testing
@testable import Mivu

struct CoachPaneTests {
    private let today = UUID(), otherDay = UUID()

    private func meal(_ key: String, day: UUID, date: String? = nil) -> CoachCommittedReceipt {
        CoachCommittedReceipt(operationKey: key, turnID: UUID(), dayID: day, mealID: UUID(), committedRevision: 1, targetLocalDate: date)
    }
    private func weight(_ key: String) -> CoachCommittedReceipt {
        CoachCommittedReceipt(operationKey: key, turnID: UUID(), weightID: UUID(), committedRevision: 1)
    }
    private func landing(seen: Set<String>? = [], _ receipts: [CoachCommittedReceipt], modalOpen: Bool = false) -> CoachPaneLanding {
        CoachPane.landing(seen: seen, receipts: receipts, activeDayID: today, today: "2026-11-14", modalOpen: modalOpen)
    }
    private func turn(_ receipts: [CoachCommittedReceipt]) -> CoachExchangeSummary {
        CoachExchangeSummary(id: UUID(), sequence: 1, capturedAt: Date(timeIntervalSince1970: 0), captureTimeZoneID: "UTC", segmentID: UUID(),
            displayLocalDate: "2026-11-14", displayTimeZoneID: "UTC", text: "Synthetic", state: .completed, photos: [], receipts: receipts)
    }

    @Test func firstObservationNeverJumps() {
        #expect(!landing(seen: nil, [meal("food/a", day: today)]).jumps)
    }

    @Test func seenReceiptsNeverJump() {
        #expect(!landing(seen: ["food/a"], [meal("food/a", day: today)]).jumps)
    }

    @Test func openSheetSkipsTheJump() {
        #expect(!landing([meal("food/a", day: today)], modalOpen: true).jumps)
    }

    @Test func mealOnActiveDayLandsOnToday() {
        #expect(landing([meal("food/a", day: today, date: "2026-11-14")]) == CoachPaneLanding(pane: nil, jumps: true))
    }

    /// The first meal of a day starts that day, so the diary has no active day yet when the receipt arrives.
    @Test func firstMealOfTheDayLandsOnTodayBeforeTheDiaryCatchesUp() {
        let receipt = meal("food/a", day: otherDay, date: "2026-11-14")
        let landing = CoachPane.landing(seen: [], receipts: [receipt], activeDayID: nil, today: "2026-11-14", modalOpen: false)
        #expect(landing == CoachPaneLanding(pane: nil, jumps: true))
    }

    @Test func mealOnAnotherDayLandsOnThatDay() {
        #expect(landing([meal("food/a", day: otherDay, date: "2026-11-10")]) == CoachPaneLanding(pane: .day("2026-11-10"), jumps: true))
    }

    @Test func workoutOnAnotherDayLandsOnThatDay() {
        let workout = CoachCommittedReceipt(operationKey: "workout/a", turnID: UUID(), dayID: otherDay, workoutID: UUID(), committedRevision: 1, targetLocalDate: "2026-11-10")
        #expect(landing([workout]) == CoachPaneLanding(pane: .day("2026-11-10"), jumps: true))
    }

    @Test func weightLandsOnProgress() {
        #expect(landing([weight("weight/2026-11-14")]) == CoachPaneLanding(pane: .progress, jumps: true))
    }

    @Test func deletedWeightDoesNotJump() {
        #expect(!landing([weight("turn/delete_weight/id")]).jumps)
    }

    @Test func goalChangeDoesNotJump() {
        let goal = CoachCommittedReceipt(operationKey: "goal/a", turnID: UUID(), goalID: UUID(), committedRevision: 1)
        #expect(!landing([goal]).jumps)
    }

    @Test func lastNewReceiptWins() {
        #expect(landing([meal("food/a", day: today), weight("weight/2026-11-14")]).pane == .progress)
    }

    @Test func changeToTheOpenRecordKeepsItOpen() {
        let receipt = meal("correct/a", day: today)
        let open = CoachPane.landing(seen: [], receipts: [receipt], activeDayID: today, today: "2026-11-14", modalOpen: false, showing: .meal(receipt.mealID!))
        #expect(!open.jumps)
        let other = CoachPane.landing(seen: [], receipts: [receipt], activeDayID: today, today: "2026-11-14", modalOpen: false, showing: .meal(UUID()))
        #expect(other == CoachPaneLanding(pane: nil, jumps: true))
    }

    @Test func consultedProgressOffersSeeProgress() {
        #expect(CoachReplyLines.followUps(for: turn([]), consulted: [.progress], today: "2026-11-14") == [.progress])
    }

    @Test func consultedOtherDayOffersThatDay() {
        #expect(CoachReplyLines.followUps(for: turn([]), consulted: [.day("2026-11-10")], today: "2026-11-14") == [.day("2026-11-10")])
    }

    @Test func consultedTodayOffersToday() {
        #expect(CoachReplyLines.followUps(for: turn([]), consulted: [.day("2026-11-14")], today: "2026-11-14") == [.today])
    }

    @Test func followUpsHaveNoDuplicates() {
        #expect(CoachReplyLines.followUps(for: turn([weight("weight/2026-11-14")]), consulted: [.progress], today: "2026-11-14") == [.progress])
    }

    @Test func followUpsNameTheirPane() {
        #expect(CoachReplyLines.FollowUp.today.pane == nil)
        #expect(CoachReplyLines.FollowUp.progress.pane == .progress)
        #expect(CoachReplyLines.FollowUp.day("2026-11-10").pane == .day("2026-11-10"))
    }
}
