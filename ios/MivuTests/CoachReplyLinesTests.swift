import Foundation
import Testing
@testable import Mivu

@Suite struct CoachReplyLinesTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func store(goal: Double? = 1600, protein: Double? = nil, food: Double? = 1142) async throws -> (DiaryStore, DiaryProfile, URL) {
        let root = URL.temporaryDirectory.appending(path: "CoachReplyLines-" + UUID().uuidString)
        let clock = now
        let store = DiaryStore(directory: root, currentTime: { clock }); let profile = DiaryProfile(name: "Synthetic")
        _ = try await store.createProfile(profile); _ = try await store.startDay(at: now)
        if let goal {
            _ = try await store.setGoals(GoalRecord(effectiveLocalDate: "2027-01-15", timeZoneID: profile.timeZoneID, targets: NutritionValues(kcal: goal, protein: protein), exerciseCreditEnabled: false), expectedRevision: nil, expectedProfileID: profile.id)
        }
        if let food {
            let turn = try await capturedTurn(store, text: "Synthetic meal", photos: [], at: now, expectedProfileID: profile.id)
            _ = try await store.applyCoachFood(turnID: turn.id, targetLocalDate: "2027-01-15", items: [FoodItem(name: "Synthetic meal", nutrition: NutritionValues(kcal: food), provenance: .estimate)], expectedProfileID: profile.id)
        }
        return (store, profile, root)
    }

    @Test func singleDayStatesIntakeTargetAndRoundedRemaining() async throws {
        let (store, profile, root) = try await store(); defer { try? FileManager.default.removeItem(at: root) }
        let progress = try await store.coachProgress(endingOn: "2027-01-15", days: 1, expectedProfileID: profile.id)
        #expect(CoachReplyLines.factLine(progress: [progress], goals: [], workouts: [], preferencesRead: false, today: "2027-01-15")
            == "Today: 1,142 of 1,600 kcal, about 460 left.")
    }

    @Test func pastDayUsesItsDate() async throws {
        let (store, profile, root) = try await store(); defer { try? FileManager.default.removeItem(at: root) }
        let progress = try await store.coachProgress(endingOn: "2027-01-15", days: 1, expectedProfileID: profile.id)
        #expect(CoachReplyLines.factLine(progress: [progress], goals: [], workouts: [], preferencesRead: false, today: "2027-01-16")
            == "2027-01-15: 1,142 of 1,600 kcal, about 460 left.")
    }

    @Test func emptyDaySaysNothingRecorded() async throws {
        let (store, profile, root) = try await store(food: nil); defer { try? FileManager.default.removeItem(at: root) }
        let progress = try await store.coachProgress(endingOn: "2027-01-15", days: 1, expectedProfileID: profile.id)
        #expect(CoachReplyLines.factLine(progress: [progress], goals: [], workouts: [], preferencesRead: false, today: "2027-01-15")
            == "There's no food recorded for 2027-01-15 yet.")
    }

    @Test func goalLineIncludesProteinWhenSet() {
        let goal = GoalRecord(effectiveLocalDate: "2027-01-15", timeZoneID: "UTC", targets: NutritionValues(kcal: 1600, protein: 120), exerciseCreditEnabled: false)
        #expect(CoachReplyLines.factLine(progress: [], goals: [goal], workouts: [], preferencesRead: false, today: "2027-01-15") == "Goal: 1,600 kcal a day, 120 g protein.")
    }

    @Test func preferencesAndNothingRead() {
        #expect(CoachReplyLines.factLine(progress: [], goals: [], workouts: [], preferencesRead: true, today: "2027-01-15") == "Your preferences are up to date.")
        #expect(CoachReplyLines.factLine(progress: [], goals: [], workouts: [], preferencesRead: false, today: "2027-01-15") == "I couldn't find anything to add there.")
    }

    @Test func atMostTwoSentences() async throws {
        let (store, profile, root) = try await store(); defer { try? FileManager.default.removeItem(at: root) }
        let progress = try await store.coachProgress(endingOn: "2027-01-15", days: 1, expectedProfileID: profile.id)
        let goal = GoalRecord(effectiveLocalDate: "2027-01-15", timeZoneID: "UTC", targets: NutritionValues(kcal: 1600), exerciseCreditEnabled: false)
        let line = CoachReplyLines.factLine(progress: [progress], goals: [goal], workouts: [], preferencesRead: true, today: "2027-01-15")
        #expect(line == "Today: 1,142 of 1,600 kcal, about 460 left. Goal: 1,600 kcal a day.")
    }

    @Test func plainStripsInlineMarkdownAndSurvivesUnbalancedMarkers() {
        #expect(CoachReplyLines.plain("About **1,240** kcal") == "About 1,240 kcal")
        #expect(CoachReplyLines.plain("**x") == "**x")
        #expect(String(CoachReplyLines.attributed("About **1,240** kcal").characters) == "About 1,240 kcal")
    }

    @Test func followUpsFollowTheCompletedTurnsReceipts() {
        func turn(_ receipts: [CoachCommittedReceipt], state: CoachTurnState = .completed) -> CoachExchangeSummary {
            CoachExchangeSummary(id: UUID(), sequence: 1, capturedAt: now, captureTimeZoneID: "UTC", segmentID: UUID(), displayLocalDate: "2027-01-15",
                displayTimeZoneID: "UTC", text: "Synthetic", state: state, photos: [], receipts: receipts)
        }
        let meal = CoachCommittedReceipt(operationKey: "m", turnID: UUID(), mealID: UUID(), committedRevision: 1, submissionState: .saved)
        let weight = CoachCommittedReceipt(operationKey: "w", turnID: UUID(), weightID: UUID(), committedRevision: 1)
        #expect(CoachReplyLines.followUps(for: turn([meal])) == [.today])
        #expect(CoachReplyLines.followUps(for: turn([weight])) == [.progress])
        #expect(CoachReplyLines.followUps(for: turn([meal, weight])) == [.today, .progress])
        #expect(CoachReplyLines.followUps(for: turn([meal], state: .analyzing)) == [])
        #expect(CoachReplyLines.followUps(for: turn([])) == [])
    }
}
