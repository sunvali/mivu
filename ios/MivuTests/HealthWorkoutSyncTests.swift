import Foundation
import HealthKit
import Testing
@testable import Mivu

@Suite @MainActor struct HealthWorkoutSyncTests {
    private final class FakeReader: HealthWorkoutReading, @unchecked Sendable {
        var workouts: [HealthWorkout] = [], deleted: [UUID] = [], anchors: [Data?] = [], authorized = false
        func requestAuthorization() async throws { authorized = true }
        func changes(since: Date, anchor: Data?) async throws -> (workouts: [HealthWorkout], deletedIDs: [UUID], anchor: Data?) {
            anchors.append(anchor); return (workouts, deleted, Data("anchor-\(anchors.count)".utf8))
        }
        func observe(_ onChange: @escaping @Sendable () async -> Void) {}
    }

    /// 10:00 in Jerusalem on 2027-01-15, with that day open.
    private let now = ISO8601DateFormatter().date(from: "2027-01-15T08:00:00Z")!

    private func fixture() async throws -> (HealthWorkoutSync, DiaryViewModel, FakeReader, HealthWorkout, URL) {
        let root = URL.temporaryDirectory.appending(path: "HealthSync-" + UUID().uuidString)
        let clock = now, store = DiaryStore(directory: root, currentTime: { clock })
        _ = try await store.createProfile(DiaryProfile(name: "Synthetic health sync", timeZoneID: "Asia/Jerusalem"))
        _ = try await store.startDay(at: now)
        let diary = DiaryViewModel(store: store)
        await diary.load(createDefaultProfile: false)
        let reader = FakeReader(), defaults = try #require(UserDefaults(suiteName: "HealthSync-" + UUID().uuidString))
        let run = HealthWorkout(id: UUID(), start: now.addingTimeInterval(-3_600), end: now.addingTimeInterval(-900),
                                activeKcal: 412, sourceName: "Garmin Connect", kind: .cardio)
        return (HealthWorkoutSync(reader: reader, model: diary, defaults: defaults), diary, reader, run, root)
    }

    @Test func syncAppliesChangesAndStoresAnchor() async throws {
        let (sync, diary, reader, run, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        reader.workouts = [run]
        try await sync.connect()
        #expect(reader.authorized && sync.isConnected)
        #expect(diary.readModel?.workouts.map(\.id) == [run.id])
        await sync.sync()
        #expect(reader.anchors == [nil, Data("anchor-1".utf8)])
    }

    @Test func disconnectKeepsWorkoutsAndStopsImports() async throws {
        let (sync, diary, reader, run, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        reader.workouts = [run]
        try await sync.connect()
        sync.disconnect()
        reader.workouts = []; reader.deleted = [run.id]
        await sync.sync()
        #expect(!sync.isConnected && reader.anchors.count == 1)
        #expect(try await diary.store.snapshotForExport().workouts.map(\.id) == [run.id])
    }

    @Test func notConnectedNeverReadsHealth() async throws {
        let (sync, _, reader, _, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        sync.refresh()
        await sync.sync()
        #expect(!sync.isConnected && reader.anchors.isEmpty && !reader.authorized)
    }

    @Test func workoutKindMapping() {
        #expect(healthWorkoutKind(.running) == .cardio)
        #expect(healthWorkoutKind(.traditionalStrengthTraining) == .strength)
        #expect(healthWorkoutKind(.yoga) == .other)
    }
}
