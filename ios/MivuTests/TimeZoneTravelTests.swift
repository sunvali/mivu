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
        #expect(try await store.snapshotForExport().days.count == 1)
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
}
