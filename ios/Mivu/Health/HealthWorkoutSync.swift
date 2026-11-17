import Foundation
import HealthKit

/// Reads workouts from Apple Health. A seam so tests use synthetic workouts only.
protocol HealthWorkoutReading: Sendable {
    func requestAuthorization() async throws
    /// Every workout that started since `since`, plus workouts deleted in Health after `anchor` (nil: none yet).
    func changes(since: Date, anchor: Data?) async throws -> (workouts: [HealthWorkout], deletedIDs: [UUID], anchor: Data?)
    /// Calls `onChange` whenever Health gets new or deleted workouts, including in the background.
    func observe(_ onChange: @escaping @Sendable () async -> Void)
    func stopObserving()
}

/// Brings Apple Health workouts into the selected diary. Imported workouts stay when Health is disconnected.
@MainActor @Observable final class HealthWorkoutSync {
    private(set) var isConnected = false
    private let reader: HealthWorkoutReading
    private let model: DiaryViewModel
    private let defaults: UserDefaults
    @ObservationIgnored private var observing = false
    @ObservationIgnored private var running = false
    @ObservationIgnored private var pending = false

    init(reader: HealthWorkoutReading, model: DiaryViewModel, defaults: UserDefaults) {
        self.reader = reader; self.model = model; self.defaults = defaults
    }

    private var profileID: UUID? { model.selection?.identity.profileID }

    static func anyConnected(_ defaults: UserDefaults) -> Bool {
        defaults.dictionaryRepresentation().contains { $0.key.hasPrefix("health.connected.") && ($0.value as? Bool) == true }
    }
    private func key(_ name: String, _ profileID: UUID) -> String { "health.\(name).\(profileID.uuidString)" }

    /// Re-reads the switch for the selected profile; call after a profile change or launch.
    func refresh() {
        isConnected = profileID.map { defaults.bool(forKey: key("connected", $0)) } ?? false
        if isConnected { startObserving() }
    }

    func connect() async throws {
        guard let id = profileID else { return }
        try await reader.requestAuthorization()
        defaults.set(true, forKey: key("connected", id)); isConnected = true
        startObserving()
        await sync()
    }

    func disconnect() {
        guard let id = profileID else { return }
        defaults.set(false, forKey: key("connected", id)); defaults.removeObject(forKey: key("anchor", id))
        isConnected = false
        // Background delivery stays on across launches until turned off, so stop it once no profile reads Health.
        if !Self.anyConnected(defaults) { reader.stopObserving(); observing = false }
    }

    /// Safe to call often: overlapping calls run once more after the current one.
    func sync() async {
        if running { pending = true; return }
        running = true; defer { running = false }
        repeat {
            pending = false
            guard let token = model.selection, defaults.bool(forKey: key("connected", token.identity.profileID)) else { return }
            let id = token.identity.profileID
            do {
                // The store keeps only the last 7 local days; a day of margin covers time zones.
                let since = Date().addingTimeInterval(-8 * 86_400)
                let result = try await reader.changes(since: since, anchor: defaults.data(forKey: key("anchor", id)))
                guard model.selection == token, defaults.bool(forKey: key("connected", id)) else { return }
                try await model.store.applyHealthWorkouts(result.workouts, deletedIDs: result.deletedIDs, expectedProfileID: id)
                defaults.set(result.anchor, forKey: key("anchor", id))
                try await model.refresh(profileID: id)
                publishWidgetSnapshot(model.readModel)
            } catch {
                // A locked phone or a busy diary: keep the anchor and try again on the next change or launch.
                return
            }
        } while pending
    }

    private func startObserving() {
        guard !observing else { return }
        observing = true
        reader.observe { [weak self] in await self?.sync() }
    }
}

/// Maps Health activity types onto Mivu's three workout kinds.
func healthWorkoutKind(_ type: HKWorkoutActivityType) -> WorkoutKind {
    switch type {
    case .traditionalStrengthTraining, .functionalStrengthTraining, .coreTraining, .crossTraining: .strength
    case .running, .walking, .cycling, .swimming, .rowing, .elliptical, .stairClimbing, .stairs, .highIntensityIntervalTraining,
         .hiking, .crossCountrySkiing, .downhillSkiing, .jumpRope, .mixedCardio, .paddleSports, .wheelchairRunPace, .wheelchairWalkPace: .cardio
    default: .other
    }
}

final class HKHealthReader: HealthWorkoutReading, @unchecked Sendable {
    private let store = HKHealthStore()
    private var query: HKObserverQuery?  // main actor only: HealthWorkoutSync starts and stops it
    private let energy = HKQuantityType(.activeEnergyBurned)

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw DiaryError.persistenceFailed }
        try await store.requestAuthorization(toShare: [], read: [HKObjectType.workoutType(), energy])
    }

    func changes(since: Date, anchor: Data?) async throws -> (workouts: [HealthWorkout], deletedIDs: [UUID], anchor: Data?) {
        let predicate = HKQuery.predicateForSamples(withStart: since, end: nil)
        let previous = anchor.flatMap { try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: $0) }
        let changed = try await HKAnchoredObjectQueryDescriptor(predicates: [.workout(predicate)], anchor: previous).result(for: store)
        // The full window every time, so a restored or reinstalled diary gets its recent workouts back.
        let workouts = try await HKSampleQueryDescriptor(predicates: [.workout(predicate)], sortDescriptors: [SortDescriptor(\.startDate)]).result(for: store)
        return (workouts.map { workout in
                    HealthWorkout(id: workout.uuid, start: workout.startDate, end: workout.endDate,
                                  activeKcal: workout.statistics(for: energy)?.sumQuantity()?.doubleValue(for: .kilocalorie()),
                                  sourceName: workout.sourceRevision.source.name, kind: healthWorkoutKind(workout.workoutActivityType))
                },
                previous == nil ? [] : changed.deletedObjects.map(\.uuid),
                try NSKeyedArchiver.archivedData(withRootObject: changed.newAnchor, requiringSecureCoding: true))
    }

    func observe(_ onChange: @escaping @Sendable () async -> Void) {
        let query = HKObserverQuery(sampleType: HKObjectType.workoutType(), predicate: nil) { _, completion, error in
            // Health waits for this call before it sends more background updates.
            nonisolated(unsafe) let completion = completion
            let failed = error != nil
            Task { if !failed { await onChange() }; completion() }
        }
        self.query = query
        store.execute(query)
        store.enableBackgroundDelivery(for: HKObjectType.workoutType(), frequency: .immediate) { _, _ in }
    }

    func stopObserving() {
        if let query { store.stop(query) }
        query = nil
        store.disableBackgroundDelivery(for: HKObjectType.workoutType()) { _, _ in }
    }
}
