import Foundation
import SQLite3

extension DiaryDatabase {
    func setWeight(dayID: UUID, value: Double, unit: String = "kg", expectedRevision: Int?, expected: DiaryHead, maximumBytes: Int) throws -> DiaryCommit<WeightEntry> {
        try transaction(expected: expected, maximumBytes: maximumBytes) { try $0.setWeight(dayID: dayID, value: value, unit: unit, expectedRevision: expectedRevision) }
    }
    func updateWeight(id: UUID, value: Double, expectedRevision: Int, expected: DiaryHead, maximumBytes: Int) throws -> DiaryCommit<WeightEntry> {
        try transaction(expected: expected, maximumBytes: maximumBytes) { transaction in
            var weight = try transaction.weight(id: id)
            guard weight.revision == expectedRevision else { throw DiaryError.staleRevision }
            weight.value = value; weight.revision += 1; try transaction.saveWeight(weight); return weight
        }
    }
    func deleteWeight(id: UUID, expectedRevision: Int, expected: DiaryHead, maximumBytes: Int) throws -> DiaryCommit<Void> {
        try transaction(expected: expected, maximumBytes: maximumBytes) { try $0.deleteWeight(id: id, revision: expectedRevision) }
    }
    func createWorkout(dayID: UUID, draft: WorkoutDraft, expected: DiaryHead, maximumBytes: Int) throws -> DiaryCommit<WorkoutSession> {
        try transaction(expected: expected, maximumBytes: maximumBytes) { try $0.createWorkout(dayID: dayID, draft: draft) }
    }
    func updateWorkout(_ session: WorkoutSession, expectedRevision: Int, expected: DiaryHead, maximumBytes: Int) throws -> DiaryCommit<WorkoutSession> {
        try transaction(expected: expected, maximumBytes: maximumBytes) { try $0.updateWorkout(session, expectedRevision: expectedRevision) }
    }
    func deleteWorkout(id: UUID, expectedRevision: Int, expected: DiaryHead, maximumBytes: Int) throws -> DiaryCommit<Void> {
        try transaction(expected: expected, maximumBytes: maximumBytes) { try $0.deleteWorkout(id: id, revision: expectedRevision) }
    }
    func setGoals(_ goal: GoalRecord, expectedRevision: Int?, expected: DiaryHead, maximumBytes: Int) throws -> DiaryCommit<GoalRecord> {
        try transaction(expected: expected, maximumBytes: maximumBytes) { try $0.setGoal(goal, revision: expectedRevision) }
    }
    func saveRoutine(_ routine: WorkoutRoutine, expectedRevision: Int?, expected: DiaryHead, maximumBytes: Int) throws -> DiaryCommit<WorkoutRoutine> {
        try transaction(expected: expected, maximumBytes: maximumBytes) { try $0.saveRoutine(routine, revision: expectedRevision) }
    }
    func deleteRoutine(id: UUID, expectedRevision: Int, expected: DiaryHead, maximumBytes: Int) throws -> DiaryCommit<Void> {
        try transaction(expected: expected, maximumBytes: maximumBytes) { try $0.deleteRoutine(id: id, revision: expectedRevision) }
    }
    /// Finished workouts holding the exercise, newest first, at most `limit` (history and bests).
    func finishedWorkouts(containing key: ExerciseKey, limit: Int, expectedProfileID: UUID) throws -> [WorkoutSession] {
        try domainRead(expectedProfileID: expectedProfileID) { _ in
            // SQL matches catalog IDs; own names are folded in Swift, so SQL only narrows to exercises without an ID.
            let catalog = !key.raw.hasPrefix("own:")
            let statement = try domainStatement("SELECT id, ordinal, payload FROM workout WHERE json_extract(CAST(payload AS TEXT), '$.state') IS NOT 'active' AND EXISTS (SELECT 1 FROM json_each(CAST(payload AS TEXT), '$.exercises') WHERE json_extract(value, '$.exerciseID') \(catalog ? "= ?" : "IS NULL")) ORDER BY json_extract(CAST(payload AS TEXT), '$.performedAt') DESC, ordinal DESC, id DESC", catalog ? [.text(key.raw)] : [])
            defer { sqlite3_finalize(statement) }; var result: [WorkoutSession] = []
            while result.count < limit, try mutationStep(statement) {
                let value = try decode(WorkoutSession.self, Record(id: try mutationText(statement, 0), ordinal: Int(sqlite3_column_int64(statement, 1)), payload: try mutationBlob(statement, 2)))
                try validateWorkoutFields(value)
                if value.exercises.contains(where: { ExerciseKey($0) == key }) { result.append(value) }
            }
            return result
        }
    }
    func ownExerciseNames(expectedProfileID: UUID) throws -> [String] {
        try domainRead(expectedProfileID: expectedProfileID) { _ in
            let own = "json_extract(e.value, '$.exerciseID') IS NULL"
            let statement = try domainStatement("SELECT json_extract(e.value, '$.name') FROM workout w, json_each(CAST(w.payload AS TEXT), '$.exercises') e WHERE \(own) AND json_extract(CAST(w.payload AS TEXT), '$.state') IS NOT 'active' UNION ALL SELECT json_extract(e.value, '$.name') FROM routine r, json_each(CAST(r.payload AS TEXT), '$.exercises') e WHERE \(own)")
            defer { sqlite3_finalize(statement) }
            var seen = Set<String>(), names: [String] = []
            while try mutationStep(statement) {
                let name = try mutationText(statement, 0)
                if seen.insert(ExerciseKey(WorkoutExercise(name: name, sets: [])).raw).inserted { names.append(name) }
            }
            return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        }
    }
    func routines(expectedProfileID: UUID) throws -> [WorkoutRoutine] {
        try domainRead(expectedProfileID: expectedProfileID) { _ in
            let statement = try domainStatement("SELECT id, ordinal, payload FROM routine ORDER BY ordinal, id")
            defer { sqlite3_finalize(statement) }; var result: [WorkoutRoutine] = []
            while try mutationStep(statement) {
                let value = try decode(WorkoutRoutine.self, Record(id: try mutationText(statement, 0), ordinal: Int(sqlite3_column_int64(statement, 1)), payload: try mutationBlob(statement, 2)))
                try validateRoutineFields(value); result.append(value)
            }
            return result.sorted { left, right in
                let (a, b) = (left.lastUsedAt ?? .distantPast, right.lastUsedAt ?? .distantPast)
                return a != b ? a > b : left.name.localizedStandardCompare(right.name) == .orderedAscending
            }
        }
    }
    func updateProfile(_ profile: DiaryProfile, expectedProfile: DiaryProfile?, expected: DiaryHead, maximumBytes: Int) throws -> DiaryCommit<Void> {
        try transaction(expected: expected, maximumBytes: maximumBytes) { try $0.updateProfile(profile, expectedProfile: expectedProfile) }
    }
}

extension DiaryTransaction {
    func weight(id: UUID) throws -> WeightEntry {
        guard let row = try records("weight", clause: "id = ?", values: [.text(id.uuidString)], limit: 1).first else { throw DiaryError.notFound }
        let value = try database.decode(WeightEntry.self, row); try validateWeightFields(value)
        guard row.parent == value.dayID?.uuidString else { throw DiaryError.invalidData }; return value
    }
    func weight(on dayID: UUID) throws -> WeightEntry? {
        let rows = try records("weight", clause: "parent = ?", values: [.text(dayID.uuidString)], limit: 2)
        guard rows.count <= 1 else { throw DiaryError.invalidData }
        return try rows.first.map { row in guard let id = UUID(uuidString: row.id) else { throw DiaryError.invalidData }; return try weight(id: id) }
    }
    func workout(id: UUID) throws -> WorkoutSession {
        guard let row = try records("workout", clause: "id = ?", values: [.text(id.uuidString)], limit: 1).first else { throw DiaryError.notFound }
        let value = try database.decode(WorkoutSession.self, row); try validateWorkoutFields(value)
        guard row.parent == value.dayID.uuidString else { throw DiaryError.invalidData }; return value
    }
    func saveWeight(_ weight: WeightEntry) throws {
        try validateWeightFields(weight)
        if let id = weight.dayID { _ = try database.trackingDay(id: id) }
        try saveProgress(weight, table: "weight", id: weight.id, dayID: weight.dayID)
        changes.weightIDs.insert(weight.id); if let id = weight.dayID { changes.dayIDs.insert(id) }
    }
    func updateWorkout(_ session: WorkoutSession, expectedRevision: Int) throws -> WorkoutSession {
        let previous = try workout(id: session.id), day = try database.trackingDay(id: session.dayID)
        guard previous.revision == expectedRevision else { throw DiaryError.staleRevision }
        guard session.dayID == previous.dayID, workoutFits(session.performedAt, day: day) else { throw DiaryError.invalidData }
        var saved = session; saved.revision = previous.revision + 1
        if saved.durationSeconds == previous.durationSeconds, saved.durationMinutes != previous.durationMinutes { saved.durationSeconds = nil } // minutes edit wins over stale seconds
        return try saveWorkout(saved)
    }
    /// The running live workout, if any. shortcut: scans workout payloads; add an expression index if rows reach many thousands.
    func activeWorkout() throws -> WorkoutSession? {
        try records("workout", clause: "json_extract(CAST(payload AS TEXT), '$.state') = 'active'", values: [], limit: 1).first.map { row in
            let value = try database.decode(WorkoutSession.self, row); try validateWorkoutFields(value); return value
        }
    }
    func startWorkout(_ draft: WorkoutDraft, at: Date) throws -> WorkoutSession {
        guard try activeWorkout() == nil else { throw DiaryError.conflict }
        // The day a meal captured now would go to: the open waking day until the cutoff passes.
        let day: TrackingDay
        switch try dayAssignment(at: at) {
        case .existing(let id): day = try database.trackingDay(id: id)
        case .newDay: day = try startDay(at: at)
        }
        var live = draft; live.state = .active; live.source = .live
        return try createWorkout(dayID: day.id, draft: live, performedAt: at)
    }
    func saveActive(_ session: WorkoutSession, expectedRevision: Int, at: Date) throws -> WorkoutSession {
        guard session.state == .active, try workout(id: session.id).state == .active else { throw DiaryError.invalidData }
        var saved = session; saved.updatedAt = at
        return try updateWorkout(saved, expectedRevision: expectedRevision)
    }
    /// Keeps ticked sets, takes the duration from the start and estimates burn unless the user typed one.
    func finishWorkout(id: UUID, effort: Int?, at: Date, expectedRevision: Int) throws -> WorkoutSession {
        var session = try workout(id: id)
        guard session.revision == expectedRevision else { throw DiaryError.staleRevision }
        session.exercises = session.exercises.compactMap { exercise in
            var ticked = exercise; ticked.sets = exercise.sets.filter { $0.done == true }
            return ticked.sets.isEmpty ? nil : ticked
        }
        // No ticked sets: the caller asks to discard instead.
        guard session.state == .active, !session.exercises.isEmpty, at.timeIntervalSince1970.isFinite else { throw DiaryError.invalidData }
        let day = try database.trackingDay(id: session.dayID)
        // Clamped so a workout left running for days can still be finished, then corrected.
        let seconds = min(max(Int(at.timeIntervalSince(session.performedAt)), 1), 86_400)
        session.state = .finished; session.durationSeconds = seconds; session.effort = effort ?? session.effort; session.updatedAt = at
        if session.burnSource != .userEstimate {
            // Live workouts are gym sessions.
            session.estimatedBurnKcal = WorkoutBurn.estimate(activity: session.activity ?? "strength", seconds: seconds,
                distanceMeters: session.distanceMeters.flatMap { $0 > 0 ? $0 : nil }, effort: session.effort, bodyKg: try bodyKg(on: day.localDate, zone: day.timeZoneID))
            session.burnSource = nil
        }
        session.revision += 1
        return try saveWorkout(session)
    }
    func discardWorkout(id: UUID, expectedRevision: Int) throws {
        guard try workout(id: id).state == .active else { throw DiaryError.invalidData }
        try deleteWorkout(id: id, revision: expectedRevision)
    }
    /// Latest weigh-in on or before `localDate`: a logged one counts on its diary day (as Progress shows it), a dayless one on its `measuredAt` date.
    func bodyKg(on localDate: String, zone: String) throws -> Double? {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: zone)!
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: try diaryDateOnlyInstant(localDate, zone: zone)))!
        let date = "json_extract(CAST(d.payload AS TEXT), '$.localDate')", measured = "json_extract(CAST(w.payload AS TEXT), '$.measuredAt')"
        let statement = try database.domainStatement("SELECT * FROM (SELECT w.payload, \(date) FROM weight w JOIN day d ON d.id = w.parent WHERE \(date) <= ? ORDER BY \(date) DESC, \(measured) DESC LIMIT 1) UNION ALL SELECT * FROM (SELECT w.payload, NULL FROM weight w WHERE w.parent IS NULL AND \(measured) < ? ORDER BY \(measured) DESC LIMIT 1)",
            [.text(localDate), .real(end.timeIntervalSinceReferenceDate)])
        defer { sqlite3_finalize(statement) }; var weights: [WeightEntry] = []
        while try database.mutationStep(statement) {
            var weight = try JSONDecoder().decode(WeightEntry.self, from: database.mutationBlob(statement, 0)); try validateWeightFields(weight)
            if sqlite3_column_type(statement, 1) != SQLITE_NULL {
                let day = try database.mutationText(statement, 1)
                if diaryDateLabel(weight.measuredAt, zone: zone) != day { weight.measuredAt = try diaryDateOnlyInstant(day, zone: zone) }
            }
            weights.append(weight)
        }
        // Onboarding saves its weight as the first weigh-in, so it is already a candidate here.
        return WorkoutBurn.bodyKg(on: localDate, weights: weights, onboardingKg: nil, zone: zone)
    }
    @discardableResult func saveWorkout(_ record: WorkoutSession) throws -> WorkoutSession {
        let workout = record.syncedMinutes
        try validateWorkoutFields(workout); _ = try database.trackingDay(id: workout.dayID)
        try saveProgress(workout, table: "workout", id: workout.id, dayID: workout.dayID)
        changes.workoutIDs.insert(workout.id); changes.dayIDs.insert(workout.dayID)
        return workout
    }
    private func saveProgress<Value: Encodable>(_ value: Value, table: String, id: UUID, dayID: UUID?) throws {
        guard try database.mutationInteger("SELECT COUNT(*) FROM \(table)_tombstone WHERE id = ?", [.text(id.uuidString)]) == 0 else { throw DiaryError.notFound }
        let payload = try JSONEncoder().encode(value)
        try database.execute("INSERT INTO \(table)(id, parent, ordinal, payload) VALUES (?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET parent = excluded.parent, payload = excluded.payload",
            [.text(id.uuidString), dayID.map { .text($0.uuidString) } ?? .null, .integer(nextOrdinal(table)), .blob(payload)])
        try contribution(table: table, rowID: id.uuidString, encodedBytes: payload.count)
    }
    func setWeight(dayID: UUID, value: Double, unit: String, expectedRevision: Int?, measuredAt: Date? = nil, precision: MealTimePrecision? = nil) throws -> WeightEntry {
        let day = try database.trackingDay(id: dayID), previous = try weight(on: dayID)
        guard previous?.revision == expectedRevision else { throw DiaryError.staleRevision }
        var saved = try previous ?? WeightEntry(dayID: dayID, measuredAt: diaryDateOnlyInstant(day.localDate, zone: day.timeZoneID), value: value, unit: unit, timePrecision: .dateOnly)
        saved.value = value; saved.unit = unit
        if previous != nil { saved.revision += 1 }
        if let measuredAt { saved.measuredAt = measuredAt }
        if let precision { saved.timePrecision = precision }
        try saveWeight(saved); return saved
    }
    func createWorkout(dayID: UUID, draft: WorkoutDraft, performedAt: Date? = nil) throws -> WorkoutSession {
        let day = try database.trackingDay(id: dayID)
        if let performedAt { guard performedAt.timeIntervalSince1970.isFinite, workoutFits(performedAt, day: day) else { throw DiaryError.invalidData } }
        var value = WorkoutSession(dayID: dayID, performedAt: try performedAt ?? diaryDateOnlyInstant(day.localDate, zone: day.timeZoneID), timePrecision: performedAt == nil ? .dateOnly : .exact, revision: 1,
            kind: draft.kind, durationMinutes: draft.durationMinutes, exercises: draft.exercises)
        value.apply(draft)
        // Starting from a routine is using it; a deleted routine is simply not touched.
        if let id = draft.routineID {
            do {
                var routine = try self.routine(id: id)
                if value.performedAt > routine.lastUsedAt ?? .distantPast { routine.lastUsedAt = value.performedAt; _ = try saveRoutine(routine, revision: routine.revision) }
            } catch DiaryError.notFound {}
        }
        return try saveWorkout(value)
    }
    /// A workout's start falls on its day's date, or after midnight before the cutoff on the waking day, as late meals do.
    private func workoutFits(_ at: Date, day: TrackingDay) -> Bool {
        diaryDateLabel(at, zone: day.timeZoneID) == day.localDate || wakingDateLabel(at, zone: day.timeZoneID) == day.localDate
    }
    func exactGoal(on date: String) throws -> GoalRecord? {
        guard validLocalDate(date) else { throw DiaryError.invalidData }
        guard let row = try records("goal", clause: "effectiveLocalDate = ?", values: [.text(date)], limit: 1).first else { return nil }
        let value = try database.decode(GoalRecord.self, row); try validateGoalFields(value); return value
    }
    func setGoal(_ goal: GoalRecord, revision: Int?) throws -> GoalRecord {
        let previous = try exactGoal(on: goal.effectiveLocalDate)
        guard previous?.revision == revision, previous == nil || previous?.id == goal.id else { throw DiaryError.staleRevision }
        if previous == nil { guard try database.mutationInteger("SELECT COUNT(*) FROM goal WHERE id = ?", [.text(goal.id.uuidString)]) == 0 else { throw DiaryError.invalidData } }
        var saved = goal; saved.revision = (previous?.revision ?? 0) + 1
        // shortcut: the first goal takes a burn choice made in Settings before any goal existed; the store reads app defaults here.
        if previous == nil, saved.exerciseCreditPercent == 0, try database.mutationInteger("SELECT COUNT(*) FROM goal", []) == 0,
           let pending = UserDefaults.standard.object(forKey: GoalRecord.pendingCreditKey(head.profile.id)) as? Int, [50, 100].contains(pending) {
            saved.exerciseCreditPercent = pending
        }
        try validateGoalFields(saved)
        let payload = try JSONEncoder().encode(saved)
        try database.execute("INSERT INTO goal(id, ordinal, effectiveLocalDate, payload) VALUES (?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET payload = excluded.payload",
            [.text(saved.id.uuidString), .integer(nextOrdinal("goal")), .text(saved.effectiveLocalDate), .blob(payload)])
        try contribution(table: "goal", rowID: saved.id.uuidString, encodedBytes: payload.count); return saved
    }
    func routine(id: UUID) throws -> WorkoutRoutine {
        guard let row = try records("routine", clause: "id = ?", values: [.text(id.uuidString)], limit: 1).first else { throw DiaryError.notFound }
        let value = try database.decode(WorkoutRoutine.self, row); try validateRoutineFields(value); return value
    }
    func saveRoutine(_ routine: WorkoutRoutine, revision: Int?) throws -> WorkoutRoutine {
        guard try database.mutationInteger("SELECT COUNT(*) FROM routine_tombstone WHERE id = ?", [.text(routine.id.uuidString)]) == 0 else { throw DiaryError.notFound }
        let previous: WorkoutRoutine?
        do { previous = try self.routine(id: routine.id) } catch DiaryError.notFound { previous = nil }
        guard previous?.revision == revision else { throw DiaryError.staleRevision }
        var saved = routine; saved.revision = (previous?.revision ?? 0) + 1
        saved.name = routine.name.trimmingCharacters(in: .whitespacesAndNewlines); try validateRoutineFields(saved)
        let payload = try JSONEncoder().encode(saved)
        try database.execute("INSERT INTO routine(id, ordinal, payload) VALUES (?, ?, ?) ON CONFLICT(id) DO UPDATE SET payload = excluded.payload",
            [.text(saved.id.uuidString), .integer(nextOrdinal("routine")), .blob(payload)])
        try contribution(table: "routine", rowID: saved.id.uuidString, encodedBytes: payload.count); return saved
    }
    func deleteRoutine(id: UUID, revision: Int) throws {
        guard try routine(id: id).revision == revision else { throw DiaryError.staleRevision }
        try deleteProgress(id: id, table: "routine")
    }
    /// Edits the own exercise in every finished workout and routine; returns how many records changed.
    /// A running workout is skipped: its open screen would save its own copy over the change.
    func rewriteOwnExercise(_ key: ExerciseKey, _ edit: (inout WorkoutExercise) -> Void) throws -> Int {
        let own = "EXISTS (SELECT 1 FROM json_each(CAST(payload AS TEXT), '$.exercises') WHERE json_extract(value, '$.exerciseID') IS NULL)"
        func rewrite(_ exercises: inout [WorkoutExercise]) -> Bool {
            let matches = exercises.indices.filter { ExerciseKey(exercises[$0]) == key }
            for index in matches { edit(&exercises[index]) }
            return !matches.isEmpty
        }
        var count = 0
        for row in try records("workout", clause: own + " AND json_extract(CAST(payload AS TEXT), '$.state') IS NOT 'active'", values: []) {
            var workout = try database.decode(WorkoutSession.self, row); try validateWorkoutFields(workout)
            guard rewrite(&workout.exercises) else { continue }
            workout.revision += 1; try saveWorkout(workout); count += 1
        }
        for row in try records("routine", clause: own, values: []) {
            var routine = try database.decode(WorkoutRoutine.self, row); try validateRoutineFields(routine)
            guard rewrite(&routine.exercises) else { continue }
            _ = try saveRoutine(routine, revision: routine.revision); count += 1
        }
        return count
    }
    func updateProfile(_ profile: DiaryProfile, expectedProfile: DiaryProfile?) throws {
        guard profile.id == head.profile.id else { throw DiaryError.wrongOwner }
        guard expectedProfile == nil || expectedProfile == head.profile else { throw DiaryError.staleRevision }
        if profile.timeZoneID != head.profile.timeZoneID { head.previousDayConfirmedAt = nil }
        head.profile = profile
    }
    func deleteWeight(id: UUID, revision: Int) throws {
        let value = try weight(id: id); guard value.revision == revision else { throw DiaryError.staleRevision }
        try deleteProgress(id: id, table: "weight"); changes.weightIDs.insert(id)
        if let day = value.dayID { changes.dayIDs.insert(day) }
    }
    func deleteWorkout(id: UUID, revision: Int) throws {
        let value = try workout(id: id); guard value.revision == revision else { throw DiaryError.staleRevision }
        let turns = try ids("SELECT turnID FROM record_source WHERE kind = 'workout' AND recordID = ?", [.text(id.uuidString)])
        try deleteProgress(id: id, table: "workout"); changes.workoutIDs.insert(id); changes.dayIDs.insert(value.dayID)
        for id in turns {
            guard let turn = try turn(id: id) else { throw DiaryError.invalidData }
            let pending = try turn.pendingMealID.map { try database.mutationInteger("SELECT COUNT(*) FROM meal WHERE id = ?", [.text($0.uuidString)]) > 0 } ?? false
            var surviving = try pending || hasSurvivingProgress(turn)
            if try database.mutationInteger("SELECT EXISTS(SELECT 1 FROM record_source r JOIN meal m ON m.id = r.recordID WHERE r.kind = 'meal' AND r.turnID = ?)", [.text(turn.id.uuidString)]) == 1 { surviving = true }
            for receipt in turn.receipts {
                if let meal = receipt.mealID, try database.mutationInteger("SELECT COUNT(*) FROM meal WHERE id = ?", [.text(meal.uuidString)]) > 0 { surviving = true }
            }
            if !surviving {
                let photos = try photoReferences(owner: .coachTurn(id))
                for photo in photos { try removePhoto(photoID: photo.photoID, owner: .coachTurn(id)); try stripUnusedPhotoID(photo.photoID, turnID: id) }
            }
        }
    }
    private func deleteProgress(id: UUID, table: String) throws {
        try removeContribution(table: table, rowID: id.uuidString)
        try database.execute("DELETE FROM \(table) WHERE id = ?", [.text(id.uuidString)])
        try database.execute("DELETE FROM record_source WHERE kind = ? AND recordID = ?", [.text(table), .text(id.uuidString)])
        let payload = try JSONEncoder().encode(id)
        try database.execute("INSERT INTO \(table)_tombstone(id, ordinal, payload) VALUES (?, ?, ?)", [.text(id.uuidString), .integer(nextOrdinal(table + "_tombstone")), .blob(payload)])
        try contribution(table: table + "_tombstone", rowID: id.uuidString, encodedBytes: payload.count)
    }
}

func diaryDateOnlyInstant(_ date: String, zone: String) throws -> Date {
    guard validLocalDate(date), TimeZone(identifier: zone) != nil else { throw DiaryError.invalidData }
    let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = TimeZone(identifier: zone); formatter.dateFormat = "yyyy-MM-dd HH:mm"; formatter.isLenient = false
    guard let value = formatter.date(from: date + " 12:00") else { throw DiaryError.invalidData }; return value
}
