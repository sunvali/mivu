import Foundation

enum WorkoutCSVFormat { case strong, hevy }

/// One workout read from another app's export, before it is stored.
struct ImportedWorkout: Equatable {
    let startedAt: Date
    let draft: WorkoutDraft
    let externalID: String
}

/// Strong and Hevy CSV exports in, a Hevy-like CSV out (one row per set). Local times read in the profile's zone.
enum WorkoutCSV {
    static func detect(header: String) -> WorkoutCSVFormat? {
        if header.contains("Workout Name"), header.contains("Exercise Name") { return .strong }
        if header.contains("exercise_title"), header.contains("start_time") { return .hevy }
        return nil
    }

    /// Workouts whose rows don't read cleanly are skipped and counted; a header without the needed columns throws.
    static func parse(_ text: String, format: WorkoutCSVFormat, defaultUnit: String, zone: TimeZone = .current) throws -> (workouts: [ImportedWorkout], skipped: Int) {
        let headerLine = text.prefix { $0 != "\n" && $0 != "\r" }
        let delimiter: Character = headerLine.filter { $0 == ";" }.count > headerLine.filter { $0 == "," }.count ? ";" : ","
        var rows = records(text, delimiter: delimiter)
        guard !rows.isEmpty else { throw DiaryError.invalidData }
        let header = rows.removeFirst().map { $0.trimmingCharacters(in: .whitespaces) }
        let column = Dictionary(header.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let required = format == .strong ? ["Date", "Workout Name", "Exercise Name", "Weight", "Reps"] : ["title", "start_time", "exercise_title", "reps"]
        guard required.allSatisfy({ column[$0] != nil }) else { throw DiaryError.invalidData }
        let reader = Reader(column: column, format: format, metric: defaultUnit != "lb", zone: zone)

        // Rows group into workouts by when and what, in the order they first appear.
        var order: [String] = [], groups: [String: [[String]]] = [:]
        for row in rows where !(row.count == 1 && row[0].isEmpty) {
            let key = format == .strong ? reader.value(row, "Date") + "\u{1}" + reader.value(row, "Workout Name")
                                        : reader.value(row, "title") + "\u{1}" + reader.value(row, "start_time")
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(row)
        }
        var workouts: [ImportedWorkout] = [], skipped = 0
        for key in order {
            if let workout = reader.workout(groups[key]!) { workouts.append(workout) } else { skipped += 1 }
        }
        return (workouts, skipped)
    }

    static let exportHeader = "title,start_time,end_time,exercise_title,superset_id,set_index,set_type,weight_kg,reps,distance_km,duration_seconds,effort,note"

    static func export(_ sessions: [WorkoutSession], zone: TimeZone = .current) -> String {
        var lines = [exportHeader]
        let formatter = dateFormatter("d MMM yyyy, HH:mm", zone)
        for session in sessions {
            let start = formatter.string(from: session.performedAt)
            let end = formatter.string(from: session.performedAt.addingTimeInterval(TimeInterval(session.durationSeconds ?? session.durationMinutes * 60)))
            let head = [session.title ?? WorkoutCatalog.activity(session.activity ?? "")?.name ?? "Workout", start, end]
            let groups = session.exercises.compactMap(\.groupID).reduce(into: [UUID]()) { if !$0.contains($1) { $0.append($1) } }
            let note = session.note ?? ""
            // Cardio has no sets: its one row carries the workout's own distance, time and effort.
            if session.exercises.isEmpty {
                lines.append(line(head + ["", "", "", "", "", "", session.distanceMeters.map { "\($0 / 1000)" } ?? "",
                                          String(session.durationSeconds ?? session.durationMinutes * 60), session.effort.map(String.init) ?? "", note]))
            }
            for exercise in session.exercises {
                let superset = exercise.groupID.flatMap { groups.firstIndex(of: $0) }.map { String($0 + 1) } ?? ""
                for (index, set) in exercise.sets.enumerated() {
                    let type = switch set.type {
                    case .warmup: "warmup"
                    case .drop: "dropset"
                    case .failure: "failure"
                    default: "normal"
                    }
                    lines.append(line(head + [exercise.name, superset, String(index), type, set.loadKg.map { "\($0)" } ?? "", String(set.repetitions),
                                              set.distanceMeters.map { "\($0 / 1000)" } ?? "", set.seconds.map(String.init) ?? "",
                                              set.effort.map(String.init) ?? "", note]))
                }
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: Reading

    private struct Reader {
        let column: [String: Int]
        let format: WorkoutCSVFormat
        let metric: Bool
        let zone: TimeZone

        func value(_ row: [String], _ name: String) -> String {
            guard let index = column[name], row.indices.contains(index) else { return "" }
            return row[index].trimmingCharacters(in: .whitespaces)
        }

        /// Empty reads as nil; anything else must be a number (a decimal comma is fine) or the row is broken.
        func number(_ row: [String], _ names: String...) throws -> Double? {
            for name in names where column[name] != nil {
                let text = value(row, name)
                if text.isEmpty { continue }
                guard let number = Double(text.replacingOccurrences(of: ",", with: ".")), number.isFinite, number >= 0 else { throw DiaryError.invalidData }
                return number
            }
            return nil
        }

        func workout(_ rows: [[String]]) -> ImportedWorkout? {
            guard let first = rows.first else { return nil }
            do {
                let title = value(first, format == .strong ? "Workout Name" : "title")
                let start = try date(value(first, format == .strong ? "Date" : "start_time"))
                let seconds: Int
                if format == .strong { seconds = try duration(value(first, "Duration")) }
                else { seconds = Int(try date(value(first, "end_time")).timeIntervalSince(start)) }
                var exercises: [WorkoutExercise] = [], groups: [String: UUID] = [:], note: String?, lastName = ""
                var distance: Double?, effort: Int?
                for row in rows {
                    let workoutNote = value(row, format == .strong ? "Workout Notes" : (column["description"] != nil ? "description" : "note"))
                    if note == nil, !workoutNote.isEmpty { note = workoutNote }
                    let name = value(row, format == .strong ? "Exercise Name" : "exercise_title")
                    if name.isEmpty {
                        // A row with no exercise is cardio (as Mivu exports it): the workout's distance and effort.
                        let set = try workoutSet(row); distance = set.distanceMeters ?? distance; effort = set.effort ?? effort
                        continue
                    }
                    let set = try workoutSet(row)
                    // Consecutive rows of one exercise (by the file's own name) are its sets.
                    if exercises.isEmpty || name != lastName {
                        lastName = name
                        let catalog = resolve(name)
                        var exercise = WorkoutExercise(name: catalog?.name ?? name, sets: [], exerciseID: catalog?.id, measure: catalog?.measure)
                        if format == .hevy, case let id = value(row, "superset_id"), !id.isEmpty {
                            exercise.groupID = groups[id] ?? UUID(); groups[id] = exercise.groupID
                        }
                        exercises.append(exercise)
                    }
                    exercises[exercises.count - 1].sets.append(set)
                    let exerciseNote = value(row, format == .strong ? "Notes" : "exercise_notes")
                    if exercises[exercises.count - 1].note == nil, !exerciseNote.isEmpty { exercises[exercises.count - 1].note = exerciseNote }
                }
                // Template rows with nothing in them (0 reps, no time or distance) are dropped, not stored.
                for index in exercises.indices { exercises[index].sets.removeAll { $0.repetitions == 0 && $0.seconds == nil && $0.distanceMeters == nil } }
                exercises.removeAll { $0.sets.isEmpty }
                for index in exercises.indices where exercises[index].measure == nil { exercises[index].measure = measure(of: exercises[index].sets) }
                let clamped = min(max(seconds, 60), 86_400)
                // No exercises and a title that names a sport (Mivu's own "Run") reads back as that sport.
                let sport = exercises.isEmpty ? WorkoutCatalog.activities.first { $0.id != "strength" && $0.name == title } : nil
                let draft = WorkoutDraft(kind: sport == nil ? .strength : .cardio, durationMinutes: min(1440, max(1, Int((Double(clamped) / 60).rounded()))),
                                         exercises: exercises, title: title.isEmpty || sport != nil ? nil : title, activity: sport?.id ?? "strength",
                                         durationSeconds: clamped, distanceMeters: distance, effort: effort, note: note,
                                         source: format == .strong ? .importStrong : .importHevy,
                                         externalID: "\(format == .strong ? "strong" : "hevy")/\(Int(start.timeIntervalSince1970))/\(title)")
                // The diary's own rules decide here, so a workout it would refuse is skipped instead of failing the whole import.
                var check = WorkoutSession(dayID: UUID(), performedAt: start, timePrecision: .exact, revision: 1, kind: draft.kind, durationMinutes: 0, exercises: [])
                check.apply(draft)
                try validateWorkoutFields(check)
                return ImportedWorkout(startedAt: start, draft: draft, externalID: draft.externalID!)
            } catch { return nil }
        }

        private func workoutSet(_ row: [String]) throws -> WorkoutSet {
            let poundsColumn = column["weight_lbs"] != nil
            var load = try number(row, "Weight", "weight_kg", "weight_lbs")
            if let pounds = load, poundsColumn || (format == .strong && !metric) { load = pounds * 0.45359237 }
            let milesColumn = column["distance_miles"] != nil
            var distance = try number(row, "Distance", "distance_km", "distance_miles")
            if let value = distance { distance = value * (milesColumn || (format == .strong && !metric) ? 1609.344 : 1000) }
            let seconds = try number(row, "Seconds", "duration_seconds")
            let reps = try number(row, "Reps", "reps") ?? 0
            let effort = try number(row, "RPE", "rpe", "effort").map { min(10, max(1, Int($0.rounded()))) }
            let marker = value(row, format == .strong ? "Set Order" : "set_type").lowercased()
            let type: WorkoutSetType? = switch marker {
            case "w", "warmup": .warmup
            case "d", "dropset": .drop
            case "f", "failure": .failure
            default: nil
            }
            return WorkoutSet(repetitions: Int(reps.rounded()), loadKg: load.flatMap { $0 > 0 ? $0 : nil }, type: type, effort: effort,
                              seconds: seconds.flatMap { $0 > 0 ? Int($0.rounded()) : nil }, distanceMeters: distance.flatMap { $0 > 0 ? $0 : nil }, done: true)
        }

        private func measure(of sets: [WorkoutSet]) -> ExerciseMeasure {
            if sets.contains(where: { $0.loadKg != nil }) { return .weightReps }
            if sets.contains(where: { $0.distanceMeters != nil }) { return .distanceTime }
            if sets.contains(where: { $0.seconds != nil }) { return .time }
            return .reps
        }

        /// Strong writes "Bench Press (Barbell)"; the catalog says "Barbell Bench Press".
        private func resolve(_ name: String) -> CatalogExercise? {
            if let found = WorkoutCatalog.resolve(name) { return found }
            guard let open = name.lastIndex(of: "("), name.hasSuffix(")") else { return nil }
            let base = name[..<open].trimmingCharacters(in: .whitespaces), equipment = name[name.index(after: open)..<name.index(before: name.endIndex)]
            return WorkoutCatalog.resolve("\(equipment) \(base)") ?? WorkoutCatalog.resolve(base)
        }

        private func date(_ text: String) throws -> Date {
            for pattern in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "d MMM yyyy, HH:mm", "d MMM yyyy HH:mm"] {
                if let date = dateFormatter(pattern, zone).date(from: text) { return date }
            }
            throw DiaryError.invalidData
        }

        /// "1h 5m", "12m", "45s", or plain seconds.
        private func duration(_ text: String) throws -> Int {
            if let seconds = Int(text) { return seconds }
            var total = 0, digits = "", matched = false
            for character in text where !character.isWhitespace {
                if character.isNumber { digits.append(character); continue }
                guard let amount = Int(digits), let scale = ["h": 3600, "m": 60, "s": 1][String(character).lowercased()] else { throw DiaryError.invalidData }
                total += amount * scale; digits = ""; matched = true
            }
            guard matched, digits.isEmpty else { throw DiaryError.invalidData }
            return total
        }
    }

    private static func dateFormatter(_ pattern: String, _ zone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = zone; formatter.dateFormat = pattern
        return formatter
    }

    // MARK: CSV text

    /// RFC 4180: quoted fields may hold the delimiter, quotes ("") and line breaks; CRLF or LF ends a record.
    static func records(_ text: String, delimiter: Character) -> [[String]] {
        var records: [[String]] = [], record: [String] = [], field = "", quoted = false
        var characters = text.makeIterator(), pending: Character?
        while let character = pending ?? characters.next() {
            pending = nil
            if quoted {
                if character == "\"" {
                    let next = characters.next()
                    if next == "\"" { field.append("\"") } else { quoted = false; pending = next }
                } else { field.append(character) }
            } else if character == "\"" && field.isEmpty { quoted = true }
            else if character == delimiter { record.append(field); field = "" }
            else if character == "\n" || character == "\r\n" || character == "\r" { record.append(field); records.append(record); record = []; field = "" }
            else { field.append(character) }
        }
        if !field.isEmpty || !record.isEmpty { record.append(field); records.append(record) }
        return records
    }

    private static func line(_ fields: [String]) -> String {
        fields.map { $0.contains(where: { ",\"\n\r".contains($0) }) ? "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : $0 }.joined(separator: ",")
    }
}
