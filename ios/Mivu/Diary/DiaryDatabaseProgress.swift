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
        try transaction(expected: expected, maximumBytes: maximumBytes) { transaction in
            let previous = try transaction.workout(id: session.id), day = try trackingDay(id: session.dayID)
            guard previous.revision == expectedRevision else { throw DiaryError.staleRevision }
            guard session.dayID == previous.dayID, diaryDateLabel(session.performedAt, zone: day.timeZoneID) == day.localDate else { throw DiaryError.invalidData }
            var saved = session; saved.revision = previous.revision + 1; try transaction.saveWorkout(saved); return saved
        }
    }
    func deleteWorkout(id: UUID, expectedRevision: Int, expected: DiaryHead, maximumBytes: Int) throws -> DiaryCommit<Void> {
        try transaction(expected: expected, maximumBytes: maximumBytes) { try $0.deleteWorkout(id: id, revision: expectedRevision) }
    }
    func setGoals(_ goal: GoalRecord, expectedRevision: Int?, expected: DiaryHead, maximumBytes: Int) throws -> DiaryCommit<GoalRecord> {
        try transaction(expected: expected, maximumBytes: maximumBytes) { try $0.setGoal(goal, revision: expectedRevision) }
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
    func saveWorkout(_ workout: WorkoutSession) throws {
        try validateWorkoutFields(workout); _ = try database.trackingDay(id: workout.dayID)
        try saveProgress(workout, table: "workout", id: workout.id, dayID: workout.dayID)
        changes.workoutIDs.insert(workout.id); changes.dayIDs.insert(workout.dayID)
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
        if let performedAt { guard performedAt.timeIntervalSince1970.isFinite, diaryDateLabel(performedAt, zone: day.timeZoneID) == day.localDate else { throw DiaryError.invalidData } }
        let value = WorkoutSession(dayID: dayID, performedAt: try performedAt ?? diaryDateOnlyInstant(day.localDate, zone: day.timeZoneID), timePrecision: performedAt == nil ? .dateOnly : .exact, revision: 1,
            kind: draft.kind, durationMinutes: draft.durationMinutes, exercises: draft.exercises, estimatedBurnKcal: draft.estimatedBurnKcal, burnSource: draft.burnSource)
        try saveWorkout(value); return value
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
        var saved = goal; saved.revision = (previous?.revision ?? 0) + 1; try validateGoalFields(saved)
        let payload = try JSONEncoder().encode(saved)
        try database.execute("INSERT INTO goal(id, ordinal, effectiveLocalDate, payload) VALUES (?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET payload = excluded.payload",
            [.text(saved.id.uuidString), .integer(nextOrdinal("goal")), .text(saved.effectiveLocalDate), .blob(payload)])
        try contribution(table: "goal", rowID: saved.id.uuidString, encodedBytes: payload.count); return saved
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
