import Foundation
import Observation

/// `.live` runs a clock and saves every change; `.past` (a workout logged afterwards) and `.edit` save once on Done.
enum LiveWorkoutMode: Equatable { case live, past, edit }

/// Lifting shows in the person's unit; storage is always kg.
enum WeightStep {
    static let defaultPlatesKg: [Double] = [25, 20, 15, 10, 5, 2.5, 1.25]
    static let defaultPlatesLb: [Double] = [45, 35, 25, 10, 5, 2.5]
    /// Settings › Bar and plates: plates as a JSON array in their own unit; the bar always in kg.
    static let platesKgKey = "workoutPlatesKg", platesLbKey = "workoutPlatesLb", barKey = "workoutBarKg"

    /// The person's plates in the unit, else the defaults. Every plate must be above zero: a zero plate would make the step zero.
    static func plates(unit: String, defaults: UserDefaults = .standard) -> [Double] {
        let stored = defaults.string(forKey: unit == "lb" ? platesLbKey : platesKgKey)
            .flatMap { try? JSONDecoder().decode([Double].self, from: Data($0.utf8)) } ?? []
        guard !stored.isEmpty, stored.allSatisfy({ $0.isFinite && $0 > 0 }) else { return unit == "lb" ? defaultPlatesLb : defaultPlatesKg }
        return stored
    }

    /// The bars Settings offers in each unit.
    static func bars(unit: String) -> [Double] { unit == "lb" ? [45, 35, 25] : [20, 15, 10] }

    /// The person's bar in the shown unit, else 20 kg / 45 lb. Snapped to the unit's nearest bar,
    /// so a 45 lb bar reads 20 kg after switching units, not 20.41.
    static func bar(unit: String, defaults: UserDefaults = .standard) -> Double {
        let kg = defaults.double(forKey: barKey), shown = display(kg: kg, unit: unit)
        guard kg.isFinite, kg > 0 else { return bars(unit: unit)[0] }
        return bars(unit: unit).min { abs($0 - shown) < abs($1 - shown) }!
    }

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
    /// The set to lift next after a tick; in a superset it moves to the next exercise of the round.
    var focus: (exercise: Int, set: Int)?
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
    /// Editing: a burn the person typed; nil uses the estimate.
    var typedKcal: Double?
    private var bodyKg: Double?
    @ObservationIgnored private let store: DiaryStore
    @ObservationIgnored private let profileID: UUID
    /// The last copy the store holds; while a save fails, ticks it lacks are not shown done.
    private var saved: WorkoutSession
    @ObservationIgnored private var history: [ExerciseKey: [WorkoutSession]] = [:]
    @ObservationIgnored private var pending: Task<Void, Never>?
    /// Edits not yet saved, in order, replayed onto the stored copy if Pip changed it meanwhile.
    @ObservationIgnored private var unsaved: [(inout WorkoutSession) -> Void] = []
    @ObservationIgnored private let rest: RestTimer?
    /// Told once a live or past workout is saved finished, with its owner, for Pip.
    @ObservationIgnored private let onSaved: (WorkoutSession, UUID) -> Void

    init(store: DiaryStore, profileID: UUID, session: WorkoutSession, unit: String, mode: LiveWorkoutMode, rest: RestTimer? = nil,
         onSaved: @escaping (WorkoutSession, UUID) -> Void = { _, _ in }) {
        self.store = store; self.profileID = profileID; self.unit = unit; self.mode = mode
        self.onSaved = onSaved
        self.rest = mode == .live ? rest : nil
        var session = session
        if mode == .edit {
            // A saved set was lifted: older ones without a tick show ticked.
            for e in session.exercises.indices { for s in session.exercises[e].sets.indices where session.exercises[e].sets[s].done == nil { session.exercises[e].sets[s].done = true } }
        }
        self.session = session; saved = session
        // The first exercise with an unticked set, else the last one.
        expandedExercise = session.exercises.firstIndex { $0.sets.contains { $0.done != true } } ?? max(session.exercises.count - 1, 0)
        // An edit's time starts at the stored one.
        if mode == .edit {
            typedMinutes = Double(session.durationSeconds ?? session.durationMinutes * 60) / 60
            typedKcal = session.burnSource == .userEstimate ? session.estimatedBurnKcal : nil
        }
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
        guard done, isTicked(exercise: exercise, set: set) else { return }
        let next = nextFocus(after: (exercise, set))
        focus = next
        // In a superset the rest waits for the last exercise of the round.
        let block = WorkoutSession.block(of: exercise, in: session.exercises)
        if block.count > 1, block.contains(next.exercise), next.set == set, next != (exercise, set) { return }
        guard let rest else { return }
        let label = next == (exercise, set) ? "" : WorkoutSession.setLabel(name: session.exercises[next.exercise].name, set: next.set + 1)
        await rest.start(seconds: rest.seconds(for: session.exercises[exercise]), next: label, workout: session)
    }

    /// The first unticked set after this one in lifting order (a superset round by round), else the first unticked anywhere.
    func nextFocus(after current: (exercise: Int, set: Int)) -> (exercise: Int, set: Int) {
        let order = session.liftingOrder
        let open = { (position: (exercise: Int, set: Int)) in position != current && !self.isTicked(exercise: position.exercise, set: position.set) }
        let after = (order.firstIndex { $0 == current } ?? -1) + 1
        return order[after...].first(where: open) ?? order.first(where: open) ?? current
    }


    /// "Round 2 of 3": the first round with an unticked set, and the most sets any member has.
    func round(of block: Range<Int>) -> (current: Int, total: Int) {
        let total = block.map { session.exercises[$0].sets.count }.max() ?? 0
        let open = (0..<total).first { round in block.contains { session.exercises[$0].sets.indices.contains(round) && !isTicked(exercise: $0, set: round) } }
        return ((open ?? total - 1) + 1, total)
    }

    /// One superset (a circuit from three) joining the first exercise's group if it has one; members move next to it.
    func group(_ exercises: [Int]) async {
        guard let first = exercises.first else { return }
        var order: [Int]?
        await change(first) { session in
            guard exercises.allSatisfy(session.exercises.indices.contains) else { return }
            let id = session.exercises[first].groupID ?? UUID()
            for index in exercises { session.exercises[index].groupID = id }
            let members = session.exercises.indices.filter { session.exercises[$0].groupID == id }, others = session.exercises.indices.filter { !members.contains($0) }
            order = others.filter { $0 < members[0] } + members + others.filter { $0 > members[0] }
            Self.reorder(&session, order!)
        }
        follow(order)
    }

    /// Takes the exercise out of its superset and puts it just after the others.
    func ungroup(exercise: Int) async {
        var order: [Int]?
        await change(exercise) { session in
            let block = WorkoutSession.block(of: exercise, in: session.exercises), indices = Array(session.exercises.indices)
            session.exercises[exercise].groupID = nil
            order = indices[..<block.lowerBound] + block.filter { $0 != exercise } + [exercise] + indices[block.upperBound...]
            Self.reorder(&session, order!)
        }
        follow(order)
    }

    /// One place up or down. Inside a superset it swaps with a neighbour or, at the edge, steps out of it;
    /// otherwise it moves past the whole neighbouring superset.
    func moveExercise(_ index: Int, up: Bool) async {
        var moved: [Int]?
        await change(index) { session in
            let block = WorkoutSession.block(of: index, in: session.exercises)
            var order = Array(session.exercises.indices)
            if block.count > 1 {
                if up ? index > block.lowerBound : index < block.upperBound - 1 { order.swapAt(index, up ? index - 1 : index + 1) }
                else { session.exercises[index].groupID = nil }
            } else {
                guard up ? index > 0 : index < session.exercises.count - 1 else { return }
                let neighbour = WorkoutSession.block(of: up ? index - 1 : index + 1, in: session.exercises)
                order.remove(at: index)
                order.insert(index, at: up ? neighbour.lowerBound : neighbour.upperBound - 1)
            }
            Self.reorder(&session, order)
            moved = order
        }
        follow(moved)
    }

    /// Swaps an exercise with nothing ticked for another, filled like a new one; it keeps its superset and rest.
    func replaceExercise(_ index: Int, with exercise: WorkoutExercise) async {
        await loadHistory(exercise)
        let replacement = prefilled(exercise)
        await change(index) { session in
            let old = session.exercises[index]
            guard !old.sets.contains(where: { $0.done == true }) else { return }
            var new = replacement; new.groupID = old.groupID; new.restSeconds = old.restSeconds
            session.exercises[index] = new
        }
    }

    func removeExercise(_ index: Int) async {
        var removed = false
        await change(index) { session in
            session.exercises.remove(at: index)
            Self.normalizeGroups(&session.exercises)
            removed = true
        }
        // Applied once the removal is on screen: the open card stays on its exercise, or hands over to the one above at the end.
        if removed, expandedExercise > index || expandedExercise == session.exercises.count { expandedExercise = max(expandedExercise - 1, 0) }
        focus = nil
    }

    /// Warm-up, drop set or to failure; `.normal` clears it.
    func setType(_ type: WorkoutSetType, exercise: Int, set: Int) async {
        await change(exercise, set) { $0.exercises[exercise].sets[set].type = type == .normal ? nil : type }
    }

    /// "How hard?" 1–10, or nil to clear.
    func setEffort(_ effort: Int?, exercise: Int, set: Int) async {
        await change(exercise, set) { $0.exercises[exercise].sets[set].effort = effort.map { min(max($0, 1), 10) } }
    }

    /// The rest after this exercise, shared by its whole superset; nil uses the default.
    func setRest(_ seconds: Int?, exercise: Int) async {
        await change(exercise) { session in
            for member in WorkoutSession.block(of: exercise, in: session.exercises) { session.exercises[member].restSeconds = seconds }
        }
    }

    func setNote(_ note: String, exercise: Int) async {
        let trimmed = String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2_000))
        await change(exercise) { $0.exercises[exercise].note = trimmed.isEmpty ? nil : trimmed }
    }

    /// Applies a new order of exercises and keeps every superset whole.
    private static func reorder(_ session: inout WorkoutSession, _ order: [Int]) {
        session.exercises = order.map { session.exercises[$0] }
        normalizeGroups(&session.exercises)
    }

    /// After an edit has been applied (and saved, when live), the open card follows its exercise and focus resets.
    private func follow(_ order: [Int]?) {
        if let order { expandedExercise = order.firstIndex(of: expandedExercise) ?? expandedExercise }
        focus = nil
    }

    /// A superset is a run of neighbours sharing a group: a run of one is no superset, and a run split
    /// off from an earlier one (an exercise taken from its middle) becomes its own superset.
    private static func normalizeGroups(_ exercises: inout [WorkoutExercise]) {
        var seen = Set<UUID>(), index = 0
        while index < exercises.count {
            let run = WorkoutSession.block(of: index, in: exercises)
            if let id = exercises[index].groupID {
                if run.count == 1 { exercises[index].groupID = nil }
                else if !seen.insert(id).inserted { let fresh = UUID(); for member in run { exercises[member].groupID = fresh } }
            }
            index = run.upperBound
        }
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
        let added = prefilled(exercise)
        await change { $0.exercises.append(added) }
        expandedExercise = session.exercises.count - 1
    }

    private func prefilled(_ exercise: WorkoutExercise) -> WorkoutExercise {
        var added = exercise
        if added.sets.isEmpty {
            let last = history[ExerciseKey(exercise)]?.first?.exercises.filter { ExerciseKey($0) == ExerciseKey(exercise) }
                .flatMap(\.sets).filter { $0.done != false } ?? []
            added.sets = last.isEmpty ? [starter(exercise)] : last.map { var set = $0; set.done = false; set.effort = nil; return set }
        }
        return added
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
        focus = nil
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

    /// An edit differs from the saved workout.
    var editChanged: Bool {
        session != saved || seconds != storedSeconds || typedKcal != (saved.burnSource == .userEstimate ? saved.estimatedBurnKcal : nil)
    }

    private var storedSeconds: Int { saved.durationSeconds ?? saved.durationMinutes * 60 }
    /// What an edit stores: an untouched time as it was (even under a minute), a changed one at least a minute.
    private var editSeconds: Int { seconds == storedSeconds ? seconds : max(seconds, 60) }

    /// The burn an edit saves: a typed number; else a fresh estimate once the time, effort or day changed or a typed
    /// number was cleared (the old number when there is no body weight to estimate with); else the stored one.
    func editBurn(bodyKg: Double?, dayChanged: Bool) -> Double? {
        if let typedKcal { return typedKcal }
        let wasTyped = saved.burnSource == .userEstimate
        guard wasTyped || editSeconds != storedSeconds || session.effort != saved.effort || dayChanged else { return saved.estimatedBurnKcal }
        return WorkoutBurn.estimate(activity: session.activity ?? "strength", seconds: editSeconds, distanceMeters: nil, effort: session.effort, bodyKg: bodyKg)
            ?? (wasTyped ? nil : saved.estimatedBurnKcal)
    }

    /// The burn the edit screen shows, as Save will store it on this day.
    var editKcal: Double? { editBurn(bodyKg: bodyKg, dayChanged: session.performedAt != saved.performedAt) }

    /// A past log has no clock: three minutes a set until the person corrects it.
    var pastMinutes: Double {
        get { typedMinutes ?? Double(max(session.exercises.reduce(0) { $0 + $1.sets.filter { $0.done == true }.count }, 1) * 3) }
        set { typedMinutes = newValue }
    }

    /// How long the workout took, as Save will store it.
    var seconds: Int {
        mode == .live ? min(max(Int(endedAt.timeIntervalSince(session.performedAt)), 1), 86_400) : Int((pastMinutes * 60).rounded())
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
                if saveError != nil { session = try await saveRecovering(session); saved = session }
                do { session = try await store.finishWorkout(id: session.id, effort: effort, at: now, expectedRevision: session.revision, expectedProfileID: profileID) }
                catch DiaryError.staleRevision {
                    // Pip added to it meanwhile; every screen change is saved, so the stored copy holds both.
                    let stored = try await storedActive()
                    session = try await store.finishWorkout(id: stored.id, effort: effort, at: now, expectedRevision: stored.revision, expectedProfileID: profileID)
                }
                onSaved(session, profileID)
            case .past:
                let date = try await workoutDate()
                let exercises = tickedExercises
                let seconds = max(seconds, 60)
                let bodyKg = try await store.bodyKg(on: date, expectedProfileID: profileID)
                let draft = WorkoutDraft(kind: .strength, durationMinutes: seconds / 60, exercises: exercises,
                    estimatedBurnKcal: WorkoutBurn.estimate(activity: session.activity ?? "strength", seconds: seconds, distanceMeters: nil, effort: effort, bodyKg: bodyKg),
                    title: session.title, activity: session.activity ?? "strength", state: .finished, durationSeconds: seconds,
                    effort: effort, routineID: session.routineID, source: .manual)
                session = try await store.createWorkout(localDate: date, draft: draft, performedAt: session.performedAt, expectedProfileID: profileID)
                onSaved(session, profileID)
            case .edit:
                var edited = session
                edited.exercises = tickedExercises
                edited.durationSeconds = editSeconds
                let note = String((edited.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(2_000))
                edited.note = note.isEmpty ? nil : note
                // A moved start is an exact time and files the workout under that start's waking day, as a past log does;
                // its burn is estimated with that day's body weight.
                var date: String?, dayKg = bodyKg
                if edited.performedAt != saved.performedAt {
                    edited.timePrecision = .exact
                    let moved = wakingDateLabel(edited.performedAt, zone: try await store.diaryHead(expectedProfileID: profileID).profile.timeZoneID)
                    date = moved
                    dayKg = try await store.bodyKg(on: moved, expectedProfileID: profileID)
                }
                edited.estimatedBurnKcal = editBurn(bodyKg: dayKg, dayChanged: date != nil)
                edited.burnSource = edited.estimatedBurnKcal == nil ? nil : typedKcal != nil ? .userEstimate : saved.burnSource == .userEstimate ? nil : saved.burnSource
                session = try await store.updateWorkout(edited, onDate: date, expectedRevision: session.revision, expectedProfileID: profileID)
            }
            saveError = nil
            return true
        } catch { saveError = error.localizedDescription; return false }
    }

    private var tickedExercises: [WorkoutExercise] {
        session.exercises.compactMap { exercise in
            var ticked = exercise; ticked.sets = exercise.sets.filter { $0.done == true }; return ticked.sets.isEmpty ? nil : ticked
        }
    }

    func discard() async -> Bool {
        await pending?.value
        guard mode == .live else { return true }
        do {
            do { try await store.discardWorkout(id: session.id, expectedRevision: session.revision, expectedProfileID: profileID) }
            catch DiaryError.staleRevision { try await store.discardWorkout(id: session.id, expectedRevision: try await storedActive().revision, expectedProfileID: profileID) }
            return true
        } catch { saveError = error.localizedDescription; return false }
    }

    /// Applies one edit after the previous one is saved, so quick taps never save over each other.
    private func change(_ edit: @escaping (inout WorkoutSession) -> Void) async {
        let previous = pending
        let task = Task { [self] in
            await previous?.value
            var next = session; edit(&next)
            guard mode == .live else { session = next; refreshBests(); return }
            unsaved.append(edit)
            do {
                session = try await saveRecovering(next)
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

    /// Saves the screen's copy. If Pip changed the running workout meanwhile, every unsaved edit is
    /// replayed in order onto the stored copy, so Pip's change and the screen's all stay.
    private func saveRecovering(_ next: WorkoutSession) async throws -> WorkoutSession {
        let result: WorkoutSession
        do { result = try await store.saveActive(next, expectedRevision: next.revision, expectedProfileID: profileID) }
        catch DiaryError.staleRevision {
            var stored = try await storedActive()
            for edit in unsaved { edit(&stored) }
            result = try await store.saveActive(stored, expectedRevision: stored.revision, expectedProfileID: profileID)
        }
        unsaved = []
        return result
    }

    private func storedActive() async throws -> WorkoutSession {
        guard let stored = try await store.activeWorkout(expectedProfileID: profileID), stored.id == session.id else { throw DiaryError.staleRevision }
        return stored
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
