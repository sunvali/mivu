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

    /// Coach deleting the meal that is open would leave "Meal unavailable" in the pane.
    @Test func removalOfTheOpenRecordReturnsToToday() {
        let id = UUID()
        let removal = CoachCommittedReceipt(operationKey: "turn/delete_meal/\(id)", turnID: UUID(), dayID: today, mealID: id, committedRevision: 2)
        let landing = CoachPane.landing(seen: [], receipts: [removal], activeDayID: today, today: "2026-11-14", modalOpen: false, showing: .meal(id))
        #expect(landing == CoachPaneLanding(pane: nil, jumps: true))
    }

    private func observe(_ memory: inout CoachPaneMemory, _ owner: CoachTimelineIdentity, _ receipts: [CoachCommittedReceipt], modalOpen: Bool = false) -> CoachPaneLanding {
        memory.observe(owner: owner, receipts: receipts, activeDayID: today, today: "2026-11-14", modalOpen: modalOpen, showing: nil)
    }

    /// Another profile's latest turn is not a change Coach just made.
    @Test func switchingProfileNeverJumps() {
        let first = CoachTimelineIdentity(profileID: UUID(), timelineGeneration: UUID())
        let second = CoachTimelineIdentity(profileID: UUID(), timelineGeneration: UUID())
        var memory = CoachPaneMemory()
        #expect(!observe(&memory, first, [weight("a/weight/1")]).jumps)
        #expect(!observe(&memory, second, [weight("b/weight/1")]).jumps)
        #expect(observe(&memory, second, [weight("b/weight/1"), weight("b/weight/2")]).pane == .progress)
    }

    /// Skipped, not queued: the change that arrived under an open sheet never moves the pane afterwards.
    @Test func skippedChangeNeverJumpsLater() {
        let owner = CoachTimelineIdentity(profileID: UUID(), timelineGeneration: UUID())
        var memory = CoachPaneMemory()
        _ = observe(&memory, owner, [])
        #expect(!observe(&memory, owner, [weight("a/weight/1")], modalOpen: true).jumps)
        #expect(!observe(&memory, owner, [weight("a/weight/1")]).jumps)
    }

    // Quick prompts cover today and progress, so only a past day gets a follow-up.
    @Test func consultedProgressOrTodayOffersNothing() {
        #expect(CoachReplyLines.followUps(for: turn([weight("weight/2026-11-14")]), consulted: [.progress, .day("2026-11-14")], today: "2026-11-14") == [])
    }

    @Test func consultedOtherDayOffersThatDay() {
        #expect(CoachReplyLines.followUps(for: turn([]), consulted: [.day("2026-11-10")], today: "2026-11-14") == [.day("2026-11-10")])
    }

    @Test func followUpsHaveNoDuplicates() {
        #expect(CoachReplyLines.followUps(for: turn([]), consulted: [.day("2026-11-10"), .day("2026-11-10")], today: "2026-11-14") == [.day("2026-11-10")])
    }

    @Test func followUpsNameTheirPane() {
        #expect(CoachReplyLines.FollowUp.day("2026-11-10").pane == .day("2026-11-10"))
    }
}
