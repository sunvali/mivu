import Foundation
import SQLite3

/// Short-lived connections prevent a removed file from acknowledging writes through an old handle.
final class DiaryDatabase {
    private var connection: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(url: URL, create: Bool = false) throws {
        guard create || FileManager.default.fileExists(atPath: url.path) else { throw DiaryError.persistenceFailed }
        let flags = SQLITE_OPEN_READWRITE | (create ? SQLITE_OPEN_CREATE : 0)
        guard sqlite3_open_v2(url.path, &connection, flags, nil) == SQLITE_OK else {
            sqlite3_close(connection); connection = nil
            throw create ? DiaryError.persistenceFailed : DiaryError.invalidData
        }
        do {
            try execute("PRAGMA foreign_keys = ON")
            try execute("PRAGMA journal_mode = DELETE")
            try execute("PRAGMA synchronous = FULL")
            if create {
                try execute("CREATE TABLE meta (id TEXT PRIMARY KEY, payload BLOB NOT NULL)")
                try execute("CREATE TABLE day (id TEXT PRIMARY KEY, ordinal INTEGER NOT NULL, payload BLOB NOT NULL)")
                try execute("CREATE TABLE meal (id TEXT PRIMARY KEY, parent TEXT NOT NULL REFERENCES day(id), ordinal INTEGER NOT NULL, payload BLOB NOT NULL)")
                for table in ["submission", "item"] {
                    try execute("CREATE TABLE \(table) (id TEXT PRIMARY KEY, parent TEXT NOT NULL REFERENCES meal(id) ON DELETE CASCADE, ordinal INTEGER NOT NULL, payload BLOB NOT NULL)")
                }
                try execute("CREATE TABLE photo (id TEXT PRIMARY KEY, parent TEXT NOT NULL REFERENCES meal(id) ON DELETE CASCADE, ordinal INTEGER NOT NULL, payload BLOB NOT NULL, bytes BLOB NOT NULL)")
                try execute("CREATE TABLE weight (id TEXT PRIMARY KEY, parent TEXT REFERENCES day(id), ordinal INTEGER NOT NULL, payload BLOB NOT NULL)")
                try execute("CREATE TABLE tombstone (id TEXT PRIMARY KEY, ordinal INTEGER NOT NULL, payload BLOB NOT NULL)")
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                #if os(iOS)
                try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUnlessOpen], ofItemAtPath: url.path)
                #endif
            }
        } catch {
            sqlite3_close(connection); connection = nil
            throw create ? DiaryError.persistenceFailed : DiaryError.invalidData
        }
    }

    deinit { sqlite3_close(connection) }

    func read(maximumBytes: Int) throws -> DiarySnapshot {
        try execute("BEGIN")
        do {
            let snapshot = try readSnapshot(maximumBytes: maximumBytes)
            try execute("COMMIT")
            return snapshot
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func readSnapshot(maximumBytes: Int) throws -> DiarySnapshot {
        do {
            try preflight(maximumBytes: maximumBytes)
            let integrity = try prepare("PRAGMA foreign_key_check")
            defer { sqlite3_finalize(integrity) }
            guard sqlite3_step(integrity) == SQLITE_DONE else { throw DiaryError.invalidData }
            let meta = try rows("meta")
            guard meta.count == 1 else { throw DiaryError.invalidData }
            var snapshot = try JSONDecoder().decode(DiarySnapshot.self, from: meta[0].payload)
            guard meta[0].id == snapshot.profile.id.uuidString else { throw DiaryError.wrongOwner }
            guard snapshot.days.isEmpty, snapshot.meals.isEmpty, snapshot.weights.isEmpty,
                  snapshot.deletedMealIDs.isEmpty else { throw DiaryError.invalidData }
            snapshot.days = try ordered(rows("day")).map { try decode(TrackingDay.self, $0) }
            let submissions = try rows("submission"), items = try rows("item"), photos = try rows("photo")
            var consumedSubmissions = 0, consumedItems = 0, consumedPhotos = 0
            snapshot.meals = try ordered(rows("meal")).map { row in
                var meal = try decode(DiaryMeal.self, row)
                guard row.parent == meal.dayID.uuidString, meal.submissions.isEmpty,
                      meal.items.isEmpty, meal.photos.isEmpty else { throw DiaryError.invalidData }
                let mealSubmissions = try ordered(submissions.filter { $0.parent == row.id })
                let mealItems = try ordered(items.filter { $0.parent == row.id })
                let mealPhotos = try ordered(photos.filter { $0.parent == row.id })
                consumedSubmissions += mealSubmissions.count; consumedItems += mealItems.count; consumedPhotos += mealPhotos.count
                meal.submissions = try mealSubmissions.map { try decode(MealSubmission.self, $0) }
                meal.items = try mealItems.map { try decode(FoodItem.self, $0, composite: true) }
                meal.photos = try mealPhotos.map { row in
                    var photo = try decode(MealPhoto.self, row, composite: true)
                    guard photo.data.isEmpty else { throw DiaryError.invalidData }
                    photo.data = row.bytes
                    return photo
                }
                return meal
            }
            guard consumedSubmissions == submissions.count, consumedItems == items.count,
                  consumedPhotos == photos.count else { throw DiaryError.invalidData }
            snapshot.weights = try ordered(rows("weight")).map { row in
                let weight = try decode(WeightEntry.self, row)
                guard row.parent == weight.dayID?.uuidString else { throw DiaryError.invalidData }
                return weight
            }
            snapshot.deletedMealIDs = try ordered(rows("tombstone")).map { row in
                let id = try JSONDecoder().decode(UUID.self, from: row.payload)
                guard row.id == id.uuidString else { throw DiaryError.invalidData }
                return id
            }
            try snapshot.validate()
            guard try JSONEncoder().encode(snapshot).count <= maximumBytes else { throw DiaryError.invalidData }
            return snapshot
        } catch let error as DiaryError { throw error == .wrongOwner ? error : .invalidData }
        catch { throw DiaryError.invalidData }
    }

    func write(_ snapshot: DiarySnapshot, expected: DiarySnapshot?, maximumBytes: Int) throws {
        try snapshot.validate()
        guard try JSONEncoder().encode(snapshot).count <= maximumBytes else { throw DiaryError.invalidData }
        try execute("BEGIN IMMEDIATE")
        try execute("PRAGMA defer_foreign_keys = ON")
        do {
            if let expected {
                guard try readSnapshot(maximumBytes: maximumBytes) == expected else { throw DiaryError.staleRevision }
            } else {
                guard try rows("meta").isEmpty else { throw DiaryError.invalidData }
            }
            var meta = snapshot; meta.days = []; meta.meals = []; meta.weights = []; meta.deletedMealIDs = []
            try execute("INSERT INTO meta(id, payload) VALUES (?, ?) ON CONFLICT(id) DO UPDATE SET payload = excluded.payload", [.text(snapshot.profile.id.uuidString), .blob(try JSONEncoder().encode(meta))])
            try reconcile("day", snapshot.days.enumerated().map { try record($0.element.id.uuidString, $0.offset, $0.element) })
            var meals: [Record] = [], submissions: [Record] = [], items: [Record] = [], photos: [Record] = []
            for (index, original) in snapshot.meals.enumerated() {
                let parent = original.id.uuidString
                var meal = original; meal.submissions = []; meal.items = []; meal.photos = []
                meals.append(try record(parent, index, meal, parent: meal.dayID.uuidString))
                for (i, submission) in original.submissions.enumerated() { submissions.append(try record(submission.id.uuidString, i, submission, parent: parent)) }
                for (i, item) in original.items.enumerated() { items.append(try record(parent + "/" + item.id.uuidString, i, item, parent: parent)) }
                for (i, originalPhoto) in original.photos.enumerated() {
                    var photo = originalPhoto; photo.data = Data()
                    photos.append(try record(parent + "/" + photo.id.uuidString, i, photo, parent: parent, bytes: originalPhoto.data))
                }
            }
            try reconcile("meal", meals)
            try reconcile("submission", submissions); try reconcile("item", items); try reconcile("photo", photos)
            try reconcile("weight", snapshot.weights.enumerated().map { try record($0.element.id.uuidString, $0.offset, $0.element, parent: $0.element.dayID?.uuidString) })
            try reconcile("tombstone", snapshot.deletedMealIDs.enumerated().map { try record($0.element.uuidString, $0.offset, $0.element) })
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private struct Record: Equatable {
        var id: String
        var ordinal: Int
        var payload: Data
        var parent: String?
        var bytes = Data()
    }
    private enum Value { case text(String), blob(Data), integer(Int), null }
    private func decode<T: Decodable & Identifiable>(_ type: T.Type, _ row: Record, composite: Bool = false) throws -> T where T.ID == UUID {
        let value = try JSONDecoder().decode(type, from: row.payload)
        let expected = composite ? (row.parent ?? "") + "/" + value.id.uuidString : value.id.uuidString
        guard row.id == expected else { throw DiaryError.invalidData }
        return value
    }
    private func ordered(_ rows: [Record]) throws -> [Record] {
        guard rows.enumerated().allSatisfy({ $0.offset == $0.element.ordinal }) else { throw DiaryError.invalidData }
        return rows
    }

    /// SQLite length/count metadata is checked before any payload or photo is copied into Data.
    private func preflight(maximumBytes: Int) throws {
        var total: Int64 = 0
        let limits = [("meta", 1), ("day", 10_000), ("meal", 50_000), ("submission", 50_000_000),
                      ("item", 10_000_000), ("photo", 1_500_000), ("weight", 10_000), ("tombstone", 50_000)]
        for (table, limit) in limits {
            let hasParent = ["meal", "submission", "item", "photo", "weight"].contains(table)
            let composite = ["item", "photo"].contains(table)
            var invalid = "typeof(payload) != 'blob' OR typeof(id) != 'text' OR length(id) != \(composite ? 73 : 36)"
            if table != "meta" { invalid += " OR typeof(ordinal) != 'integer' OR ordinal < 0" }
            if hasParent {
                let nullable = table == "weight" ? "parent IS NOT NULL AND " : ""
                invalid += " OR (\(nullable)(typeof(parent) != 'text' OR length(parent) != 36))"
            }
            let photo = table == "photo"
            if photo { invalid += " OR typeof(bytes) != 'blob' OR length(bytes) < 1 OR length(bytes) > 10000000" }
            let photoBytes = photo ? "COALESCE(SUM(length(bytes)), 0)" : "0"
            let statement = try prepare("SELECT COUNT(*), COALESCE(SUM(length(payload)), 0), COALESCE(MIN(length(payload)), 1), COUNT(CASE WHEN \(invalid) THEN 1 END), \(photoBytes) FROM \(table)")
            defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement) == SQLITE_ROW,
                  sqlite3_column_int64(statement, 0) <= Int64(limit),
                  sqlite3_column_int64(statement, 2) > 0,
                  sqlite3_column_int64(statement, 3) == 0 else { throw DiaryError.invalidData }
            for column: Int32 in [1, 4] {
                let length = sqlite3_column_int64(statement, column)
                guard length >= 0, length <= Int64(maximumBytes) - total else { throw DiaryError.invalidData }
                total += length
            }
            if photo { guard sqlite3_column_int64(statement, 4) <= 250_000_000 else { throw DiaryError.invalidData } }
            let childLimit = ["submission": 1000, "item": 200, "photo": 30][table]
            if let childLimit {
                let counts = try prepare("SELECT COALESCE(MAX(n), 0) FROM (SELECT COUNT(*) AS n FROM \(table) GROUP BY parent)")
                defer { sqlite3_finalize(counts) }
                guard sqlite3_step(counts) == SQLITE_ROW,
                      sqlite3_column_int64(counts, 0) <= Int64(childLimit) else { throw DiaryError.invalidData }
            }
        }
    }
    private func record<T: Encodable>(_ id: String, _ ordinal: Int, _ value: T, parent: String? = nil, bytes: Data = Data()) throws -> Record {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return Record(id: id, ordinal: ordinal, payload: try encoder.encode(value), parent: parent, bytes: bytes)
    }
    private func reconcile(_ table: String, _ records: [Record]) throws {
        let existing = try rows(table)
        let ids = Set(records.map(\.id))
        for row in existing where !ids.contains(row.id) { try execute("DELETE FROM \(table) WHERE id = ?", [.text(row.id)]) }
        let previous = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        for row in records where previous[row.id] != row {
            var columns = "id, ordinal, payload", values: [Value] = [.text(row.id), .integer(row.ordinal), .blob(row.payload)]
            var assignments = "ordinal = excluded.ordinal, payload = excluded.payload"
            if ["meal", "submission", "item", "photo", "weight"].contains(table) {
                columns += ", parent"; values.append(row.parent.map(Value.text) ?? .null); assignments += ", parent = excluded.parent"
            }
            if table == "photo" {
                columns += ", bytes"; values.append(.blob(row.bytes))
                if previous[row.id]?.bytes != row.bytes { assignments += ", bytes = excluded.bytes" }
            }
            try execute("INSERT INTO \(table)(\(columns)) VALUES (\(Array(repeating: "?", count: values.count).joined(separator: ","))) ON CONFLICT(id) DO UPDATE SET \(assignments)", values)
        }
    }
    private func rows(_ table: String) throws -> [Record] {
        let hasParent = ["meal", "submission", "item", "photo", "weight"].contains(table)
        let columns = table == "meta" ? "id, 0, payload, NULL, NULL" : "id, ordinal, payload, \(hasParent ? "parent" : "NULL"), \(table == "photo" ? "bytes" : "NULL")"
        let statement = try prepare("SELECT \(columns) FROM \(table) ORDER BY 2")
        defer { sqlite3_finalize(statement) }
        var result: [Record] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return result }
            guard status == SQLITE_ROW, let id = sqlite3_column_text(statement, 0) else { throw DiaryError.persistenceFailed }
            func blob(_ column: Int32) -> Data {
                guard let bytes = sqlite3_column_blob(statement, column) else { return Data() }
                return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, column)))
            }
            result.append(Record(id: String(cString: id), ordinal: Int(sqlite3_column_int(statement, 1)), payload: blob(2), parent: sqlite3_column_text(statement, 3).map { String(cString: $0) }, bytes: blob(4)))
        }
    }
    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw DiaryError.persistenceFailed }
        return statement
    }
    private func execute(_ sql: String, _ values: [Value] = []) throws {
        let statement = try prepare(sql); defer { sqlite3_finalize(statement) }
        for (index, value) in values.enumerated() {
            let position = Int32(index + 1)
            let status: Int32
            switch value {
            case .text(let string): status = sqlite3_bind_text(statement, position, string, -1, transient)
            case .blob(let data): status = data.withUnsafeBytes { sqlite3_bind_blob(statement, position, $0.baseAddress, Int32($0.count), transient) }
            case .integer(let integer): status = sqlite3_bind_int64(statement, position, Int64(integer))
            case .null: status = sqlite3_bind_null(statement, position)
            }
            guard status == SQLITE_OK else { throw DiaryError.persistenceFailed }
        }
        let status = sqlite3_step(statement)
        guard status == SQLITE_DONE || status == SQLITE_ROW else { throw DiaryError.persistenceFailed }
    }
}
