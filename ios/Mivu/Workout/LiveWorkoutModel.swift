import Foundation
import Observation

/// `.live` runs a clock and saves every change; `.past` (a workout logged afterwards) and `.edit` save once on Done.
enum LiveWorkoutMode: Equatable { case live, past, edit }

/// Lifting shows in the person's unit; storage is always kg.
enum WeightStep {
    // shortcut: the spec's default plates until Settings › Bar and plates stores the person's own.
    static let defaultPlatesKg: [Double] = [25, 20, 15, 10, 5, 2.5, 1.25]
    static let defaultPlatesLb: [Double] = [45, 35, 25, 10, 5, 2.5]

    /// The smallest jump a loaded bar can make: the smallest plate on each side.
    static func step(unit: String, plates: [Double]) -> Double {
        plates.min().map { $0 * 2 } ?? (unit == "lb" ? 5 : 2.5)
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
    /// The routine this workout started from, if it still exists.
    var routine: WorkoutRoutine?
    /// The Done screen's answer to "How did it feel?".
    var effort: Int?
    /// When Done was tapped: a live workout ends there, not when Save is tapped.
    var endedAt = Date()
    private var typedMinutes: Double?
    private var bodyKg: Double?
    @ObservationIgnored private let store: DiaryStore
    @ObservationIgnored private let profileID: UUID
    /// The last copy the store holds; while a save fails, ticks it lacks are not shown done.
    private var saved: WorkoutSession
    @ObservationIgnored private var history: [ExerciseKey: [WorkoutSession]] = [:]
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private let rest: RestTimer?
    /// Told once a live or past workout is saved finished, for Pip.
    @ObservationIgnored private let onSaved: (WorkoutSession) -> Void

    init(store: DiaryStore, profileID: UUID, session: WorkoutSession, unit: String, mode: LiveWorkoutMode, rest: RestTimer? = nil,
         onSaved: @escaping (WorkoutSession) -> Void = { _ in }) {
        self.store = store; self.profileID = profileID; self.session = session; self.saved = session; self.unit = unit; self.mode = mode
        self.onSaved = onSaved
        self.rest = mode == .live ? rest : nil
        // The first exercise with an unticked set, else the last one.
        expandedExercise = session.exercises.firstIndex { $0.sets.contains { $0.done != true } } ?? max(session.exercises.count - 1, 0)
    }

    /// Live only for a start left at now (or within five minutes of it); anything earlier is logged afterwards.
    static func mode(start: Date?, now: Date) -> LiveWorkoutMode {
        guard let start, now.timeIntervalSince(start) > 300 else { return .live }
        return .past
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
        if let id = session.routineID { routine = (try? await store.routines(expectedProfileID: profileID))?.first { $0.id == id } }
        bodyKg = try? await store.bodyKg(on: workoutDate(), expectedProfileID: profileID)
    }

    func tick(exercise: Int, set: Int) async {
        // Toggles what the screen shows: a tick still unsaved after a failure is ticked again, not cleared.
        let done = !isTicked(exercise: exercise, set: set)
        await change(exercise, set) { $0.exercises[exercise].sets[set].done = done }
        // Rest starts only once the tick is saved; a failed one shows undone and starts nothing.
        guard done, let rest, isTicked(exercise: exercise, set: set) else { return }
        await rest.start(seconds: rest.seconds(for: session.exercises[exercise]), next: session.nextSetLabel ?? "", workout: session)
    }

    /// Copies the row above, else last time's set at this position, else a starting set.
    func addSet(exercise: Int) async {
        await change(exercise) { [self] session in
            let current = session.exercises[exercise]
            var next = current.sets.last ?? lastTime(of: current, position: 1, type: .normal) ?? starter(current)
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
            added.sets = last.isEmpty ? [starter(exercise)] : last.map { var set = $0; set.done = false; set.effort = nil; return set }
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
    }

    func deleteSet(exercise: Int, set: Int) async {
        await change(exercise, set) { $0.exercises[exercise].sets.remove(at: set) }
    }

    /// Saves the screen as it is again, after a failed save.
    func retry() async { await change { _ in } }

    /// The same set in the most recent finished workout with this exercise.
    func lastTime(exercise: Int, set: Int) -> WorkoutSet? {
        let current = session.exercises[exercise], type = current.sets[set].type ?? .normal
        return lastTime(of: current, position: current.sets[...set].filter { ($0.type ?? .normal) == type }.count, type: type)
    }

    /// Shown done: ticked and, while a save is failing, already stored ticked.
    func isTicked(exercise: Int, set: Int) -> Bool {
        guard session.exercises.indices.contains(exercise), session.exercises[exercise].sets.indices.contains(set),
              session.exercises[exercise].sets[set].done == true else { return false }
        guard saveError != nil else { return true }
        // shortcut: matched by position, so a set deleted during a failed save can shift this; Retry clears it.
        let stored = saved.exercises.indices.contains(exercise) ? saved.exercises[exercise].sets : []
        return stored.indices.contains(set) && stored[set].done == true
    }

    /// A weight exercise whose weight was never chosen: ✓ opens the wheels instead.
    func needsWeight(exercise: Int, set: Int) -> Bool {
        Self.measure(session.exercises[exercise]) == .weightReps && session.exercises[exercise].sets[set].loadKg == nil
    }

    /// Where the weight wheel starts for an unset weight, in the shown unit: the bar, else a light dumbbell.
    func startingWeight(exercise: Int) -> Double {
        let barbell = session.exercises[exercise].exerciseID.flatMap { WorkoutCatalog.exercise($0)?.barbell } == true
        return unit == "lb" ? (barbell ? 45 : 20) : (barbell ? 20 : 10)
    }

    var hasTicked: Bool { session.hasTickedSets }

    /// A past log has no clock: three minutes a set until the person corrects it.
    var pastMinutes: Double {
        get { typedMinutes ?? Double(max(session.exercises.reduce(0) { $0 + $1.sets.filter { $0.done == true }.count }, 1) * 3) }
        set { typedMinutes = newValue }
    }

    /// How long the workout took, as Save will store it.
    var seconds: Int {
        mode == .past ? Int(pastMinutes * 60) : min(max(Int(endedAt.timeIntervalSince(session.performedAt)), 1), 86_400)
    }

    /// The Done screen's three numbers; kcal is estimated as Save will store it.
    var summary: (sets: Int, kcal: Double?, newBests: Int) {
        let sets = session.exercises.indices.reduce(0) { total, e in total + session.exercises[e].sets.indices.filter { isTicked(exercise: e, set: $0) }.count }
        let kcal = session.burnSource == .userEstimate ? session.estimatedBurnKcal
            : WorkoutBurn.estimate(activity: session.activity ?? "strength", seconds: seconds, distanceMeters: nil, effort: effort, bodyKg: bodyKg)
        return (sets, kcal, newBests.count)
    }

    /// The "How did it feel?" chip closest to the ticked sets' average effort, if any were rated.
    var feel: Int? {
        let efforts = session.exercises.flatMap(\.sets).filter { $0.done == true }.compactMap(\.effort)
        guard !efforts.isEmpty else { return nil }
        let average = Double(efforts.reduce(0, +)) / Double(efforts.count)
        return EffortChips.efforts.map(\.1).min { abs(Double($0) - average) < abs(Double($1) - average) }
    }

    /// The ticked exercises or their set counts differ from the routine it started from.
    var routineChanged: Bool {
        guard let routine else { return false }
        func shape(_ exercises: [WorkoutExercise]) -> [[ExerciseKey]] { exercises.map { Array(repeating: ExerciseKey($0), count: $0.sets.count) } }
        return shape(routine.exercises) != shape(WorkoutRoutine(from: session, name: routine.name).exercises)
    }

    func saveRoutine(name: String) async -> Bool {
        do { routine = try await store.saveRoutine(WorkoutRoutine(from: session, name: name), expectedRevision: nil, expectedProfileID: profileID); return true }
        catch { saveError = error.localizedDescription; return false }
    }

    /// Replaces the routine's targets with this workout's ticked sets.
    func updateRoutine() async -> Bool {
        guard let id = routine?.id else { return false }
        do {
            // Read again: saving the workout moved the routine's last use on.
            guard let current = try await store.routines(expectedProfileID: profileID).first(where: { $0.id == id }) else { throw DiaryError.notFound }
            var updated = WorkoutRoutine(from: session, name: current.name)
            updated.id = id; updated.revision = current.revision; updated.lastUsedAt = max(current.lastUsedAt ?? .distantPast, session.performedAt)
            routine = try await store.saveRoutine(updated, expectedRevision: current.revision, expectedProfileID: profileID)
            return true
        } catch { saveError = error.localizedDescription; return false }
    }

    /// Saves the workout as finished; false when it could not be saved.
    func finish(at now: Date = Date()) async -> Bool {
        await pending?.value
        do {
            switch mode {
            case .live:
                // Edits that failed to save are saved first, so Done never drops a tick.
                if saveError != nil { session = try await store.saveActive(session, expectedRevision: session.revision, expectedProfileID: profileID) }
                session = try await store.finishWorkout(id: session.id, effort: effort, at: now, expectedRevision: session.revision, expectedProfileID: profileID)
                onSaved(session)
            case .past:
                let date = try await workoutDate()
                let exercises = session.exercises.compactMap { exercise in
                    var ticked = exercise; ticked.sets = exercise.sets.filter { $0.done == true }; return ticked.sets.isEmpty ? nil : ticked
                }
                let seconds = max(seconds, 60)
                let bodyKg = try await store.bodyKg(on: date, expectedProfileID: profileID)
                let draft = WorkoutDraft(kind: .strength, durationMinutes: seconds / 60, exercises: exercises,
                    estimatedBurnKcal: WorkoutBurn.estimate(activity: session.activity ?? "strength", seconds: seconds, distanceMeters: nil, effort: effort, bodyKg: bodyKg),
                    title: session.title, activity: session.activity ?? "strength", state: .finished, durationSeconds: seconds,
                    effort: effort, routineID: session.routineID, source: .manual)
                session = try await store.createWorkout(localDate: date, draft: draft, performedAt: session.performedAt, expectedProfileID: profileID)
                onSaved(session)
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
            guard mode == .live else { session = next; refreshBests(); return }
            do {
                session = try await store.saveActive(next, expectedRevision: next.revision, expectedProfileID: profileID)
                saved = session; saveError = nil
            } catch {
                // The values stay on screen, unsaved ticks shown undone; Retry saves them again.
                session = next; saveError = error.localizedDescription
            }
            refreshBests()
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

    /// The diary date the workout counts on; a past log after midnight counts for the waking day, as meals do.
    private func workoutDate() async throws -> String {
        if mode == .past { return wakingDateLabel(session.performedAt, zone: try await store.diaryHead(expectedProfileID: profileID).profile.timeZoneID) }
        return try await store.trackingDay(id: session.dayID, expectedProfileID: profileID).localDate
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
            return exercise.sets.indices.contains { isTicked(exercise: index, set: $0) && WorkoutHistory.isNewBest(exercise.sets[$0], measure: Self.measure(exercise), before: before) }
        })
    }

    /// A first set with nothing to copy: a barbell at the bar, other weights unset ("–").
    private func starter(_ exercise: WorkoutExercise) -> WorkoutSet {
        switch Self.measure(exercise) {
        case .time, .distanceTime: return WorkoutSet(repetitions: 0, seconds: 60, done: false)
        case .reps: return WorkoutSet(repetitions: 10, done: false)
        case .weightReps:
            let barbell = exercise.exerciseID.flatMap { WorkoutCatalog.exercise($0)?.barbell } == true
            return WorkoutSet(repetitions: 10, loadKg: barbell ? WeightStep.kg(fromDisplay: unit == "lb" ? 45 : 20, unit: unit) : nil, done: false)
        }
    }
}
