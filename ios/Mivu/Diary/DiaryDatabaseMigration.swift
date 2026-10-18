import Foundation
import SQLite3

extension DiaryDatabase {
    /// Staged explicitly; shipping activation and the legacy-writer fence belong together.
    func migrateForPagedStorage(maximumBytes: Int) throws {
        let maximumBytes = min(maximumBytes, 350_000_000)
        guard maximumBytes > 0 else { throw DiaryError.invalidData }
        try execute("BEGIN IMMEDIATE")
        do {
            let version = try storageInteger("PRAGMA user_version")
            if version == 1 {
                guard try storageInteger("SELECT COUNT(*) FROM storage_head") == 1,
                      try storageInteger("SELECT portableBytes FROM storage_quota WHERE id = 1") <= maximumBytes else { throw DiaryError.invalidData }
                try execute("COMMIT")
                return
            }
            guard version == 0 else { throw DiaryError.invalidData }
            try preflight(maximumBytes: maximumBytes)
            guard try storageInteger("SELECT COUNT(*) FROM pragma_foreign_key_check") == 0 else { throw DiaryError.invalidData }
            // Capacity is advisory; every SQLite write/commit must still handle a full disk.
            if let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
               let available = values.volumeAvailableCapacityForImportantUsage, available < 65_536 {
                throw DiaryError.persistenceFailed
            }
            try createPagedSchema()
            let metadata = try migrateMetadata()
            let days = try migrateDays(metadata: metadata)
            try validateMetadata(metadata, days: days)
            try migrateMeals(metadata: metadata, days: days)
            try migrateProgress(metadata: metadata, days: days)
            try migrateTurns(metadata: metadata, days: days)
            try finishPagedAccounting(maximumBytes: maximumBytes)
            try execute("PRAGMA user_version = 1")
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            if let error = error as? DiaryError { throw error }
            throw DiaryError.invalidData
        }
    }

    private func createPagedSchema() throws {
        let statements = [
            "CREATE TABLE storage_head (id INTEGER PRIMARY KEY CHECK(id = 1), schemaVersion INTEGER NOT NULL, profileID TEXT NOT NULL UNIQUE, profilePayload BLOB NOT NULL, revision INTEGER NOT NULL, lineagePayload BLOB, activeDayID TEXT REFERENCES day(id) DEFERRABLE INITIALLY DEFERRED, previousDayConfirmedAt REAL, timelineGeneration TEXT NOT NULL, nextSequence INTEGER NOT NULL)",
            "CREATE TABLE goal (id TEXT PRIMARY KEY, ordinal INTEGER NOT NULL, effectiveLocalDate TEXT NOT NULL UNIQUE, payload BLOB NOT NULL)",
            "CREATE TABLE weight_tombstone (id TEXT PRIMARY KEY, ordinal INTEGER NOT NULL, payload BLOB NOT NULL)",
            "CREATE TABLE workout_tombstone (id TEXT PRIMARY KEY, ordinal INTEGER NOT NULL, payload BLOB NOT NULL)",
            "CREATE TABLE coach_segment (segmentID TEXT PRIMARY KEY, trackingDayID TEXT REFERENCES day(id), displayLocalDate TEXT NOT NULL, displayTimeZoneID TEXT NOT NULL, firstTurnID TEXT NOT NULL REFERENCES coach_turn(id), firstCapturedAt REAL NOT NULL, firstSequence INTEGER NOT NULL, lastSequence INTEGER NOT NULL, preview TEXT NOT NULL)",
            "CREATE TABLE coach_index (turnID TEXT PRIMARY KEY REFERENCES coach_turn(id) ON DELETE CASCADE, sequence INTEGER NOT NULL UNIQUE, capturedAt REAL NOT NULL, captureTimeZoneID TEXT NOT NULL, trackingDayID TEXT REFERENCES day(id), displayLocalDate TEXT NOT NULL, displayTimeZoneID TEXT NOT NULL, state TEXT NOT NULL, pendingMealID TEXT, segmentID TEXT NOT NULL REFERENCES coach_segment(segmentID))",
            "CREATE INDEX coach_index_day_sequence ON coach_index(trackingDayID, sequence)",
            "CREATE INDEX coach_index_state_sequence ON coach_index(state, sequence)",
            "CREATE INDEX coach_index_pending_meal ON coach_index(pendingMealID)",
            "CREATE TRIGGER coach_index_capture_immutable BEFORE UPDATE OF turnID, sequence, capturedAt, captureTimeZoneID, trackingDayID, displayLocalDate, displayTimeZoneID, segmentID ON coach_index WHEN NEW.turnID IS NOT OLD.turnID OR NEW.sequence IS NOT OLD.sequence OR NEW.capturedAt IS NOT OLD.capturedAt OR NEW.captureTimeZoneID IS NOT OLD.captureTimeZoneID OR NEW.trackingDayID IS NOT OLD.trackingDayID OR NEW.displayLocalDate IS NOT OLD.displayLocalDate OR NEW.displayTimeZoneID IS NOT OLD.displayTimeZoneID OR NEW.segmentID IS NOT OLD.segmentID BEGIN SELECT RAISE(ABORT, 'immutable capture metadata'); END",
            "CREATE INDEX coach_segment_date_last ON coach_segment(displayLocalDate, lastSequence, segmentID)",
            "CREATE INDEX coach_segment_last ON coach_segment(lastSequence, segmentID)",
            "CREATE TABLE record_source (kind TEXT NOT NULL, recordID TEXT NOT NULL, turnID TEXT NOT NULL REFERENCES coach_turn(id) ON DELETE CASCADE, relation TEXT NOT NULL CHECK(relation IN ('origin','reference')), PRIMARY KEY(kind, recordID, turnID, relation))",
            "CREATE INDEX record_source_turn ON record_source(turnID)",
            "CREATE INDEX record_source_origin ON record_source(kind, recordID, relation, turnID)",
            "CREATE TABLE photo_content (ownerKind TEXT NOT NULL CHECK(ownerKind IN ('meal','coachTurn')), parentID TEXT NOT NULL, photoID TEXT NOT NULL, physicalID TEXT NOT NULL, contentToken TEXT NOT NULL UNIQUE, mealPhysicalID TEXT REFERENCES photo(id) ON DELETE CASCADE, coachPhysicalID TEXT REFERENCES coach_photo(id) ON DELETE CASCADE, PRIMARY KEY(ownerKind, parentID, photoID), UNIQUE(ownerKind, physicalID), CHECK(physicalID = parentID || '/' || photoID), CHECK((ownerKind = 'meal' AND mealPhysicalID IS NOT NULL AND mealPhysicalID = physicalID AND coachPhysicalID IS NULL) OR (ownerKind = 'coachTurn' AND coachPhysicalID IS NOT NULL AND coachPhysicalID = physicalID AND mealPhysicalID IS NULL)))",
            "CREATE TABLE photo_consumer (ownerKind TEXT NOT NULL, parentID TEXT NOT NULL, photoID TEXT NOT NULL, turnID TEXT NOT NULL REFERENCES coach_turn(id) ON DELETE CASCADE, PRIMARY KEY(ownerKind, parentID, photoID, turnID), FOREIGN KEY(ownerKind, parentID, photoID) REFERENCES photo_content(ownerKind, parentID, photoID) ON DELETE CASCADE)",
            "CREATE INDEX photo_consumer_turn ON photo_consumer(turnID)",
            "CREATE TABLE storage_contribution (tableName TEXT NOT NULL, rowID TEXT NOT NULL, parentID TEXT, encodedBytes INTEGER NOT NULL CHECK(encodedBytes > 0), originalPhotoBytes INTEGER NOT NULL CHECK(originalPhotoBytes >= 0), PRIMARY KEY(tableName, rowID))",
            "CREATE INDEX storage_contribution_parent ON storage_contribution(tableName, parentID)",
            "CREATE TABLE storage_row_count (tableName TEXT PRIMARY KEY, rowCount INTEGER NOT NULL CHECK(rowCount >= 0))",
            "CREATE TABLE storage_quota (id INTEGER PRIMARY KEY CHECK(id = 1), portableBytes INTEGER NOT NULL CHECK(portableBytes > 0), originalPhotoBytes INTEGER NOT NULL CHECK(originalPhotoBytes >= 0))"
        ]
        for statement in statements { try execute(statement) }
        for table in ["meal", "submission", "item", "photo", "weight", "workout", "coach_photo"] {
            try execute("CREATE INDEX IF NOT EXISTS \(table)_parent_ordinal ON \(table)(parent, ordinal, id)")
        }
        for table in ["day", "meal", "weight", "workout", "tombstone", "coach_turn"] {
            try execute("CREATE INDEX IF NOT EXISTS \(table)_ordinal ON \(table)(ordinal, id)")
        }
        try execute("CREATE INDEX goal_date ON goal(effectiveLocalDate)")
    }

    private struct StorageRow {
        var record: Record
        var rowID: Int64
        var photoBytes: Int
    }

    /// SQLite steps one metadata row at a time; originals are only streamed by accounting.
    private func visitStorageRows(_ table: String, parent: String? = nil, _ body: (StorageRow) throws -> Void) throws {
        let hasParent = ["meal", "submission", "item", "photo", "weight", "workout", "coach_photo"].contains(table)
        let isPhoto = ["photo", "coach_photo"].contains(table)
        let statement = try prepare("SELECT id, \(table == "meta" ? "0" : "ordinal"), payload, \(hasParent ? "parent" : "NULL"), rowid, \(isPhoto ? "length(bytes)" : "0") FROM \(table)\(parent == nil ? "" : " WHERE parent = ?") ORDER BY \(table == "meta" ? "id" : "ordinal, id")")
        defer { sqlite3_finalize(statement) }
        if let parent {
            guard sqlite3_bind_text(statement, 1, parent, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) == SQLITE_OK else { throw DiaryError.persistenceFailed }
        }
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return }
            guard result == SQLITE_ROW, let id = sqlite3_column_text(statement, 0),
                  let payload = sqlite3_column_blob(statement, 2) else { throw DiaryError.invalidData }
            let record = Record(id: String(cString: id), ordinal: Int(sqlite3_column_int64(statement, 1)),
                payload: Data(bytes: payload, count: Int(sqlite3_column_bytes(statement, 2))),
                parent: sqlite3_column_text(statement, 3).map { String(cString: $0) })
            try body(StorageRow(record: record, rowID: sqlite3_column_int64(statement, 4), photoBytes: Int(sqlite3_column_int64(statement, 5))))
        }
    }

    private func storageInteger(_ sql: String) throws -> Int {
        let statement = try prepare(sql); defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw DiaryError.invalidData }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func account<Value: Encodable>(_ value: Value, table: String, row: Record, nested: Bool = false) throws {
        try contribution(table: table, row: row, count: JSONEncoder().encode(value).count, nested: nested)
    }

    private func contribution(table: String, row: Record, count: Int, originalBytes: Int = 0, nested: Bool = false) throws {
        try execute("INSERT INTO storage_contribution(tableName, rowID, parentID, encodedBytes, originalPhotoBytes) VALUES (?, ?, ?, ?, ?)",
            [.text(table), .text(row.id), nested ? row.parent.map(Value.text) ?? .null : .null, .integer(count), .integer(originalBytes)])
    }

    private func migrateMetadata() throws -> DiarySnapshot {
        var metadata: DiarySnapshot?
        try visitStorageRows("meta") { row in
            guard metadata == nil else { throw DiaryError.invalidData }
            let value = try JSONDecoder().decode(DiarySnapshot.self, from: row.record.payload)
            guard row.record.id == value.profile.id.uuidString else { throw DiaryError.wrongOwner }
            guard value.days.isEmpty, value.meals.isEmpty, value.weights.isEmpty, value.workouts.isEmpty,
                  value.deletedMealIDs.isEmpty, value.coachTurns.isEmpty else { throw DiaryError.invalidData }
            metadata = value
        }
        guard let metadata else { throw DiaryError.invalidData }
        guard metadata.goals.count <= 10_000, Set(metadata.goals.map(\.id)).count == metadata.goals.count,
              Set(metadata.goals.map(\.effectiveLocalDate)).count == metadata.goals.count,
              metadata.deletedWeightIDs.count <= 10_000, Set(metadata.deletedWeightIDs).count == metadata.deletedWeightIDs.count,
              metadata.deletedWorkoutIDs.count <= 50_000, Set(metadata.deletedWorkoutIDs).count == metadata.deletedWorkoutIDs.count else { throw DiaryError.invalidData }
        try execute("INSERT INTO storage_head(id, schemaVersion, profileID, profilePayload, revision, lineagePayload, activeDayID, previousDayConfirmedAt, timelineGeneration, nextSequence) VALUES (1, ?, ?, ?, ?, ?, ?, ?, ?, 1)",
            [.integer(metadata.schemaVersion), .text(metadata.profile.id.uuidString), .blob(try JSONEncoder().encode(metadata.profile)),
             .integer(metadata.revision), try metadata.lineage.map { .blob(try JSONEncoder().encode($0)) } ?? .null,
             metadata.activeDayID.map { .text($0.uuidString) } ?? .null,
             metadata.previousDayConfirmedAt.map { .real($0.timeIntervalSinceReferenceDate) } ?? .null, .text(UUID().uuidString)])
        for (ordinal, goal) in metadata.goals.enumerated() {
            let payload = try JSONEncoder().encode(goal)
            try execute("INSERT INTO goal(id, ordinal, effectiveLocalDate, payload) VALUES (?, ?, ?, ?)", [.text(goal.id.uuidString), .integer(ordinal), .text(goal.effectiveLocalDate), .blob(payload)])
            try contribution(table: "goal", row: Record(id: goal.id.uuidString, ordinal: ordinal, payload: payload), count: payload.count)
        }
        for (table, ids) in [("weight_tombstone", metadata.deletedWeightIDs), ("workout_tombstone", metadata.deletedWorkoutIDs)] {
            for (ordinal, id) in ids.enumerated() {
                let payload = try JSONEncoder().encode(id)
                try execute("INSERT INTO \(table)(id, ordinal, payload) VALUES (?, ?, ?)", [.text(id.uuidString), .integer(ordinal), .blob(payload)])
                try contribution(table: table, row: Record(id: id.uuidString, ordinal: ordinal, payload: payload), count: payload.count)
            }
        }
        // An encoding shell is used only for one-time interchange accounting, never as a read projection.
        var shell = metadata; shell.goals = []; shell.deletedWeightIDs = []; shell.deletedWorkoutIDs = []
        try account(shell, table: "meta", row: Record(id: metadata.profile.id.uuidString, ordinal: 0, payload: Data()))
        return metadata
    }

    private func migrateDays(metadata: DiarySnapshot) throws -> [UUID: TrackingDay] {
        var days: [UUID: TrackingDay] = [:]
        try visitStorageRows("day") { row in
            let day = try decode(TrackingDay.self, row.record)
            guard validLocalDate(day.localDate), TimeZone(identifier: day.timeZoneID) != nil,
                  day.startAt.timeIntervalSince1970.isFinite,
                  day.closedAt == nil || day.closedAt!.timeIntervalSince1970.isFinite else { throw DiaryError.invalidData }
            days[day.id] = day
            try account(day, table: "day", row: row.record)
        }
        return days
    }

    private func validateMetadata(_ metadata: DiarySnapshot, days: [UUID: TrackingDay]) throws {
        let profile = metadata.profile
        guard metadata.schemaVersion == 1, (0..<10_000_000).contains(metadata.revision),
              !profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, profile.name.count <= 200,
              ["en", "he"].contains(profile.language), TimeZone(identifier: profile.timeZoneID) != nil,
              profile.preferences.count <= 10_000,
              metadata.activeDayID == nil || days[metadata.activeDayID!] != nil,
              metadata.previousDayConfirmedAt == nil || metadata.previousDayConfirmedAt!.timeIntervalSince1970.isFinite,
              metadata.lineage == nil || (!metadata.lineage!.isEmpty && metadata.lineage!.count <= 256 && Set(metadata.lineage!).count == metadata.lineage!.count),
              metadata.goals.count <= 10_000, Set(metadata.goals.map(\.id)).count == metadata.goals.count,
              Set(metadata.goals.map(\.effectiveLocalDate)).count == metadata.goals.count,
              metadata.deletedWeightIDs.count <= 10_000, Set(metadata.deletedWeightIDs).count == metadata.deletedWeightIDs.count,
              metadata.deletedWorkoutIDs.count <= 50_000, Set(metadata.deletedWorkoutIDs).count == metadata.deletedWorkoutIDs.count else { throw DiaryError.invalidData }
        for goal in metadata.goals {
            guard validLocalDate(goal.effectiveLocalDate), TimeZone(identifier: goal.timeZoneID) != nil,
                  (1..<1_000_000).contains(goal.revision),
                  [goal.targets.kcal, goal.targets.carbs, goal.targets.protein, goal.targets.fat, goal.goalWeightKg]
                    .allSatisfy({ $0 == nil || ($0!.isFinite && $0! > 0 && $0! <= 10_000_000) }) else { throw DiaryError.invalidData }
        }
    }

    private func migrateMeals(metadata: DiarySnapshot, days: [UUID: TrackingDay]) throws {
        try visitStorageRows("meal") { row in
            let meal = try decode(DiaryMeal.self, row.record)
            guard row.record.parent == meal.dayID.uuidString, days[meal.dayID] != nil,
                  meal.items.isEmpty, meal.photos.isEmpty, meal.submissions.isEmpty,
                  (0..<1_000_000).contains(meal.revision),
                  meal.capturedAt.timeIntervalSince1970.isFinite, meal.eatenAt.timeIntervalSince1970.isFinite else { throw DiaryError.invalidData }
            try account(meal, table: "meal", row: row.record)
            var items: [FoodItem] = []
            try visitStorageRows("item", parent: row.record.id) { child in
                let item = try decode(FoodItem.self, child.record, composite: true)
                items.append(item)
                try account(item, table: "item", row: child.record, nested: true)
            }
            try validateItems(items)
            guard meal.revision == 0 || !items.isEmpty else { throw DiaryError.invalidData }
            let photoIDs = try migratePhotos(table: "photo", parent: row.record.id, owner: "meal")
            try visitStorageRows("submission", parent: row.record.id) { child in
                let submission = try decode(MealSubmission.self, child.record)
                guard submission.baseRevision >= 0, submission.baseRevision <= meal.revision,
                      submission.text.count <= 20_000, Set(submission.photoIDs).count == submission.photoIDs.count,
                      submission.photoIDs.allSatisfy({ photoIDs.contains($0) }),
                      submission.state != .awaitingReview || submission.proposal != nil else { throw DiaryError.invalidData }
                if let proposal = submission.proposal {
                    guard proposal.schemaVersion == 1, proposal.profileID == metadata.profile.id,
                          proposal.mealID == meal.id, proposal.submissionID == submission.id,
                          proposal.baseRevision == submission.baseRevision else { throw DiaryError.invalidData }
                    try validateItems(proposal.items)
                }
                try account(submission, table: "submission", row: child.record, nested: true)
            }
        }
    }

    private func migratePhotos(table: String, parent: String, owner: String) throws -> Set<UUID> {
        var ids = Set<UUID>()
        try visitStorageRows(table, parent: parent) { row in
            let photo = try decode(MealPhoto.self, row.record, composite: true)
            guard photo.data.isEmpty, photo.createdAt.timeIntervalSince1970.isFinite,
                  row.photoBytes > 0, row.photoBytes <= 10_000_000,
                  ids.insert(photo.id).inserted else { throw DiaryError.invalidData }
            let encoded = try JSONEncoder().encode(photo).count + encodedPhotoContentBytes(table: table, rowID: row.rowID, byteCount: row.photoBytes)
            try contribution(table: table, row: row.record, count: encoded, originalBytes: row.photoBytes, nested: true)
            try execute("INSERT INTO photo_content(ownerKind, parentID, photoID, physicalID, contentToken, mealPhysicalID, coachPhysicalID) VALUES (?, ?, ?, ?, ?, ?, ?)",
                [.text(owner), .text(parent), .text(photo.id.uuidString), .text(row.record.id), .text(UUID().uuidString),
                 owner == "meal" ? .text(row.record.id) : .null, owner == "coachTurn" ? .text(row.record.id) : .null])
        }
        return ids
    }

    /// Default JSONEncoder escapes '/' in base64. Chunk boundaries are multiples of three.
    private func encodedPhotoContentBytes(table: String, rowID: Int64, byteCount: Int) throws -> Int {
        var blob: OpaquePointer?
        guard sqlite3_blob_open(connection, "main", table, "bytes", rowID, 0, &blob) == SQLITE_OK, let blob else { throw DiaryError.persistenceFailed }
        defer { sqlite3_blob_close(blob) }
        guard Int(sqlite3_blob_bytes(blob)) == byteCount else { throw DiaryError.invalidData }
        var buffer = [UInt8](repeating: 0, count: 49_152)
        var offset = 0, encodedBytes = 0
        while offset < byteCount {
            let count = min(buffer.count, byteCount - offset)
            let status = buffer.withUnsafeMutableBytes { sqlite3_blob_read(blob, $0.baseAddress, Int32(count), Int32(offset)) }
            guard status == SQLITE_OK else { throw DiaryError.persistenceFailed }
            diagnostics?.recordPhotoRead(bytes: count)
            let chunk = Data(buffer.prefix(count)).base64EncodedData()
            encodedBytes += chunk.count + chunk.reduce(0) { $0 + ($1 == 47 ? 1 : 0) }
            offset += count
        }
        return encodedBytes
    }

    private func migrateProgress(metadata: DiarySnapshot, days: [UUID: TrackingDay]) throws {
        var weightDays = Set<UUID>()
        let deletedWeightIDs = Set(metadata.deletedWeightIDs)
        let deletedWorkoutIDs = Set(metadata.deletedWorkoutIDs)
        try visitStorageRows("weight") { row in
            let weight = try decode(WeightEntry.self, row.record)
            guard row.record.parent == weight.dayID?.uuidString,
                  weight.value.isFinite, weight.value > 0, weight.value <= 1500,
                  ["kg", "lb"].contains(weight.unit), weight.measuredAt.timeIntervalSince1970.isFinite,
                  (1..<1_000_000).contains(weight.revision), !deletedWeightIDs.contains(weight.id) else { throw DiaryError.invalidData }
            if let dayID = weight.dayID { guard days[dayID] != nil, weightDays.insert(dayID).inserted else { throw DiaryError.invalidData } }
            try account(weight, table: "weight", row: row.record)
        }
        try visitStorageRows("workout") { row in
            let workout = try decode(WorkoutSession.self, row.record)
            guard row.record.parent == workout.dayID.uuidString, days[workout.dayID] != nil,
                  workout.performedAt.timeIntervalSince1970.isFinite,
                  (1..<1_000_000).contains(workout.revision), (1...1440).contains(workout.durationMinutes),
                  workout.exercises.count <= 100, !deletedWorkoutIDs.contains(workout.id),
                  workout.estimatedBurnKcal == nil || (workout.estimatedBurnKcal!.isFinite && workout.estimatedBurnKcal! >= 0 && workout.estimatedBurnKcal! <= 100_000),
                  workout.burnSource == nil || workout.estimatedBurnKcal != nil else { throw DiaryError.invalidData }
            for exercise in workout.exercises {
                guard !exercise.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      exercise.name.count <= 200, exercise.sets.count <= 100 else { throw DiaryError.invalidData }
                for set in exercise.sets {
                    guard (1...10_000).contains(set.repetitions),
                          set.loadKg == nil || (set.loadKg!.isFinite && set.loadKg! >= 0 && set.loadKg! <= 100_000) else { throw DiaryError.invalidData }
                }
            }
            try account(workout, table: "workout", row: row.record)
        }
        try visitStorageRows("tombstone") { row in
            let id = try JSONDecoder().decode(UUID.self, from: row.record.payload)
            guard row.record.id == id.uuidString else { throw DiaryError.invalidData }
            let statement = try prepare("SELECT 1 FROM meal WHERE id = ?"); defer { sqlite3_finalize(statement) }
            sqlite3_bind_text(statement, 1, row.record.id, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            guard sqlite3_step(statement) == SQLITE_DONE else { throw DiaryError.invalidData }
            try account(id, table: "tombstone", row: row.record)
        }
    }

    private func migrateTurns(metadata: DiarySnapshot, days: [UUID: TrackingDay]) throws {
        var sequence = 0
        var priorDayID: UUID?, priorDate: String?, priorZone: String?, segmentID: UUID?
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        try visitStorageRows("coach_turn") { row in
            let turn = try decode(CoachTurn.self, row.record)
            guard turn.photos.isEmpty, turn.capturedAt.timeIntervalSince1970.isFinite, turn.text.count <= 20_000,
                  let zone = TimeZone(identifier: turn.captureTimeZoneID),
                  Set(turn.photoIDs).count == turn.photoIDs.count, turn.photoIDs.count <= 30,
                  turn.assistantText == nil || turn.assistantText!.utf8.count <= 65_536,
                  turn.receipts.count <= 16, Set(turn.receipts.map(\.operationKey)).count == turn.receipts.count,
                  turn.pendingMealRevision == nil || turn.pendingMealRevision! >= 0,
                  turn.activeDayID == nil || days[turn.activeDayID!] != nil,
                  turn.resolvedDayID == nil || days[turn.resolvedDayID!] != nil else { throw DiaryError.invalidData }
            try account(turn, table: "coach_turn", row: row.record)
            let photoIDs = try migratePhotos(table: "coach_photo", parent: row.record.id, owner: "coachTurn")
            guard photoIDs.isSubset(of: turn.photoIDs) else { throw DiaryError.invalidData }
            sequence += 1
            formatter.timeZone = zone
            let day = turn.activeDayID.flatMap { days[$0] }
            let date = day?.localDate ?? formatter.string(from: turn.capturedAt)
            let displayZone = day?.timeZoneID ?? turn.captureTimeZoneID
            if segmentID == nil || priorDayID != turn.activeDayID || priorDate != date || priorZone != displayZone {
                segmentID = UUID()
                try execute("INSERT INTO coach_segment(segmentID, trackingDayID, displayLocalDate, displayTimeZoneID, firstTurnID, firstCapturedAt, firstSequence, lastSequence, preview) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    [.text(segmentID!.uuidString), turn.activeDayID.map { .text($0.uuidString) } ?? .null,
                     .text(date), .text(displayZone), .text(turn.id.uuidString), .real(turn.capturedAt.timeIntervalSinceReferenceDate),
                     .integer(sequence), .integer(sequence), .text(String(turn.text.prefix(160)))])
            } else {
                try execute("UPDATE coach_segment SET lastSequence = ? WHERE segmentID = ?", [.integer(sequence), .text(segmentID!.uuidString)])
            }
            try execute("INSERT INTO coach_index(turnID, sequence, capturedAt, captureTimeZoneID, trackingDayID, displayLocalDate, displayTimeZoneID, state, pendingMealID, segmentID) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                [.text(turn.id.uuidString), .integer(sequence), .real(turn.capturedAt.timeIntervalSinceReferenceDate), .text(turn.captureTimeZoneID),
                 turn.activeDayID.map { .text($0.uuidString) } ?? .null, .text(date), .text(displayZone), .text(turn.state.rawValue),
                 turn.pendingMealID.map { .text($0.uuidString) } ?? .null, .text(segmentID!.uuidString)])
            priorDayID = turn.activeDayID; priorDate = date; priorZone = displayZone
            try migrateTurnLinks(turn, metadata: metadata, days: days, ownPhotos: photoIDs)
        }
        try execute("UPDATE storage_head SET nextSequence = ? WHERE id = 1", [.integer(sequence + 1)])
    }

    private func migrateTurnLinks(_ turn: CoachTurn, metadata: DiarySnapshot, days: [UUID: TrackingDay], ownPhotos: Set<UUID>) throws {
        let linkedMeals = Set(turn.receipts.compactMap(\.mealID) + (turn.pendingMealID.map { [$0] } ?? []))
        for receipt in turn.receipts {
            guard receipt.turnID == turn.id, !receipt.operationKey.isEmpty, receipt.operationKey.utf8.count <= 500,
                  receipt.committedRevision > 0, receipt.committedRevision <= metadata.revision,
                  receipt.resultJSON.utf8.count <= 65_536,
                  (receipt.dayID.map { days[$0] != nil } ?? (receipt.goalID != nil || receipt.destination != nil || receipt.operationKey == "\(turn.id.uuidString)/update_preferences" || receipt.operationKey.hasPrefix("\(turn.id.uuidString)/update_preferences/"))),
                  (try? JSONSerialization.jsonObject(with: Data(receipt.resultJSON.utf8))) != nil else { throw DiaryError.invalidData }
            let foodPrefix = turn.id.uuidString + "/food/"
            let isFoodCreate = turn.pendingMealID == nil && receipt.operationKey.hasPrefix(foodPrefix) && validLocalDate(String(receipt.operationKey.dropFirst(foodPrefix.count)))
            for (kind, id) in [("meal", receipt.mealID), ("weight", receipt.weightID), ("workout", receipt.workoutID), ("goal", receipt.goalID)] {
                if let id { try addSource(kind: kind, recordID: id, turnID: turn.id, origin: kind == "meal" && isFoodCreate) }
            }
        }
        // A stable original submission is stronger origin evidence than an unrelated correction receipt.
        let submission = try prepare("SELECT parent, payload FROM submission WHERE id = ?")
        defer { sqlite3_finalize(submission) }
        sqlite3_bind_text(submission, 1, turn.id.uuidString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        if sqlite3_step(submission) == SQLITE_ROW, let parent = sqlite3_column_text(submission, 0), let bytes = sqlite3_column_blob(submission, 1) {
            let value = try JSONDecoder().decode(MealSubmission.self, from: Data(bytes: bytes, count: Int(sqlite3_column_bytes(submission, 1))))
            if value.baseRevision == 0, let id = UUID(uuidString: String(cString: parent)) { try addSource(kind: "meal", recordID: id, turnID: turn.id, origin: true) }
        }
        for photoID in turn.photoIDs {
            if ownPhotos.contains(photoID) {
                try addConsumer(owner: "coachTurn", parent: turn.id, photoID: photoID, turnID: turn.id)
            } else {
                var matches = 0
                for mealID in linkedMeals {
                    let statement = try prepare("SELECT 1 FROM photo_content WHERE ownerKind = 'meal' AND parentID = ? AND photoID = ?")
                    defer { sqlite3_finalize(statement) }
                    sqlite3_bind_text(statement, 1, mealID.uuidString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                    sqlite3_bind_text(statement, 2, photoID.uuidString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                    if sqlite3_step(statement) == SQLITE_ROW {
                        matches += 1
                        try addConsumer(owner: "meal", parent: mealID, photoID: photoID, turnID: turn.id)
                    }
                }
                guard matches > 0 else { throw DiaryError.invalidData }
            }
        }
    }

    private func addSource(kind: String, recordID: UUID, turnID: UUID, origin: Bool) throws {
        // Deleted targets keep their historical receipt but cannot acquire a live-record source.
        let statement = try prepare("SELECT 1 FROM \(kind) WHERE id = ?"); defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, recordID.uuidString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        let status = sqlite3_step(statement)
        guard status == SQLITE_ROW || status == SQLITE_DONE else { throw DiaryError.persistenceFailed }
        if status == SQLITE_ROW {
            try execute("INSERT OR IGNORE INTO record_source(kind, recordID, turnID, relation) VALUES (?, ?, ?, ?)",
                [.text(kind), .text(recordID.uuidString), .text(turnID.uuidString), .text(origin ? "origin" : "reference")])
        }
    }

    private func addConsumer(owner: String, parent: UUID, photoID: UUID, turnID: UUID) throws {
        try execute("INSERT INTO photo_consumer(ownerKind, parentID, photoID, turnID) VALUES (?, ?, ?, ?)",
            [.text(owner), .text(parent.uuidString), .text(photoID.uuidString), .text(turnID.uuidString)])
    }

    private func finishPagedAccounting(maximumBytes: Int) throws {
        for table in ["meta", "day", "meal", "submission", "item", "photo", "weight", "workout", "tombstone", "coach_turn", "coach_photo", "goal", "weight_tombstone", "workout_tombstone"] {
            let count = try storageInteger("SELECT COUNT(*) FROM \(table)")
            let statement = try prepare("SELECT COUNT(*) FROM storage_contribution WHERE tableName = ?"); defer { sqlite3_finalize(statement) }
            sqlite3_bind_text(statement, 1, table, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            guard sqlite3_step(statement) == SQLITE_ROW, sqlite3_column_int64(statement, 0) == Int64(count) else { throw DiaryError.invalidData }
            try execute("INSERT INTO storage_row_count(tableName, rowCount) VALUES (?, ?)", [.text(table), .integer(count)])
        }
        let payloads = try storageInteger("SELECT COALESCE(SUM(encodedBytes), 0) FROM storage_contribution")
        let separators = try storageInteger("SELECT COALESCE(SUM(n - 1), 0) FROM (SELECT COUNT(*) AS n FROM storage_contribution WHERE tableName != 'meta' GROUP BY tableName, parentID)")
        let originals = try storageInteger("SELECT COALESCE(SUM(originalPhotoBytes), 0) FROM storage_contribution")
        guard payloads + separators <= maximumBytes, originals <= 250_000_000,
              try storageInteger("SELECT COUNT(*) FROM coach_index") == storageInteger("SELECT COUNT(*) FROM coach_turn"),
              try storageInteger("SELECT COUNT(*) FROM photo_content") == storageInteger("SELECT COUNT(*) FROM photo") + storageInteger("SELECT COUNT(*) FROM coach_photo"),
              try storageInteger("SELECT COUNT(*) FROM pragma_foreign_key_check") == 0 else { throw DiaryError.invalidData }
        try execute("INSERT INTO storage_quota(id, portableBytes, originalPhotoBytes) VALUES (1, ?, ?)", [.integer(payloads + separators), .integer(originals)])
        for query in ["SELECT turnID FROM coach_index WHERE trackingDayID = ? ORDER BY sequence LIMIT 20",
                      "SELECT segmentID FROM coach_segment WHERE displayLocalDate = ? ORDER BY lastSequence DESC, segmentID DESC LIMIT 30",
                      "SELECT turnID FROM coach_index WHERE state = ? ORDER BY sequence LIMIT 1"] {
            let statement = try prepare("EXPLAIN QUERY PLAN " + query); defer { sqlite3_finalize(statement) }
            while sqlite3_step(statement) == SQLITE_ROW {
                if let detail = sqlite3_column_text(statement, 3) { diagnostics?.recordQueryPlan(String(cString: detail)) }
            }
        }
    }
}
