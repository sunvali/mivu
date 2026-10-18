import Foundation
import SQLite3
@testable import Mivu

/// Complete interchange assembly belongs to tests, never a viewport or mutation.
enum ChatHistoryFixture {
    static let maximumBytes = 350_000_000
    struct Generator {
        let seed: UInt64
        private var state: UInt64
        private(set) var drawIndex = 0
        init(seed: UInt64) { self.seed = seed; self.state = seed }
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            drawIndex += 1
            return state
        }
        mutating func encodingEdge() -> String {
            let edges = ["Synthetic", "é שלום 🍎", "\"quoted\"", "\\path/", "line\nbreak\t", "\u{0000}"]
            return edges[Int(next() % UInt64(edges.count))]
        }
        mutating func uuid() -> UUID {
            let high = next(), low = next()
            return UUID(uuidString: String(format: "%08llX-%04llX-%04llX-%04llX-%012llX",
                high >> 32, (high >> 16) & 0xFFFF, high & 0xFFFF, low >> 48, low & 0xFFFFFFFFFFFF))!
        }
    }

    static func snapshot(exchanges: Int = 100, seed: UInt64 = 42) -> DiarySnapshot {
        var generator = Generator(seed: seed)
        let instant = Date(timeIntervalSince1970: 1_800_000_000.125)
        let first = TrackingDay(id: generator.uuid(), localDate: "2027-01-15", timeZoneID: "Asia/Jerusalem", startAt: instant)
        let second = TrackingDay(id: generator.uuid(), localDate: "2027-01-14", timeZoneID: "America/New_York", startAt: instant.addingTimeInterval(-86400))
        let photoID = generator.uuid()
        var snapshot = DiarySnapshot(revision: 9, profile: DiaryProfile(id: generator.uuid(), name: "Synthetic \"profile\" 🍎"),
            days: [first, second], activeDayID: first.id, previousDayConfirmedAt: instant,
            deletedMealIDs: [generator.uuid()], deletedWeightIDs: [generator.uuid()], deletedWorkoutIDs: [generator.uuid()],
            lineage: [generator.uuid(), generator.uuid()])
        snapshot.meals = [DiaryMeal(id: generator.uuid(), dayID: second.id, capturedAt: instant, eatenAt: instant,
            revision: 1, items: [FoodItem(id: generator.uuid(), name: "Synthetic", nutrition: NutritionValues(kcal: 0, carbs: 0.125))],
            photos: [MealPhoto(id: photoID, data: Data([255, 255, 255, 0]), createdAt: instant)])]
        snapshot.weights = [WeightEntry(id: generator.uuid(), dayID: first.id, measuredAt: instant, value: 70.125)]
        snapshot.goals = [GoalRecord(id: generator.uuid(), effectiveLocalDate: first.localDate, timeZoneID: first.timeZoneID,
            targets: NutritionValues(kcal: 2000), goalWeightKg: nil, exerciseCreditEnabled: false)]
        snapshot.workouts = [WorkoutSession(id: generator.uuid(), dayID: first.id, performedAt: instant, timePrecision: .dateOnly,
            revision: 1, kind: .other, durationMinutes: 1, exercises: [], estimatedBurnKcal: 0, burnSource: .userEstimate)]
        snapshot.coachTurns = (0..<exchanges).map { index in
            let group = index % 100
            let active = group < 25 || group >= 75 ? first.id : (group < 50 ? nil : second.id)
            var turn = CoachTurn(id: generator.uuid(), capturedAt: instant, text: generator.encodingEdge(),
                state: index.isMultiple(of: 3) ? .captured : .completed,
                assistantText: index.isMultiple(of: 2) ? "Synthetic reply / \\ \" 🍎\n" : nil,
                captureTimeZoneID: "Asia/Jerusalem", activeDayID: active, resolvedDayID: second.id)
            if index < 5 {
                let photo = MealPhoto(id: photoID, data: Data(repeating: 255, count: index + 1), createdAt: instant, role: .after)
                turn.photos = [photo]; turn.photoIDs = [photo.id]
            }
            if index == 0 {
                turn.receipts = [CoachReceipt(operationKey: turn.id.uuidString + "/food/2027-01-14", turnID: turn.id,
                    dayID: second.id, mealID: snapshot.meals[0].id, committedRevision: 1, resultJSON: "{\"synthetic\":true}")]
            }
            return turn
        }
        return snapshot
    }

    /// Alternating day evidence and backwards clocks exercise sequence-based paging.
    static func pagingSnapshot(exchanges: Int = 100) -> DiarySnapshot {
        var value = snapshot(exchanges: exchanges)
        for index in value.coachTurns.indices {
            value.coachTurns[index].activeDayID = index.isMultiple(of: 2) ? value.days[0].id : value.days[1].id
            if index % 3 == 0 {
                value.coachTurns[index].capturedAt = value.coachTurns[index].capturedAt.addingTimeInterval(-Double(index))
            }
        }
        return value
    }

    /// Shared historical-correction seed; source lunch is outside both recent windows.
    static func lunchCorrectionSnapshot(capturedAt: Date = ISO8601DateFormatter().date(from: "2027-01-16T10:00:00Z")!,
                                        zone: String = "UTC", ambiguity: String = "none") -> DiarySnapshot {
        var generator = Generator(seed: 6006)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: zone)!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: capturedAt)!
        let formatter = DateFormatter(); formatter.calendar = calendar; formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        let lunch = TrackingDay(id: generator.uuid(), localDate: formatter.string(from: yesterday), timeZoneID: zone,
                                startAt: calendar.startOfDay(for: yesterday))
        let basis = NutritionValues(kcal: 100, carbs: nil, protein: 20, fat: 3)
        let chicken = FoodItem(id: generator.uuid(), name: "Chicken", quantity: ambiguity == "quantity" ? 200 : 2,
                               unit: ambiguity == "quantity" ? "g" : "piece", nutrition: basis.scaled(by: 2),
                               provenance: .estimate, reference: "Synthetic committed portion", uncertain: true,
                               nutrientSources: ["kcal": .estimate, "protein": .estimate], nutritionBasis: basis)
        let photo = MealPhoto(id: generator.uuid(), data: Data([255, 0, 255, 1]), createdAt: yesterday)
        let originID = generator.uuid()
        let description = ambiguity == "description" ? String(repeating: "Synthetic 🍎 ", count: 180) + "lunch" : "Synthetic lunch: chicken, rice and salad."
        var items = [chicken, FoodItem(id: generator.uuid(), name: "Rice", quantity: 1, unit: "cup", nutrition: NutritionValues(kcal: 200)),
                     FoodItem(id: generator.uuid(), name: "Salad", quantity: 1, unit: "bowl", nutrition: NutritionValues(kcal: 50))]
        if ambiguity == "item" { var second = chicken; second.id = generator.uuid(); items.append(second) }
        if ambiguity == "itemsOmitted" {
            for _ in 0..<196 {
                items.append(FoodItem(id: generator.uuid(), name: String(repeating: "Synthetic food ", count: 30),
                    quantity: 1, unit: "piece", nutrition: NutritionValues(kcal: 1), reference: String(repeating: "Source ", count: 250)))
            }
            var hidden = chicken; hidden.id = generator.uuid(); items.append(hidden)
        }
        let meal = DiaryMeal(id: generator.uuid(), dayID: lunch.id, capturedAt: yesterday,
                             eatenAt: calendar.date(bySettingHour: 12, minute: 0, second: 0, of: yesterday)!,
                             revision: 1, timePrecision: .dateOnly, items: items, photos: [photo],
                             submissions: [MealSubmission(id: originID, baseRevision: 0, text: description,
                                                          photoIDs: [photo.id], reviewFirst: false, state: .saved)])
        var source = DiarySnapshot(revision: 9, profile: DiaryProfile(id: generator.uuid(), name: "Synthetic correction", timeZoneID: zone),
                                   days: [lunch], meals: [meal])
        source.coachTurns = [CoachTurn(id: originID, capturedAt: yesterday, text: description, state: .completed,
                                      assistantText: "Recorded synthetic lunch.",
                                      receipts: [CoachReceipt(operationKey: "\(originID)/food/\(lunch.localDate)", turnID: originID,
                                                              dayID: lunch.id, mealID: meal.id, committedRevision: 1, resultJSON: "{}")],
                                      captureTimeZoneID: zone, activeDayID: lunch.id, photoIDs: [photo.id])]
        // Repeated date labels are real distinct days; noon alone never proves lunch.
        let repeated = TrackingDay(id: generator.uuid(), localDate: lunch.localDate,
                                   timeZoneID: zone == "Pacific/Honolulu" ? "UTC" : "Pacific/Honolulu", startAt: lunch.startAt)
        source.days.append(repeated)
        var other = meal; other.id = generator.uuid(); other.dayID = repeated.id
        other.photos = []; other.submissions = [MealSubmission(id: generator.uuid(), baseRevision: 0,
            text: ambiguity == "meal" ? "Another synthetic lunch" : "Synthetic dinner", photoIDs: [], reviewFirst: false, state: .saved)]
        other.items = other.items.map { item in var value = item; value.id = generator.uuid(); return value }
        source.meals.append(other)
        if ambiguity == "page" {
            for _ in 0..<21 {
                var extra = other; extra.id = generator.uuid(); extra.submissions[0].id = generator.uuid()
                source.meals.append(extra)
            }
        }
        for index in 1...30 {
            let instant = calendar.date(byAdding: .day, value: index, to: capturedAt)!
            let day = TrackingDay(id: generator.uuid(), localDate: formatter.string(from: instant), timeZoneID: zone, startAt: instant)
            source.days.append(day)
            for _ in 0..<4 {
                source.coachTurns.append(CoachTurn(id: generator.uuid(), capturedAt: instant,
                    text: "Synthetic newer completed exchange \(index)", state: .completed, assistantText: "Recorded.",
                    captureTimeZoneID: zone, activeDayID: day.id))
            }
        }
        source.activeDayID = source.days.last!.id
        source.previousDayConfirmedAt = source.days.last!.startAt
        return source
    }

    static func makeDatabase(_ snapshot: DiarySnapshot) throws -> URL {
        let directory = URL.temporaryDirectory.appending(path: "ChatHistory-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "diary.sqlite")
        try DiaryDatabase(url: url, create: true).write(snapshot, expected: nil, maximumBytes: maximumBytes)
        return url
    }

    static func withConnection<T>(_ url: URL, _ body: (OpaquePointer) throws -> T) throws -> T {
        var connection: OpaquePointer?
        guard sqlite3_open(url.path, &connection) == SQLITE_OK, let connection else { throw DiaryError.invalidData }
        defer { sqlite3_close(connection) }
        return try body(connection)
    }
    static func execute(_ url: URL, _ sql: String) throws {
        try withConnection(url) { connection in
            guard sqlite3_exec(connection, sql, nil, nil, nil) == SQLITE_OK else { throw DiaryError.persistenceFailed }
        }
    }
    static func changePayload(_ url: URL, table: String, _ change: (inout [String: Any]) -> Void) throws {
        try withConnection(url) { connection in
            var read: OpaquePointer?
            guard sqlite3_prepare_v2(connection, "SELECT id, payload FROM \(table) ORDER BY id LIMIT 1", -1, &read, nil) == SQLITE_OK, let read else { throw DiaryError.invalidData }
            defer { sqlite3_finalize(read) }
            guard sqlite3_step(read) == SQLITE_ROW, let id = sqlite3_column_text(read, 0), let bytes = sqlite3_column_blob(read, 1),
                  var payload = try JSONSerialization.jsonObject(with: Data(bytes: bytes, count: Int(sqlite3_column_bytes(read, 1)))) as? [String: Any] else { throw DiaryError.invalidData }
            let rowID = String(cString: id)
            change(&payload)
            let encoded = try JSONSerialization.data(withJSONObject: payload)
            var write: OpaquePointer?
            guard sqlite3_prepare_v2(connection, "UPDATE \(table) SET payload = ? WHERE id = ?", -1, &write, nil) == SQLITE_OK, let write else { throw DiaryError.invalidData }
            defer { sqlite3_finalize(write) }
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            _ = encoded.withUnsafeBytes { sqlite3_bind_blob(write, 1, $0.baseAddress, Int32($0.count), transient) }
            sqlite3_bind_text(write, 2, rowID, -1, transient)
            guard sqlite3_step(write) == SQLITE_DONE else { throw DiaryError.persistenceFailed }
        }
    }
    static func strings(_ url: URL, _ sql: String) throws -> [[String]] {
        try withConnection(url) { connection in
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw DiaryError.invalidData }
            defer { sqlite3_finalize(statement) }
            var result: [[String]] = []
            while true {
                let status = sqlite3_step(statement)
                if status == SQLITE_DONE { return result }
                guard status == SQLITE_ROW else { throw DiaryError.invalidData }
                result.append((0..<sqlite3_column_count(statement)).map { column in
                    sqlite3_column_text(statement, column).map { String(cString: $0) } ?? "NULL"
                })
            }
        }
    }

    static func completeReference(databaseURL: URL) throws -> DiarySnapshot {
        try withConnection(databaseURL) { connection in
            struct Row { var parent: String?; var payload: Any; var bytes: Data }
            func rows(_ table: String) throws -> [Row] {
                let parents = ["meal", "submission", "item", "photo", "weight", "workout", "coach_photo"]
                let isPhoto = ["photo", "coach_photo"].contains(table)
                let query = "SELECT \(parents.contains(table) ? "parent" : "NULL"), payload, \(isPhoto ? "bytes" : "NULL") FROM \(table) ORDER BY \(table == "meta" ? "id" : "ordinal, id")"
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(connection, query, -1, &statement, nil) == SQLITE_OK, let statement else { throw DiaryError.invalidData }
                defer { sqlite3_finalize(statement) }
                var result: [Row] = []
                while true {
                    let status = sqlite3_step(statement)
                    if status == SQLITE_DONE { return result }
                    guard status == SQLITE_ROW, let payload = sqlite3_column_blob(statement, 1) else { throw DiaryError.invalidData }
                    let data = Data(bytes: payload, count: Int(sqlite3_column_bytes(statement, 1)))
                    let bytes = sqlite3_column_blob(statement, 2).map { Data(bytes: $0, count: Int(sqlite3_column_bytes(statement, 2))) } ?? Data()
                    result.append(Row(parent: sqlite3_column_text(statement, 0).map { String(cString: $0) },
                        payload: try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed), bytes: bytes))
                }
            }
            let version = try strings(databaseURL, "PRAGMA user_version")
            var root: [String: Any]
            if version == [["1"]] {
                // Version 1 export takes metadata only from its authoritative normalized head.
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(connection, "SELECT schemaVersion, revision, profilePayload, lineagePayload, activeDayID, previousDayConfirmedAt, activeConversationSegmentID FROM storage_head WHERE id = 1", -1, &statement, nil) == SQLITE_OK, let statement else { throw DiaryError.invalidData }
                defer { sqlite3_finalize(statement) }
                guard sqlite3_step(statement) == SQLITE_ROW, let profile = sqlite3_column_blob(statement, 2) else { throw DiaryError.invalidData }
                root = ["schemaVersion": Int(sqlite3_column_int64(statement, 0)), "revision": Int(sqlite3_column_int64(statement, 1)),
                    "profile": try JSONSerialization.jsonObject(with: Data(bytes: profile, count: Int(sqlite3_column_bytes(statement, 2))))]
                if let lineage = sqlite3_column_blob(statement, 3) { root["lineage"] = try JSONSerialization.jsonObject(with: Data(bytes: lineage, count: Int(sqlite3_column_bytes(statement, 3)))) }
                if let active = sqlite3_column_text(statement, 4) { root["activeDayID"] = String(cString: active) }
                if sqlite3_column_type(statement, 5) != SQLITE_NULL {
                    root["previousDayConfirmedAt"] = sqlite3_column_double(statement, 5)
                }
                if let segment = sqlite3_column_text(statement, 6) { root["activeConversationSegmentID"] = String(cString: segment) }
                root["goals"] = try rows("goal").map(\.payload)
                root["deletedWeightIDs"] = try rows("weight_tombstone").map(\.payload)
                root["deletedWorkoutIDs"] = try rows("workout_tombstone").map(\.payload)
            } else {
                let meta = try rows("meta")
                guard meta.count == 1, let value = meta[0].payload as? [String: Any] else { throw DiaryError.invalidData }
                root = value
            }
            func objects(_ table: String) throws -> [[String: Any]] { try rows(table).map { guard let object = $0.payload as? [String: Any] else { throw DiaryError.invalidData }; return object } }
            let submissions = try rows("submission"), items = try rows("item"), photos = try rows("photo"), coachPhotos = try rows("coach_photo")
            func children(_ source: [Row], parent: String, photo: Bool = false) throws -> [[String: Any]] {
                try source.filter { $0.parent == parent }.map { row in
                    guard var value = row.payload as? [String: Any] else { throw DiaryError.invalidData }
                    if photo { value["data"] = row.bytes.base64EncodedString() }
                    return value
                }
            }
            root["days"] = try objects("day")
            root["meals"] = try objects("meal").map { meal in
                var value = meal
                guard let id = value["id"] as? String else { throw DiaryError.invalidData }
                value["submissions"] = try children(submissions, parent: id)
                value["items"] = try children(items, parent: id)
                value["photos"] = try children(photos, parent: id, photo: true)
                return value
            }
            root["weights"] = try objects("weight"); root["workouts"] = try objects("workout")
            root["deletedMealIDs"] = try rows("tombstone").map(\.payload)
            root["coachTurns"] = try objects("coach_turn").map { turn in
                var value = turn
                guard let id = value["id"] as? String else { throw DiaryError.invalidData }
                value["photos"] = try children(coachPhotos, parent: id, photo: true)
                return value
            }
            return try JSONDecoder().decode(DiarySnapshot.self, from: JSONSerialization.data(withJSONObject: root))
        }
    }
}
