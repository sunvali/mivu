import Foundation
import Testing
@testable import Mivu

@Suite struct TimeZoneTravelTests {
    static let draft = WorkoutDraft(kind: .cardio, durationMinutes: 30, exercises: [], estimatedBurnKcal: nil, burnSource: nil)
    func move(_ store: DiaryStore, _ profile: DiaryProfile, to zone: String) async throws {
        var changed = profile
        changed.timeZoneID = zone
        try await store.updateProfile(changed)
    }

    @Test func travelDayNeedsTwoOffsets() {
        let at = DayTests.date("2026-11-17T08:00:00Z")
        #expect(!isTravelDay(dayZone: "Asia/Jerusalem", mealZones: ["Asia/Jerusalem", nil], at: at))
        #expect(isTravelDay(dayZone: "Asia/Jerusalem", mealZones: ["America/New_York", nil], at: at))
        #expect(!isTravelDay(dayZone: "Europe/Paris", mealZones: ["Europe/Paris", "Europe/Berlin"], at: at))
    }
    @Test func historySummaryFlagsTheTravelDay() async throws {
        let (store, profile, day) = try await DayTests.ready(zone: "Asia/Jerusalem", at: "2026-11-17T08:00:00Z")
        // Only saved meals count, so each capture gets its synthetic analysis.
        func save(_ text: String, at: String) async throws {
            let meal = try await capturedMeal(store, text: text, photos: [], reviewFirst: false, dayID: day.id, at: DayTests.date(at))
            try await store.applyAnalysis(AnalysisOutput(profileID: profile.id, mealID: meal.id, submissionID: meal.submissions[0].id, baseRevision: 0, items: [Self.apple]), expectedProfileID: profile.id)
        }
        func flagged() async throws -> Bool? { try await store.diaryWeek(from: "2026-11-17", through: "2026-11-17", expectedProfileID: profile.id).days.first?.isTravelDay }
        try await save("Synthetic breakfast", at: "2026-11-17T08:00:00Z")
        #expect(try await flagged() == false)
        try await move(store, profile, to: "America/New_York")
        _ = try await capturedMeal(store, text: "Synthetic pending dinner", photos: [], reviewFirst: false, dayID: day.id, at: DayTests.date("2026-11-17T19:00:00Z"))
        #expect(try await flagged() == false)
        try await save("Synthetic dinner", at: "2026-11-17T20:00:00Z")
        #expect(try await flagged() == true)
    }
    @Test func telAvivToNewYorkKeepsTheDayUntilFourAMNewYork() async throws {
        let (store, profile, day) = try await DayTests.ready(zone: "Asia/Jerusalem", at: "2026-11-17T08:00:00Z")
        try await move(store, profile, to: "America/New_York")
        #expect(try await store.dayAssignment(at: DayTests.date("2026-11-17T20:00:00Z")) == .existing(day.id))
        #expect(try await store.dayAssignment(at: DayTests.date("2026-11-18T08:59:59Z")) == .existing(day.id))
        #expect(try await store.dayAssignment(at: DayTests.date("2026-11-18T09:00:00Z")) == .newDay)
        let next = try await store.startDay(at: DayTests.date("2026-11-18T09:00:00Z"))
        #expect(next.localDate == "2026-11-18" && next.timeZoneID == "America/New_York")
        #expect(try await store.snapshotForExport().days[0] == day)
    }
    @Test func telAvivToTokyoStartsTheTokyoDate() async throws {
        let (store, profile, _) = try await DayTests.ready(zone: "Asia/Jerusalem", at: "2026-11-17T16:00:00Z")
        try await move(store, profile, to: "Asia/Tokyo")
        #expect(try await store.dayAssignment(at: DayTests.date("2026-11-18T04:00:00Z")) == .newDay)
        #expect(try await store.startDay(at: DayTests.date("2026-11-18T04:00:00Z")).localDate == "2026-11-18")
    }
    @Test func tokyoToHonoluluNeverGoesBackADate() async throws {
        let (store, profile, day) = try await DayTests.ready(zone: "Asia/Tokyo", at: "2026-11-18T00:00:00Z")
        try await move(store, profile, to: "Pacific/Honolulu")
        #expect(try await store.dayAssignment(at: DayTests.date("2026-11-18T06:00:00Z")) == .existing(day.id))
        #expect(try await store.dayAssignment(at: DayTests.date("2026-11-19T13:59:59Z")) == .existing(day.id))
        #expect(try await store.dayAssignment(at: DayTests.date("2026-11-19T14:00:00Z")) == .newDay)
        #expect(try await store.startDay(at: DayTests.date("2026-11-18T06:00:00Z")).localDate == "2026-11-19")
    }
    @Test func travelDateWritesReuseTheExistingDay() async throws {
        let (store, profile, day) = try await DayTests.ready(zone: "Asia/Jerusalem", at: "2026-11-17T08:00:00Z")
        try await move(store, profile, to: "America/New_York")
        let weight = try await store.recordWeight(value: 70, at: DayTests.date("2026-11-17T20:00:00Z"), startNewDay: false)
        let workout = try await store.createWorkout(localDate: "2026-11-17", draft: Self.draft, performedAt: nil, expectedProfileID: profile.id)
        let snapshot = try await store.snapshotForExport()
        #expect(snapshot.days.map(\.id) == [day.id] && weight.dayID == day.id && workout.dayID == day.id)
    }
    @Test func newMealRecordsItsZoneAndOldPayloadsDecode() async throws {
        let (store, profile, day) = try await DayTests.ready(zone: "Asia/Jerusalem", at: "2026-11-17T08:00:00Z")
        try await move(store, profile, to: "America/New_York")
        let meal = try await capturedMeal(store, text: "apple", photos: [], reviewFirst: false, dayID: day.id, at: DayTests.date("2026-11-17T20:00:00Z"))
        #expect(meal.timeZoneID == "America/New_York")
        var old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(meal)) as! [String: Any]
        old["timeZoneID"] = nil
        #expect(try JSONDecoder().decode(DiaryMeal.self, from: JSONSerialization.data(withJSONObject: old)).timeZoneID == nil)
        var bare = meal; bare.timeZoneID = nil
        #expect(!String(decoding: try JSONEncoder().encode(bare), as: UTF8.self).contains("\"timeZoneID\""))
    }
    @Test func movingANewYorkDinnerWithinTheTravelDayIsValid() async throws {
        let (store, profile, day) = try await DayTests.ready(zone: "Asia/Jerusalem", at: "2026-11-17T08:00:00Z")
        try await move(store, profile, to: "America/New_York")
        let meal = try await capturedMeal(store, text: "dinner", photos: [], reviewFirst: false, dayID: day.id, at: DayTests.date("2026-11-17T20:00:00Z"))
        // 22:00 in New York is already Nov 18 in Tel Aviv, the day's own zone.
        let dinner = DayTests.date("2026-11-18T03:00:00Z")
        try await store.moveMeal(meal.id, to: day.id, eatenAt: dinner, expectedProfileID: profile.id)
        #expect(try await store.snapshotForExport().meals.first { $0.id == meal.id }?.eatenAt == dinner)
    }
    @Test func lateWeightOnTravelDayIsAccepted() async throws {
        // 21:30 New York is already Nov 18 in Tel Aviv.
        let (store, profile, day) = try await DayTests.ready(zone: "Asia/Jerusalem", at: "2026-11-17T08:00:00Z")
        try await move(store, profile, to: "America/New_York")
        let saved = try await store.setWeight(dayLocalDate: "2026-11-17", value: 70, unit: "kg", measuredAt: DayTests.date("2026-11-18T02:30:00Z"), expectedRevision: nil, expectedProfileID: profile.id)
        #expect(saved.dayID == day.id)
        for outside in ["2026-11-16T10:00:00Z", "2026-11-18T09:00:00Z"] { // before the day started; New York waking date already Nov 18
            await #expect(throws: DiaryError.invalidData) { _ = try await store.setWeight(dayLocalDate: "2026-11-17", value: 71, unit: "kg", measuredAt: DayTests.date(outside), expectedRevision: saved.revision, expectedProfileID: profile.id) }
        }
    }
    @Test func duplicateLegacyDatesResolveToActiveThenEarliest() async throws {
        let profile = DiaryProfile(name: "Synthetic", timeZoneID: "Pacific/Honolulu")
        let utc = TrackingDay(localDate: "2026-11-17", timeZoneID: "UTC", startAt: DayTests.date("2026-11-17T01:00:00Z"))
        let honolulu = TrackingDay(localDate: "2026-11-17", timeZoneID: "Pacific/Honolulu", startAt: DayTests.date("2026-11-17T20:00:00Z"))
        let store = DiaryStore(directory: DiaryTests.directory())
        _ = try await store.importProfile(DiarySnapshot(profile: profile, days: [utc, honolulu], activeDayID: honolulu.id))
        let first = try await store.createWorkout(localDate: "2026-11-17", draft: Self.draft, performedAt: nil, expectedProfileID: profile.id)
        #expect(first.dayID == honolulu.id)
        _ = try await store.startDay(at: DayTests.date("2026-11-18T20:00:00Z"))
        let second = try await store.createWorkout(localDate: "2026-11-17", draft: Self.draft, performedAt: nil, expectedProfileID: profile.id)
        #expect(second.dayID == utc.id)
    }

    static let apple = FoodItem(name: "Synthetic apple", quantity: 1, unit: "portion", nutrition: NutritionValues(kcal: 95), provenance: .estimate, reference: "Synthetic estimate")

    @Test func coachTurnFromTelAvivAppliesAfterLandingInNewYork() async throws {
        let (store, profile, day) = try await DayTests.ready(zone: "Asia/Jerusalem", at: "2026-11-17T08:00:00Z")
        let turn = try await capturedTurn(store, text: "Synthetic apple", photos: [], at: DayTests.date("2026-11-17T09:00:00Z"), expectedProfileID: profile.id)
        try await move(store, profile, to: "America/New_York")
        let receipt = try await store.applyCoachFood(turnID: turn.id, targetLocalDate: "2026-11-17", items: [Self.apple], expectedProfileID: profile.id)
        #expect(receipt.dayID == day.id)
        let snapshot = try await store.snapshotForExport()
        #expect(snapshot.days.count == 1 && snapshot.meals.allSatisfy { $0.timeZoneID == "Asia/Jerusalem" }) // the turn's capture zone, not the landing zone
    }
    @Test func manualNutritionMealRecordsTheProfileZone() async throws {
        let (store, profile, day) = try await DayTests.ready(zone: "Asia/Jerusalem", at: "2026-11-17T08:00:00Z")
        try await move(store, profile, to: "America/New_York")
        let item = FoodItem(name: "Synthetic manual", quantity: 1, unit: "cup", nutrition: NutritionValues(kcal: 100), provenance: .user, reference: "Entered", uncertain: false)
        let at = DayTests.date("2026-11-17T20:00:00Z")
        let payload = ManualNutritionPayload(profileID: profile.id, mealID: UUID(), submissionID: UUID(), operation: .create,
            target: .recorded(dayID: day.id, localDate: day.localDate, timeZoneID: day.timeZoneID), capturedAt: at, eatenAt: at, timePrecision: .exact, expectedMealRevision: nil, items: [item])
        let selection = try await store.selectionOwnership(expectedProfileID: profile.id)
        _ = try await store.saveManualNutrition(payload, expectedSelection: selection, expectedProfileID: profile.id)
        #expect(try await store.snapshotForExport().meals.first { $0.id == payload.mealID }?.timeZoneID == "America/New_York")
    }
    @Test func coachTodayIsTheOpenDayInHonolulu() async throws {
        let (store, profile, day) = try await DayTests.ready(zone: "Asia/Tokyo", at: "2026-11-18T00:00:00Z")
        try await move(store, profile, to: "Pacific/Honolulu")
        let turn = try await capturedTurn(store, text: "Synthetic apple", photos: [], at: DayTests.date("2026-11-18T06:00:00Z"), expectedProfileID: profile.id)
        let receipt = try await store.applyCoachFood(turnID: turn.id, targetLocalDate: "2026-11-17", items: [Self.apple], expectedProfileID: profile.id)
        #expect(receipt.dayID == day.id)
    }
    @Test func coachCaptureSavesAfterZoneChangeBetweenPrepareAndCommit() async throws {
        let (store, profile, _) = try await DayTests.ready(zone: "Asia/Jerusalem", at: "2026-11-17T08:00:00Z")
        let prepared = try await store.coachCapturePreparation(at: DayTests.date("2026-11-17T09:00:00Z"), expectedProfileID: profile.id)
        let payload = try CoachSubmissionPayload(submissionID: UUID(), text: "Synthetic apple", attachments: [], context: prepared.context)
        try await move(store, profile, to: "America/New_York")
        let first = try await store.captureCoachSubmission(payload, expectedSelection: prepared.ownership, expectedProfileID: profile.id)
        let again = try await store.captureCoachSubmission(payload, expectedSelection: prepared.ownership, expectedProfileID: profile.id)
        #expect(first == again)
        #expect(try await store.snapshotForExport().coachTurns.count == 1)
    }

    @Test func coachWeightCorrectsOnlyTheSelectedDayWhenTwoDaysShareADate() async throws {
        let profile = DiaryProfile(name: "Synthetic", timeZoneID: "Pacific/Honolulu")
        let utc = TrackingDay(localDate: "2026-11-17", timeZoneID: "UTC", startAt: DayTests.date("2026-11-17T01:00:00Z"))
        let honolulu = TrackingDay(localDate: "2026-11-17", timeZoneID: "Pacific/Honolulu", startAt: DayTests.date("2026-11-17T20:00:00Z"))
        let utcWeight = WeightEntry(dayID: utc.id, measuredAt: utc.startAt, value: 80)
        let honoluluWeight = WeightEntry(dayID: honolulu.id, measuredAt: honolulu.startAt, value: 70)
        let store = DiaryStore(directory: DiaryTests.directory())
        _ = try await store.importProfile(DiarySnapshot(profile: profile, days: [utc, honolulu], weights: [utcWeight, honoluluWeight], activeDayID: honolulu.id))
        let turn = try await capturedTurn(store, text: "Weighed 71 kg", photos: [], at: DayTests.date("2026-11-17T21:00:00Z"), expectedProfileID: profile.id)
        let epoch = try await store.selectionEpoch(expectedProfileID: profile.id)
        _ = try await store.applyCoachWrites([.weight(date: "2026-11-17", value: 71, unit: "kg", revision: honoluluWeight.revision)], turnID: turn.id, epoch: epoch, expectedProfileID: profile.id)
        let weights = try await store.snapshotForExport().weights
        #expect(weights.first { $0.id == honoluluWeight.id }?.value == 71)
        #expect(weights.first { $0.id == utcWeight.id } == utcWeight)
    }
}
