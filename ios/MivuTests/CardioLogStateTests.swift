import Foundation
import Testing
@testable import Mivu

@Suite struct CardioLogStateTests {
    private let now = ISO8601DateFormatter().date(from: "2027-03-10T18:00:00+02:00")!

    private func log(_ activity: String, km: Double?, minutes: Double) -> CardioLogState {
        var state = CardioLogState(activity: activity, last: nil, now: now)
        state.km = km; state.minutes = minutes
        return state
    }

    @Test func editedStartAfterMidnightCountsForWakingDay() async throws {
        var state = log("run", km: 5, minutes: 30)
        state.startedAt = ISO8601DateFormatter().date(from: "2027-03-10T01:30:00+02:00")!; state.startEdited = true
        #expect(state.day(zone: "Asia/Jerusalem") == "2027-03-09", "before the cutoff it is still the previous waking day, as meals are")
        state.startedAt = ISO8601DateFormatter().date(from: "2027-03-10T07:00:00+02:00")!
        #expect(state.day(zone: "Asia/Jerusalem") == "2027-03-10")

        // Stored there with its exact start kept.
        state.startedAt = ISO8601DateFormatter().date(from: "2027-03-10T01:30:00+02:00")!
        let root = URL.temporaryDirectory.appending(path: "CardioDay-" + UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let profile = DiaryProfile(name: "Synthetic runner", timeZoneID: "Asia/Jerusalem"), store = DiaryStore(directory: root)
        _ = try await store.createProfile(profile)
        let saved = try await store.createWorkout(localDate: state.day(zone: profile.timeZoneID), draft: state.draft(bodyKg: nil),
                                                  performedAt: state.startedAt, expectedProfileID: profile.id)
        #expect(try await store.trackingDay(id: saved.dayID, expectedProfileID: profile.id).localDate == "2027-03-09")
        #expect(saved.performedAt == state.startedAt && saved.timePrecision == .exact)
    }

    @Test func paceRun() {
        let run = log("run", km: 5, minutes: 28)
        #expect(run.pace(unit: "km") == "5:36 /km")
        #expect(run.pace(unit: "mi") == "9:01 /mi")
        #expect(log("run", km: nil, minutes: 28).pace(unit: "km") == nil)
    }

    @Test func speedCycle() {
        #expect(log("cycle", km: 20, minutes: 60).pace(unit: "km") == "20 km/h")
        #expect(log("cycle", km: 20, minutes: 60).pace(unit: "mi") == "12.4 mph")
    }

    @Test func swimPer100() {
        #expect(log("swim", km: 1, minutes: 20).pace(unit: "km") == "2:00 /100 m")
    }

    @Test func defaultsFromLast() {
        var last = WorkoutSession(dayID: UUID(), performedAt: now, timePrecision: .exact, revision: 1, kind: .cardio, durationMinutes: 28, exercises: [])
        last.activity = "run"; last.durationSeconds = 1_680; last.distanceMeters = 5_000; last.effort = 7; last.indoor = true
        let state = CardioLogState(activity: "run", last: last, now: now)
        #expect(state.minutes == 28 && state.km == 5 && state.effort == 7 && state.indoor == true)

        let fresh = CardioLogState(activity: "run", last: nil, now: now)
        #expect(fresh.minutes == 30 && fresh.km == 5 && fresh.effort == 5)
        #expect(CardioLogState(activity: "yoga", last: nil, now: now).km == nil)
    }

    @Test func typedKcalWins() {
        var state = log("run", km: 5, minutes: 28)
        let estimated = state.draft(bodyKg: 70)
        #expect(estimated.estimatedBurnKcal == WorkoutBurn.estimate(activity: "run", seconds: 1_680, distanceMeters: 5_000, effort: 5, bodyKg: 70))
        #expect(estimated.burnSource == nil)
        #expect(state.draft(bodyKg: nil).estimatedBurnKcal == nil)

        state.typedKcal = 400
        let typed = state.draft(bodyKg: 70)
        #expect(typed.estimatedBurnKcal == 400 && typed.burnSource == .userEstimate)
    }

    @Test func draftSecondsAndSource() {
        var state = log("run", km: 5, minutes: 28)
        state.note = "  "
        let draft = state.draft(bodyKg: 70)
        #expect(draft.durationSeconds == 1_680 && draft.durationMinutes == 28)
        #expect(draft.source == .manual && draft.state == .finished && draft.kind == .cardio)
        #expect(draft.activity == "run" && draft.title == "Run" && draft.distanceMeters == 5_000 && draft.effort == 5)
        #expect(draft.note == nil)
    }

    @Test func rowMarksEstimatedBurn() {
        var session = WorkoutSession(dayID: UUID(), performedAt: now, timePrecision: .exact, revision: 1, kind: .cardio, durationMinutes: 28, exercises: [])
        #expect(WorkoutRow.burn(session) == nil)
        session.estimatedBurnKcal = 310
        #expect(WorkoutRow.burn(session) == "~310")
        session.burnSource = .userEstimate
        #expect(WorkoutRow.burn(session) == "310")
    }
}
