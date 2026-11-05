import Foundation
import Observation

/// `.live` runs a clock and saves every change; `.past` (a workout logged afterwards) and `.edit` save once on Done.
enum LiveWorkoutMode: Equatable { case live, past, edit }

/// Lifting shows in the person's unit; storage is always kg.
enum WeightStep {
    // shortcut: the spec's default plates until Settings › Bar and plates stores the person's own.
    static let defaultPlatesKg: [Double] = [25, 20, 15, 10, 5, 2.5]
    static let defaultPlatesLb: [Double] = [45, 35, 25, 10, 5]

    static func step(unit: String, plates: [Double]) -> Double {
        unit == "lb" ? (plates.contains(2.5) ? 2.5 : 5) : (plates.contains(1.25) ? 1.25 : 2.5)
    }

    /// Rounded to hundredths so a weight entered in lb reads back exactly (135, not 134.99).
    static func display(kg: Double, unit: String) -> Double {
        ((unit == "lb" ? kg / 0.45359237 : kg) * 100).rounded() / 100
    }

    static func kg(fromDisplay value: Double, unit: String) -> Double { unit == "lb" ? value * 0.45359237 : value }
}

/// The gym screen's state. Live changes are saved one at a time, in order, before the screen shows them.
@MainActor @Observable final class LiveWorkoutModel {
    let mode: LiveWorkoutMode
    let unit: String
    var session: WorkoutSession
    var expandedExercise: Int
    var newBests: Set<Int> = []
    var saveError: String?
    /// Recent distinct exercises, newest first, for the exercise picker.
    var recent: [WorkoutExercise] = []
    @ObservationIgnored private let store: DiaryStore
    @ObservationIgnored private let profileID: UUID
    @ObservationIgnored private var history: [ExerciseKey: [WorkoutSession]] = [:]
    @ObservationIgnored private var pending: Task<Void, Never>?

    init(store: DiaryStore, profileID: UUID, session: WorkoutSession, unit: String, mode: LiveWorkoutMode) {
        self.store = store; self.profileID = profileID; self.session = session; self.unit = unit; self.mode = mode
        // The first exercise with an unticked set, else the last one.
        expandedExercise = session.exercises.firstIndex { $0.sets.contains { $0.done != true } } ?? max(session.exercises.count - 1, 0)
    }

    static func measure(_ exercise: WorkoutExercise) -> ExerciseMeasure {
        exercise.measure ?? exercise.exerciseID.flatMap { WorkoutCatalog.exercise($0)?.measure } ?? .weightReps
    }

    /// Reads each exercise's earlier workouts once, for "Last time" and new bests, and the recent exercises.
    func load() async {
        for exercise in session.exercises { await loadHistory(exercise) }
        refreshBests()
        var seen = Set<ExerciseKey>()
        let workouts = (try? await store.workoutHistory(expectedProfileID: profileID).values) ?? []
        recent = workouts.flatMap(\.exercises).filter { seen.insert(ExerciseKey($0)).inserted }.prefix(8).map { var exercise = $0; exercise.sets = []; return exercise }
    }

    func tick(exercise: Int, set: Int) async {
        await change(exercise, set) { $0.exercises[exercise].sets[set].done = $0.exercises[exercise].sets[set].done != true }
        refreshBests()
    }

    /// Copies the row above, else last time's set at this position, else a starting set.
    func addSet(exercise: Int) async {
        await change(exercise) { [self] session in
            let current = session.exercises[exercise]
            var next = current.sets.last ?? lastTime(of: current, position: 1, type: .normal) ?? Self.starter(Self.measure(current))
            next.done = false; next.effort = nil
            session.exercises[exercise].sets.append(next)
        }
    }

    /// Adds an exercise filled with last time's sets (unticked), or one starting set.
    func addExercise(_ exercise: WorkoutExercise) async {
        await loadHistory(exercise)
        var added = exercise
        if added.sets.isEmpty {
            let last = history[ExerciseKey(exercise)]?.first?.exercises.filter { ExerciseKey($0) == ExerciseKey(exercise) }
                .flatMap(\.sets).filter { $0.done != false } ?? []
            added.sets = last.isEmpty ? [Self.starter(Self.measure(exercise))] : last.map { var set = $0; set.done = false; set.effort = nil; return set }
        }
        await change { $0.exercises.append(added) }
        expandedExercise = session.exercises.count - 1
    }

    /// Changes the given values; nil keeps a value as it is.
    func update(exercise: Int, set: Int, kg: Double?, reps: Int?, seconds: Int?) async {
        await change(exercise, set) { session in
            if let kg { session.exercises[exercise].sets[set].loadKg = kg }
            if let reps { session.exercises[exercise].sets[set].repetitions = reps }
            if let seconds { session.exercises[exercise].sets[set].seconds = seconds }
        }
        refreshBests()
    }

    func deleteSet(exercise: Int, set: Int) async {
        await change(exercise, set) { $0.exercises[exercise].sets.remove(at: set) }
        refreshBests()
    }

    /// Saves the screen as it is again, after a failed save.
    func retry() async { await change { _ in } }

    /// The same set in the most recent finished workout with this exercise.
    func lastTime(exercise: Int, set: Int) -> WorkoutSet? {
        let current = session.exercises[exercise], type = current.sets[set].type ?? .normal
        return lastTime(of: current, position: current.sets[...set].filter { ($0.type ?? .normal) == type }.count, type: type)
    }

    var hasTicked: Bool { session.exercises.contains { $0.sets.contains { $0.done == true } } }

    /// Saves the workout as finished; false when it could not be saved.
    func finish(at now: Date = Date()) async -> Bool {
        await pending?.value
        do {
            switch mode {
            case .live:
                session = try await store.finishWorkout(id: session.id, effort: nil, at: now, expectedRevision: session.revision, expectedProfileID: profileID)
            case .past:
                let zone = try await store.diaryHead(expectedProfileID: profileID).profile.timeZoneID
                let date = diaryDateLabel(session.performedAt, zone: zone)
                let exercises = session.exercises.compactMap { exercise in
                    var ticked = exercise; ticked.sets = exercise.sets.filter { $0.done == true }; return ticked.sets.isEmpty ? nil : ticked
                }
                // shortcut: a past log has no clock, so it counts three minutes a set; the Done screen can let people correct it.
                let seconds = max(exercises.reduce(0) { $0 + $1.sets.count }, 1) * 180
                let bodyKg = try await store.bodyKg(on: date, expectedProfileID: profileID)
                let draft = WorkoutDraft(kind: .strength, durationMinutes: seconds / 60, exercises: exercises,
                    estimatedBurnKcal: WorkoutBurn.estimate(activity: session.activity ?? "strength", seconds: seconds, distanceMeters: nil, effort: nil, bodyKg: bodyKg),
                    title: session.title, activity: session.activity ?? "strength", state: .finished, durationSeconds: seconds,
                    routineID: session.routineID, source: .manual)
                session = try await store.createWorkout(localDate: date, draft: draft, performedAt: session.performedAt, expectedProfileID: profileID)
            case .edit:
                session = try await store.updateWorkout(session, expectedRevision: session.revision, expectedProfileID: profileID)
            }
            saveError = nil
            return true
        } catch { saveError = error.localizedDescription; return false }
    }

    func discard() async -> Bool {
        await pending?.value
        guard mode == .live else { return true }
        do { try await store.discardWorkout(id: session.id, expectedRevision: session.revision, expectedProfileID: profileID); return true }
        catch { saveError = error.localizedDescription; return false }
    }

    /// Applies one edit after the previous one is saved, so quick taps never save over each other.
    private func change(_ edit: @escaping (inout WorkoutSession) -> Void) async {
        let previous = pending
        let task = Task { [self] in
            await previous?.value
            var next = session; edit(&next)
            guard mode == .live else { session = next; return }
            do {
                session = try await store.saveActive(next, expectedRevision: next.revision, expectedProfileID: profileID)
                saveError = nil
            } catch {
                // The values stay on screen; Retry saves them again.
                session = next; saveError = error.localizedDescription
            }
        }
        pending = task
        await task.value
    }

    /// An edit to one exercise or set; skipped if an earlier queued edit removed it.
    private func change(_ exercise: Int, _ set: Int? = nil, _ edit: @escaping (inout WorkoutSession) -> Void) async {
        await change { session in
            guard session.exercises.indices.contains(exercise), set.map(session.exercises[exercise].sets.indices.contains) ?? true else { return }
            edit(&session)
        }
    }

    private func loadHistory(_ exercise: WorkoutExercise) async {
        let key = ExerciseKey(exercise)
        guard history[key] == nil else { return }
        // shortcut: bests read the latest 1,000 workouts with this exercise; store bests if someone logs more.
        history[key] = ((try? await store.finishedWorkouts(containing: key, limit: 1_000, expectedProfileID: profileID)) ?? []).filter { $0.id != session.id }
    }

    private func lastTime(of exercise: WorkoutExercise, position: Int, type: WorkoutSetType) -> WorkoutSet? {
        WorkoutHistory.lastTime(for: ExerciseKey(exercise), position: position, type: type, in: history[ExerciseKey(exercise)] ?? [])
    }

    private func refreshBests() {
        newBests = Set(session.exercises.indices.filter { index in
            let exercise = session.exercises[index], key = ExerciseKey(exercise)
            let before = (history[key] ?? []).flatMap(\.exercises).filter { ExerciseKey($0) == key }.flatMap(\.sets)
            return exercise.sets.contains { $0.done == true && WorkoutHistory.isNewBest($0, measure: Self.measure(exercise), before: before) }
        })
    }

    private static func starter(_ measure: ExerciseMeasure) -> WorkoutSet {
        switch measure {
        case .time, .distanceTime: WorkoutSet(repetitions: 0, seconds: 60, done: false)
        case .weightReps: WorkoutSet(repetitions: 10, loadKg: 0, done: false)
        case .reps: WorkoutSet(repetitions: 10, done: false)
        }
    }
}
