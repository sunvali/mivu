import Foundation
import CoreFoundation
import CryptoKit

/// A Coach workout write before it meets the stored record: nil keeps the stored value,
/// an empty title, note or group clears it. A log applies its exercises to an empty list.
struct WorkoutPatch: Codable, Equatable, Sendable {
    struct Exercise: Codable, Equatable, Sendable {
        var name: String
        var exerciseID: String? = nil
        var group: String? = nil
        var restSeconds: Int? = nil
        var note: String? = nil
        var sets: [WorkoutSet]
    }
    var localDate: String? = nil
    var kind: WorkoutKind? = nil
    var activity: String? = nil
    var title: String? = nil
    var durationMinutes: Int? = nil
    var durationSeconds: Int? = nil
    var distanceMeters: Double? = nil
    var avgHeartRate: Int? = nil
    var effort: Int? = nil
    var indoor: Bool? = nil
    var note: String? = nil
    /// A burn the person said; without one Mivu estimates it.
    var userBurnKcal: Double? = nil
    var exercises: [Exercise]? = nil

    /// The stored workout with this edit; the day move and burn are the caller's.
    func applied(to stored: WorkoutSession) throws -> WorkoutSession {
        var result = stored
        if let activity { result.activity = activity; result.kind = activity == "strength" ? .strength : .cardio }
        if let kind { result.kind = kind }
        if let title { result.title = title.isEmpty ? nil : title }
        if let note { result.note = note.isEmpty ? nil : note }
        if let durationSeconds { result.durationSeconds = durationSeconds }
        else if let durationMinutes { result.durationMinutes = durationMinutes; result.durationSeconds = nil }
        if let distanceMeters { result.distanceMeters = distanceMeters > 0 ? distanceMeters : nil }
        if let avgHeartRate { result.avgHeartRate = avgHeartRate }
        if let effort { result.effort = effort }
        if let indoor { result.indoor = indoor }
        if let exercises { result.exercises = try Self.merged(exercises, into: stored.exercises) }
        return result
    }

    /// The exercises as listed. Each keeps what the call leaves out from the same stored exercise (at its
    /// position, else the first unused one like it); others resolve to the catalog or stay the person's own.
    static func merged(_ rows: [Exercise], into stored: [WorkoutExercise]) throws -> [WorkoutExercise] {
        func key(_ id: String?, _ name: String) -> String { id ?? WorkoutCatalog.resolve(name)?.id ?? "own:" + WorkoutCatalog.normalized(name) }
        var unused = Array(stored.indices)
        var result = rows.enumerated().map { index, row -> WorkoutExercise in
            let wanted = key(row.exerciseID, row.name)
            let match = unused.contains(index) && key(stored[index].exerciseID, stored[index].name) == wanted
                ? index : unused.first { key(stored[$0].exerciseID, stored[$0].name) == wanted }
            var exercise: WorkoutExercise
            let resolved = row.exerciseID.flatMap(WorkoutCatalog.exercise) ?? WorkoutCatalog.resolve(row.name)
            if let match {
                unused.removeAll { $0 == match }; exercise = stored[match]
                // An older record named in words joins its catalog exercise, so its history no longer splits.
                if exercise.exerciseID == nil, let catalog = resolved { exercise.name = catalog.name; exercise.exerciseID = catalog.id; exercise.measure = catalog.measure }
            } else if let catalog = resolved {
                exercise = WorkoutExercise(name: catalog.name, sets: [], exerciseID: catalog.id, measure: catalog.measure)
            } else { exercise = WorkoutExercise(name: row.name, sets: []) }
            let old = exercise.sets
            exercise.sets = row.sets.enumerated().map { $1.merged(onto: old.indices.contains($0) ? old[$0] : nil) }
            if let group = row.group { exercise.groupID = group.isEmpty ? nil : UUID(uuidString: group) ?? groupID(group) }
            if let rest = row.restSeconds { exercise.restSeconds = rest }
            if let note = row.note { exercise.note = note.isEmpty ? nil : note }
            return exercise
        }
        // A superset is neighbours sharing a group: a lone member leaves it, one split apart is refused.
        var seen = Set<UUID>(), index = 0
        while index < result.count {
            let run = WorkoutSession.block(of: index, in: result)
            if let id = result[index].groupID {
                guard seen.insert(id).inserted else { throw CoachError.invalidArguments }
                if run.count == 1 { result[index].groupID = nil }
            }
            index = run.upperBound
        }
        return result
    }

    /// The same label always names the same group, so a retried call writes the same record.
    private static func groupID(_ label: String) -> UUID {
        Array(SHA256.hash(data: Data(("mivu.workout.group/" + label).utf8)).prefix(16)).withUnsafeBytes { UUID(uuid: $0.loadUnaligned(as: uuid_t.self)) }
    }
}

extension WorkoutSet {
    /// A listed set is the whole set, so removing a warm-up never shifts its type onto the next one;
    /// only the ticked state, which calls never carry, comes from the stored set at its position.
    func merged(onto stored: WorkoutSet?) -> WorkoutSet {
        var result = self
        if result.type == .normal { result.type = nil }
        if result.done == nil { result.done = stored?.done }
        return result
    }
}

extension CoachTools {
    static func workoutSchemas(string: [String: Any], integer: [String: Any], number: [String: Any], unconfirmedTime: [String: Any]) -> [(String, String, [String: Any])] {
        let boolean: [String: Any] = ["type": "boolean"]
        let set = object(["repetitions": integer, "load_kg": number, "type": ["type": "string", "enum": ["normal", "warmup", "drop", "failure"]],
                          "effort": ["type": "integer", "description": "How hard, 1-10"], "seconds": integer, "distance_meters": number], required: ["repetitions", "load_kg"])
        let sets: [String: Any] = ["type": "array", "items": set]
        let exercise = object(["name": string, "sets": sets, "exercise_id": string, "rest_seconds": integer, "note": string,
            "group": ["type": "string", "description": "Same label on neighbouring exercises makes a superset; a retrieved groupID keeps one; empty leaves it"]], required: ["name", "sets"])
        let workout: [String: Any] = ["kind": ["type": "string", "enum": ["strength", "cardio", "other"]],
            "activity": ["type": "string", "enum": WorkoutCatalog.activities.map(\.id)], "title": string, "note": string,
            "duration_minutes": integer, "duration_seconds": integer, "distance_meters": number, "avg_heart_rate": integer, "indoor": boolean,
            "effort": ["type": "integer", "description": "How hard, 1-10: easy 3, moderate 5, hard 7, max 9"],
            "exercises": ["type": "array", "items": exercise], "estimated_burn_kcal": number,
            "burn_source": ["type": ["string", "null"], "enum": ["userEstimate", "modelEstimate", NSNull()]], "performed_at": unconfirmedTime]
        return [
            ("get_workout", "Read a complete owned finished workout before editing it. Oversized records are refused; never replace unseen sets.", object(["workout_id": string], required: ["workout_id"])),
            ("log_workout", "Log one finished workout per turn/date; another session needs another turn. Exercise names resolve to the catalog; unknown names become the user's own exercises. Set activity. Pass estimated_burn_kcal only for a number the user said, with burn_source userEstimate; otherwise Mivu estimates burn. Timestamps are unconfirmed date-only. While context.activeWorkout exists, use add_to_workout for what the user is doing now.",
             object(workout.merging(["local_date": string]) { _, new in new }, required: ["local_date", "kind", "duration_minutes", "exercises"])),
            ("edit_workout", "Edit a retrieved finished workout using its real ID/revision. Only listed fields change; null keeps the stored value; an empty title, note or exercise note clears it. local_date moves it to that date. exercises, when listed, is the complete new list in order, used to add, remove, move or replace exercises; a listed exercise keeps unlisted fields of the stored one with the same name. Each listed set is complete: send all its fields as retrieved, since null means none.",
             object(workout.merging(["workout_id": string, "expected_revision": integer, "local_date": string]) { _, new in new }, required: ["workout_id", "expected_revision"])),
            ("add_to_workout", "Add sets the user just did to the running workout in context.activeWorkout: they join that exercise, or the exercise is added. Empty sets adds a new exercise with last time's sets still to do. One call per exercise per turn.",
             object(["exercise": string, "sets": sets], required: ["exercise", "sets"])),
            ("get_exercise_history", "Read the user's finished sessions of one exercise, newest first (limit 1-10), with bests across them. For questions; answer in one line.",
             object(["exercise": string, "limit": integer], required: ["exercise", "limit"])),
            ("start_routine", "Show one of context.routines as a card with a Start button; the user taps Start. It starts nothing itself.",
             object(["routine_id": string], required: ["routine_id"])),
        ]
    }

    static func optionalValue(_ row: [String: Any], _ key: String) -> Any? { row[key].flatMap { $0 is NSNull ? nil : $0 } }
    static func optionalInteger(_ row: [String: Any], _ key: String, _ range: ClosedRange<Int>) throws -> Int? {
        guard let raw = optionalValue(row, key) else { return nil }
        guard let value = number(raw), value.rounded() == value, value >= Double(range.lowerBound), value <= Double(range.upperBound) else { throw CoachError.invalidArguments }
        return Int(value)
    }
    static func optionalNumber(_ row: [String: Any], _ key: String, _ range: ClosedRange<Double>) throws -> Double? {
        guard let raw = optionalValue(row, key) else { return nil }
        guard let value = number(raw), range.contains(value) else { throw CoachError.invalidArguments }
        return value
    }
    /// Trimmed; empty stays empty, which clears a field on edit.
    static func optionalText(_ row: [String: Any], _ key: String, _ maximum: Int) throws -> String? {
        guard let raw = optionalValue(row, key) else { return nil }
        guard let text = raw as? String, text.count <= maximum else { throw CoachError.invalidArguments }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func workoutSets(_ raw: Any?, done: Bool?) throws -> [WorkoutSet] {
        guard let rows = raw as? [[String: Any]], rows.count <= 100 else { throw CoachError.invalidArguments }
        return try rows.map { row in
            guard Set(row.keys).isSubset(of: ["repetitions", "load_kg", "type", "effort", "seconds", "distance_meters"]),
                  let reps = try optionalInteger(row, "repetitions", 0...10_000) else { throw CoachError.invalidArguments }
            var set = WorkoutSet(repetitions: reps, loadKg: try optionalNumber(row, "load_kg", 0...100_000), effort: try optionalInteger(row, "effort", 1...10),
                                 seconds: try optionalInteger(row, "seconds", 0...86_400), distanceMeters: try optionalNumber(row, "distance_meters", 0...1_000_000), done: done)
            if let raw = optionalValue(row, "type") { guard let type = (raw as? String).flatMap(WorkoutSetType.init) else { throw CoachError.invalidArguments }; set.type = type }
            return set
        }
    }

    static func workoutPatch(_ args: [String: Any]) throws -> WorkoutPatch {
        var patch = WorkoutPatch()
        if let raw = optionalValue(args, "kind") { guard let kind = (raw as? String).flatMap(WorkoutKind.init) else { throw CoachError.invalidArguments }; patch.kind = kind }
        if let activity = try optionalText(args, "activity", 200) { guard WorkoutCatalog.activity(activity) != nil else { throw CoachError.invalidArguments }; patch.activity = activity }
        if let date = try optionalText(args, "local_date", 10) { guard validLocalDate(date) else { throw CoachError.invalidArguments }; patch.localDate = date }
        patch.title = try optionalText(args, "title", 200)
        patch.note = try optionalText(args, "note", 2_000)
        patch.durationMinutes = try optionalInteger(args, "duration_minutes", 1...1440)
        patch.durationSeconds = try optionalInteger(args, "duration_seconds", 1...86_400)
        patch.distanceMeters = try optionalNumber(args, "distance_meters", 0...1_000_000)
        patch.avgHeartRate = try optionalInteger(args, "avg_heart_rate", 20...250)
        patch.effort = try optionalInteger(args, "effort", 1...10)
        if let raw = optionalValue(args, "indoor") {
            guard let value = raw as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() else { throw CoachError.invalidArguments }; patch.indoor = value.boolValue
        }
        let burn = try optionalNumber(args, "estimated_burn_kcal", 0...100_000)
        if let raw = optionalValue(args, "burn_source") {
            guard let source = (raw as? String).flatMap(WorkoutBurnSource.init) else { throw CoachError.invalidArguments }
            // Only a number the person said is kept; the model never supplies burn.
            if source == .userEstimate { patch.userBurnKcal = burn }
        }
        if let raw = optionalValue(args, "exercises") {
            guard let rows = raw as? [[String: Any]], rows.count <= 100 else { throw CoachError.invalidArguments }
            patch.exercises = try rows.map { row in
                guard Set(row.keys).isSubset(of: ["name", "exercise_id", "group", "rest_seconds", "note", "sets"]),
                      let name = try optionalText(row, "name", 200), !name.isEmpty else { throw CoachError.invalidArguments }
                var exercise = WorkoutPatch.Exercise(name: name, sets: try workoutSets(row["sets"], done: nil))
                if let id = try optionalText(row, "exercise_id", 200), !id.isEmpty {
                    guard WorkoutCatalog.exercise(id) != nil else { throw CoachError.invalidArguments }; exercise.exerciseID = id
                }
                exercise.group = try optionalText(row, "group", 100)
                exercise.restSeconds = try optionalInteger(row, "rest_seconds", 0...86_400)
                exercise.note = try optionalText(row, "note", 2_000)
                return exercise
            }
        }
        return patch
    }

    /// A new finished workout from a log call; Mivu fills its burn unless the person said one.
    static func workoutDraft(_ patch: WorkoutPatch) throws -> WorkoutDraft {
        guard let kind = patch.kind, let minutes = patch.durationMinutes, let rows = patch.exercises else { throw CoachError.invalidArguments }
        return WorkoutDraft(kind: kind, durationMinutes: minutes, exercises: try WorkoutPatch.merged(rows, into: []),
            estimatedBurnKcal: patch.userBurnKcal, burnSource: patch.userBurnKcal == nil ? nil : .userEstimate, title: patch.title,
            activity: patch.activity, durationSeconds: patch.durationSeconds, distanceMeters: patch.distanceMeters.flatMap { $0 > 0 ? $0 : nil },
            avgHeartRate: patch.avgHeartRate, effort: patch.effort, indoor: patch.indoor, note: patch.note, source: .coach)
    }
}
