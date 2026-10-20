import Foundation
import Testing
@testable import Mivu

struct DayTests {
    static func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    static func ready(zone: String = "Asia/Jerusalem", at: String = "2026-10-10T09:00:00Z") async throws -> (DiaryStore, DiaryProfile, TrackingDay) {
        let store = DiaryStore(directory: DiaryTests.directory())
        let profile = DiaryProfile(name: "Synthetic", timeZoneID: zone)
        _ = try await store.createProfile(profile)
        let day = try await store.startDay(at: date(at))
        return (store, profile, day)
    }
    @Test func wakingDateCountsTheHoursBeforeTheCutoffForTheDayBefore() {
        #expect(wakingDateLabel(Self.date("2026-10-11T01:30:00Z"), zone: "UTC", cutoffHour: 4) == "2026-10-10")
        #expect(wakingDateLabel(Self.date("2026-10-11T04:00:00Z"), zone: "UTC", cutoffHour: 4) == "2026-10-11")
        #expect(wakingDateLabel(Self.date("2026-10-11T01:30:00Z"), zone: "UTC", cutoffHour: 0) == "2026-10-11")
    }
    @Test func lateFoodStaysInTheWakingDayAndTheCutoffStartsTheNextWithoutAsking() async throws {
        let (store, _, day) = try await Self.ready()
        #expect(try await store.dayAssignment(at: Self.date("2026-10-10T22:30:00Z")) == .existing(day.id))
        #expect(try await store.dayAssignment(at: Self.date("2026-10-11T00:59:59Z")) == .existing(day.id))
        #expect(try await store.dayAssignment(at: Self.date("2026-10-11T01:00:00Z")) == .newDay)
        #expect(try await store.startDay(at: Self.date("2026-10-11T01:00:00Z")).localDate == "2026-10-11")
    }
    @Test func earlyMorningCaptureLetsCoachJudgeTheNightBefore() {
        let early = WakingDayInstruction.text(capturedAt: Self.date("2026-10-11T05:30:00Z"), zone: "UTC", cutoffHour: 4)
        #expect(early.contains("alcohol") && early.contains("(2026-10-10)") && early.contains("belongs to 2026-10-11"))
        let late = WakingDayInstruction.text(capturedAt: Self.date("2026-10-11T07:00:00Z"), zone: "UTC", cutoffHour: 4)
        #expect(late == "The current waking day is 2026-10-11; log new intake to it unless the person names another day.")
        #expect(WakingDayInstruction.text(capturedAt: Self.date("2026-10-11T01:30:00Z"), zone: "UTC", cutoffHour: 4).contains("2026-10-10"))
    }
    @Test func explicitStartBeforeTheCutoffOpensTheCalendarDateOnce() async throws {
        let (store, _, day) = try await Self.ready(zone: "UTC")
        let next = try await store.startDay(at: Self.date("2026-10-11T01:30:00Z"))
        #expect(next.id != day.id && next.localDate == "2026-10-11")
        #expect(try await store.dayAssignment(at: Self.date("2026-10-11T02:00:00Z")) == .existing(next.id))
        #expect(try await store.dayAssignment(at: Self.date("2026-10-11T09:00:00Z")) == .existing(next.id))
    }
    @Test func startDayAndMorningWeightAreIdempotent() async throws {
        let (store, _, oldDay) = try await Self.ready()
        let morning = Self.date("2026-10-11T09:00:00Z")
        let day = try await store.startDay(at: morning)
        #expect(try await store.startDay(at: morning).id == day.id)
        let weight = try await store.recordWeight(value: 70, at: morning)
        let second = try await store.recordWeight(value: 71, at: morning)
        let snapshot = try await store.snapshotForExport()
        #expect(weight.id == second.id)
        #expect(snapshot.days.count == 2)
        #expect(snapshot.weights.count == 1)
        #expect(snapshot.weights[0].value == 71)
        #expect(snapshot.days.first { $0.id == oldDay.id }?.completeness == .unknown)
    }
    @Test func DSTNightStaysInTheWakingDay() async throws {
        let (store, _, day) = try await Self.ready(zone: "America/New_York", at: "2026-10-31T12:00:00Z")
        #expect(try await store.dayAssignment(at: Self.date("2026-11-01T05:30:00Z")) == .existing(day.id))
        #expect(try await store.startDay(at: Self.date("2026-11-01T12:00:00Z")).localDate == "2026-11-01")
    }
    @Test func timezoneChangeStartsADayInTheNewZoneAndPreservesHistory() async throws {
        let (store, profile, day) = try await Self.ready()
        var changed = profile
        changed.timeZoneID = "America/New_York"
        try await store.updateProfile(changed)
        #expect(try await store.dayAssignment(at: day.startAt) == .newDay)
        #expect(try await store.snapshotForExport().days[0] == day)
    }
    @Test func moveUpdatesBothDayTotalsAndCompletenessStaysIndependent() async throws {
        let (store, _, oldDay) = try await Self.ready()
        let meal = try await capturedMeal(store, text: "apple", photos: [], reviewFirst: false, dayID: oldDay.id)
        try await store.processPending()
        try await store.setCompleteness(dayID: oldDay.id, .partial)
        let newDay = try await store.startDay(at: Self.date("2026-10-11T09:00:00Z"))
        try await store.moveMeal(meal.id, to: newDay.id)
        let snapshot = try await store.snapshotForExport()
        #expect(snapshot.totals(dayID: oldDay.id).kcal == nil)
        #expect(snapshot.totals(dayID: newDay.id).kcal == 95)
        #expect(snapshot.days.first { $0.id == oldDay.id }?.completeness == .partial)
        try await store.setCompleteness(dayID: oldDay.id, .complete)
        #expect(try await store.snapshotForExport().totals(dayID: oldDay.id).kcal == 0)
    }
    @Test func confirmedEmptyDayWithPendingCaptureNeverReportsZero() async throws {
        let (store, _, day) = try await Self.ready()
        try await store.setCompleteness(dayID: day.id, .complete)
        _ = try await capturedMeal(store, text: "apple", photos: [], reviewFirst: true, dayID: day.id)
        #expect(try await store.snapshotForExport().totals(dayID: day.id).kcal == nil)
        try await store.processPending()
        #expect(try await store.snapshotForExport().totals(dayID: day.id).kcal == nil)
    }

}
