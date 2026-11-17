import Foundation
import Testing
@testable import Mivu

@Suite struct HealthWorkoutStoreTests {
    private final class Clock: @unchecked Sendable { var now: Date; init(_ now: Date) { self.now = now } }
    private static let zone = "Asia/Jerusalem"

    private func at(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    /// Days at 07:00 Jerusalem; the clock starts at 10:00 Jerusalem on 2027-01-15.
    private func fixture(days labels: [String], clock: Clock? = nil) async throws -> (DiaryStore, DiaryProfile, [String: TrackingDay], URL) {
        let root = URL.temporaryDirectory.appending(path: "HealthStore-" + UUID().uuidString)
        let clock = clock ?? Clock(at("2027-01-15T08:00:00Z"))
        let store = DiaryStore(directory: root, currentTime: { clock.now })
        let profile = DiaryProfile(name: "Synthetic health", timeZoneID: Self.zone)
        let days = labels.map { TrackingDay(localDate: $0, timeZoneID: Self.zone, startAt: at("\($0)T05:00:00Z")) }
        var snapshot = DiarySnapshot(revision: 1, profile: profile, days: days, activeDayID: days.last?.id)
        snapshot.lineage = [UUID()]
        _ = try await store.importProfile(snapshot)
        return (store, profile, Dictionary(uniqueKeysWithValues: days.map { ($0.localDate, $0) }), root)
    }

    private func garmin(_ start: String, minutes: Double = 45, kcal: Double? = 412, id: UUID = UUID()) -> HealthWorkout {
        let begin = at(start)
        return HealthWorkout(id: id, start: begin, end: begin.addingTimeInterval(minutes * 60), activeKcal: kcal, sourceName: "Garmin Connect", kind: .cardio)
    }

    @Test func importsIntoExistingDayWithinWindow() async throws {
        let (store, profile, days, root) = try await fixture(days: ["2027-01-15"]); defer { try? FileManager.default.removeItem(at: root) }
        let run = garmin("2027-01-15T05:00:00Z")
        try await store.applyHealthWorkouts([run], deletedIDs: [], expectedProfileID: profile.id)
        let workouts = try await store.snapshotForExport().workouts
        let saved = try #require(workouts.first)
        #expect(workouts.count == 1)
        #expect(saved.id == run.id && saved.dayID == days["2027-01-15"]?.id)
        #expect(saved.isFromHealth && saved.healthSource == "Garmin Connect" && saved.timePrecision == .exact)
        #expect(saved.durationMinutes == 45 && saved.estimatedBurnKcal == 412 && saved.revision == 1)
    }

    @Test func skipsDatesWithoutDayAndOutsideWindow() async throws {
        let (store, profile, _, root) = try await fixture(days: ["2027-01-07", "2027-01-15"]); defer { try? FileManager.default.removeItem(at: root) }
        try await store.applyHealthWorkouts([garmin("2027-01-12T05:00:00Z"), garmin("2027-01-07T05:00:00Z")], deletedIDs: [], expectedProfileID: profile.id)
        let snapshot = try await store.snapshotForExport()
        #expect(snapshot.workouts.isEmpty)
        #expect(snapshot.days.count == 2)
    }

    @Test func reapplyIsIdempotent() async throws {
        let (store, profile, _, root) = try await fixture(days: ["2027-01-15"]); defer { try? FileManager.default.removeItem(at: root) }
        let run = garmin("2027-01-15T05:00:00Z")
        try await store.applyHealthWorkouts([run], deletedIDs: [], expectedProfileID: profile.id)
        let before = try await store.snapshotForExport()
        try await store.applyHealthWorkouts([run], deletedIDs: [], expectedProfileID: profile.id)
        let after = try await store.snapshotForExport()
        #expect(after == before)
        #expect(after.workouts.first?.revision == 1)
    }

    @Test func changeUpdatesAndDeleteTombstones() async throws {
        let (store, profile, _, root) = try await fixture(days: ["2027-01-15"]); defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        try await store.applyHealthWorkouts([garmin("2027-01-15T05:00:00Z", id: id)], deletedIDs: [], expectedProfileID: profile.id)
        try await store.applyHealthWorkouts([garmin("2027-01-15T05:00:00Z", kcal: 430, id: id)], deletedIDs: [], expectedProfileID: profile.id)
        let updated = try #require(try await store.snapshotForExport().workouts.first)
        #expect(updated.revision == 2 && updated.estimatedBurnKcal == 430)
        let coach = try await store.createWorkout(localDate: "2027-01-15", draft: WorkoutDraft(kind: .strength, durationMinutes: 30, exercises: [], estimatedBurnKcal: nil, burnSource: nil),
                                                  performedAt: nil, expectedProfileID: profile.id)
        try await store.applyHealthWorkouts([], deletedIDs: [id, coach.id, UUID()], expectedProfileID: profile.id)
        try await store.applyHealthWorkouts([garmin("2027-01-15T05:00:00Z", kcal: 430, id: id)], deletedIDs: [], expectedProfileID: profile.id)
        let snapshot = try await store.snapshotForExport()
        #expect(snapshot.workouts.map(\.id) == [coach.id])
        #expect(snapshot.deletedWorkoutIDs.contains(id))
    }

    @Test func userDeleteBlocksReimport() async throws {
        let (store, profile, _, root) = try await fixture(days: ["2027-01-15"]); defer { try? FileManager.default.removeItem(at: root) }
        let run = garmin("2027-01-15T05:00:00Z")
        try await store.applyHealthWorkouts([run], deletedIDs: [], expectedProfileID: profile.id)
        try await store.deleteWorkout(id: run.id, expectedRevision: 1, expectedProfileID: profile.id)
        try await store.applyHealthWorkouts([run], deletedIDs: [], expectedProfileID: profile.id)
        #expect(try await store.snapshotForExport().workouts.isEmpty)
    }

    @Test func profileZoneDecidesDate() async throws {
        let (store, profile, days, root) = try await fixture(days: ["2027-01-14", "2027-01-15"]); defer { try? FileManager.default.removeItem(at: root) }
        // 23:30 UTC is 01:30 the next day in Jerusalem.
        try await store.applyHealthWorkouts([garmin("2027-01-14T23:30:00Z")], deletedIDs: [], expectedProfileID: profile.id)
        #expect(try await store.snapshotForExport().workouts.first?.dayID == days["2027-01-15"]?.id)
    }

    @Test func zeroCaloriesAreStoredAsUnknown() async throws {
        let (store, profile, _, root) = try await fixture(days: ["2027-01-15"]); defer { try? FileManager.default.removeItem(at: root) }
        try await store.applyHealthWorkouts([garmin("2027-01-15T05:00:00Z", kcal: 0)], deletedIDs: [], expectedProfileID: profile.id)
        #expect(try await store.snapshotForExport().workouts.first?.estimatedBurnKcal == nil)
    }

    @Test func durationIsClamped() async throws {
        let (store, profile, _, root) = try await fixture(days: ["2027-01-15"]); defer { try? FileManager.default.removeItem(at: root) }
        let short = garmin("2027-01-15T05:00:00Z", minutes: 1.0 / 3), long = garmin("2027-01-15T06:00:00Z", minutes: 30 * 60)
        try await store.applyHealthWorkouts([short, long], deletedIDs: [], expectedProfileID: profile.id)
        let minutes = Dictionary(uniqueKeysWithValues: try await store.snapshotForExport().workouts.map { ($0.id, $0.durationMinutes) })
        #expect(minutes[short.id] == 1 && minutes[long.id] == 1440)
    }

    @Test func enablingCreditStartsTodayAndKeepsEarlierGoals() async throws {
        let (store, profile, _, root) = try await fixture(days: ["2027-01-15"]); defer { try? FileManager.default.removeItem(at: root) }
        let earlier = GoalRecord(effectiveLocalDate: "2027-01-01", timeZoneID: Self.zone, targets: NutritionValues(kcal: 2_000), goalWeightKg: nil, exerciseCreditEnabled: false)
        _ = try await store.setGoals(earlier, expectedRevision: nil, expectedProfileID: profile.id)
        try await store.enableExerciseCredit(from: "2027-01-15", expectedProfileID: profile.id)
        try await store.enableExerciseCredit(from: "2027-01-15", expectedProfileID: profile.id)
        let goals = try await store.snapshotForExport().goals.sorted { $0.effectiveLocalDate < $1.effectiveLocalDate }
        #expect(goals.map(\.effectiveLocalDate) == ["2027-01-01", "2027-01-15"])
        #expect(goals.map(\.exerciseCreditEnabled) == [false, true])
        #expect(goals[1].targets.kcal == 2_000 && goals[1].revision == 1)
    }

    @Test func staleWindowChangesIgnored() async throws {
        let clock = Clock(at("2027-01-08T08:00:00Z"))
        let (store, profile, _, root) = try await fixture(days: ["2027-01-07", "2027-01-15"], clock: clock); defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        try await store.applyHealthWorkouts([garmin("2027-01-07T05:00:00Z", id: id)], deletedIDs: [], expectedProfileID: profile.id)
        clock.now = at("2027-01-15T08:00:00Z")
        let before = try await store.snapshotForExport()
        #expect(before.workouts.map(\.id) == [id])
        try await store.applyHealthWorkouts([garmin("2027-01-07T05:00:00Z", kcal: 999, id: id)], deletedIDs: [], expectedProfileID: profile.id)
        try await store.applyHealthWorkouts([], deletedIDs: [id], expectedProfileID: profile.id)
        #expect(try await store.snapshotForExport() == before)
    }
}
