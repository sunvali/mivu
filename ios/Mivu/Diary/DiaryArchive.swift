import Foundation
import SQLite3
import CryptoKit

/// Portable profile data and inline photos; credentials and folder bookmarks never enter this envelope.
enum DiaryArchive {
    static let maximumBytes = 350_000_000
    private struct Envelope: Codable {
        var format = "mivu-diary"
        var version = 4
        var profileID: UUID
        var snapshot: DiarySnapshot
    }

    static func encode(_ snapshot: DiarySnapshot) throws -> Data {
        try validate(snapshot)
        do {
            let data = try JSONEncoder().encode(Envelope(profileID: snapshot.profile.id, snapshot: snapshot))
            guard data.count <= maximumBytes else { throw DiaryError.invalidData }
            return data
        } catch { throw DiaryError.invalidData }
    }

    static func decode(_ data: Data, expectedProfileID: UUID? = nil) throws -> DiarySnapshot {
        guard !data.isEmpty, data.count <= maximumBytes else { throw DiaryError.invalidData }
        do {
            let envelope = try JSONDecoder().decode(Envelope.self, from: data)
            guard envelope.format == "mivu-diary", [1, 2, 3, 4].contains(envelope.version) else { throw DiaryError.invalidData }
            guard envelope.profileID == envelope.snapshot.profile.id,
                  expectedProfileID == nil || expectedProfileID == envelope.profileID else { throw DiaryError.wrongOwner }
            guard envelope.version == 4 || envelope.snapshot.meals.allSatisfy({ $0.submissions.allSatisfy { $0.manualAcceptance == nil } }) else { throw DiaryError.invalidData }
            try validate(envelope.snapshot)
            return envelope.snapshot
        } catch let error as DiaryError { throw error }
        catch { throw DiaryError.invalidData }
    }

    static func readContents(_ url: URL, expectedProfileID: UUID? = nil) throws -> DiarySnapshot {
        let size = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard size.isRegularFile == true, let count = size.fileSize, count <= maximumBytes else { throw DiaryError.invalidData }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = Data()
        while let chunk = try handle.read(upToCount: min(1_000_000, maximumBytes + 1 - data.count)), !chunk.isEmpty {
            guard data.count + chunk.count <= maximumBytes else { throw DiaryError.invalidData }
            data.append(chunk)
        }
        return try decode(data, expectedProfileID: expectedProfileID)
    }

    static func read(_ url: URL, expectedProfileID: UUID? = nil) throws -> DiarySnapshot {
        try BackupFileAccess.withAccess(to: url) {
            var result: Result<DiarySnapshot, Error> = .failure(DiaryError.persistenceFailed)
            var coordinationError: NSError?
            NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError) { coordinated in
                result = Result {
                    try readContents(coordinated, expectedProfileID: expectedProfileID)
                }
            }
            if coordinationError != nil { throw DiaryError.persistenceFailed }
            return try result.get()
        }
    }

    /// Only explicit interchange calls this assembler, and only on its isolated clone.
    static func completeSnapshot(at cloneURL: URL, request: DiaryExportRequest) throws -> DiarySnapshot {
        let database = try DiaryDatabase(url: cloneURL)
        guard try database.mutationInteger("PRAGMA user_version") == request.storageVersion else { throw DiaryError.invalidData }
        if request.storageVersion == 0 { return try database.read(maximumBytes: request.maximumBytes) }
        return try database.readArchiveSnapshot(expectedProfileID: request.profileID, maximumBytes: request.maximumBytes)
    }

    static func cloneHead(at cloneURL: URL, request: DiaryExportRequest) throws -> DiaryHead {
        let database = try DiaryDatabase(url: cloneURL)
        guard try database.mutationInteger("PRAGMA user_version") == request.storageVersion else { throw DiaryError.invalidData }
        if request.storageVersion == 1 { return try database.readHead(expectedProfileID: request.profileID) }
        let value = try database.read(maximumBytes: request.maximumBytes)
        guard value.profile.id == request.profileID else { throw DiaryError.wrongOwner }
        return DiaryHead(profile: value.profile, revision: value.revision, lineage: value.lineage,
            activeDayID: value.activeDayID, previousDayConfirmedAt: value.previousDayConfirmedAt,
            timelineGeneration: request.head.timelineGeneration, activeConversationSegmentID: value.activeConversationSegmentID)
    }

    static func validate(_ snapshot: DiarySnapshot) throws {
        try snapshot.validate()
        func fingerprint(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
        for turn in snapshot.coachTurns {
            guard let manifest = turn.submissionManifest else { continue }
            guard manifest.submissionID == turn.id,
                  manifest.textFingerprint == fingerprint(Data(turn.text.utf8)),
                  manifest.context.capturedAt == turn.capturedAt,
                  manifest.context.timeZoneID == turn.captureTimeZoneID,
                  manifest.context.activeDayID == turn.activeDayID,
                  manifest.context.previousDayConfirmedAt?.timeIntervalSinceReferenceDate.isFinite != false,
                  manifest.context.activeConversationSegmentID == nil || manifest.context.activeConversationSegmentID == turn.captureSegmentID,
                  (manifest.pendingMealID == nil) == (manifest.pendingMealRevision == nil),
                  manifest.pendingMealRevision == nil || manifest.pendingMealRevision! >= 0,
                  manifest.attachments.count <= 8,
                  Set(manifest.attachments.map(\.id)).count == manifest.attachments.count else { throw DiaryError.invalidData }
            for attachment in manifest.attachments {
                guard attachment.createdAt.timeIntervalSinceReferenceDate.isFinite,
                      attachment.contentFingerprint.utf8.count == 64,
                      attachment.contentFingerprint.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw DiaryError.invalidData }
                // Accepted fingerprints describe original input, even after current pixels are replaced or transferred.
            }
        }
    }

    static func replacement(_ incoming: DiarySnapshot, original: DiarySnapshot) throws -> DiarySnapshot {
        try validate(incoming)
        guard incoming.profile.id == original.profile.id else { throw DiaryError.wrongOwner }
        guard incoming.revision >= original.revision,
              incoming == original || incoming.isVerifiedSuccessor(of: original),
              Set(incoming.meals.map(\.id)).isDisjoint(with: original.deletedMealIDs),
              Set(incoming.weights.map(\.id)).isDisjoint(with: original.deletedWeightIDs),
              Set(incoming.workouts.map(\.id)).isDisjoint(with: original.deletedWorkoutIDs) else { throw DiaryError.staleArchive }
        var result = incoming
        result.deletedMealIDs = Array(Set(incoming.deletedMealIDs + original.deletedMealIDs)).sorted { $0.uuidString < $1.uuidString }
        result.deletedWeightIDs = Array(Set(incoming.deletedWeightIDs + original.deletedWeightIDs)).sorted { $0.uuidString < $1.uuidString }
        result.deletedWorkoutIDs = Array(Set(incoming.deletedWorkoutIDs + original.deletedWorkoutIDs)).sorted { $0.uuidString < $1.uuidString }
        result.revision = max(incoming.revision, original.revision) + 1
        result.lineage = Array((incoming.lineage ?? []).suffix(255)) + [UUID()]
        return result
    }
}

private extension DiaryDatabase {
    func archiveRows(_ table: String, sequenceOrder: Bool = false) throws -> [Record] {
        let parent = ["meal", "submission", "item", "photo", "weight", "workout", "coach_photo"].contains(table)
        let photo = ["photo", "coach_photo"].contains(table)
        let query = sequenceOrder
            ? "SELECT t.id, t.ordinal, t.payload, NULL, NULL FROM coach_turn t JOIN coach_index i ON i.turnID = t.id ORDER BY i.sequence"
            : "SELECT id, ordinal, payload, \(parent ? "parent" : "NULL"), \(photo ? "bytes" : "NULL") FROM \(table) ORDER BY ordinal, id"
        let statement = try prepare(query); defer { sqlite3_finalize(statement) }
        var result: [Record] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return result }
            guard status == SQLITE_ROW, let id = sqlite3_column_text(statement, 0),
                  sqlite3_column_type(statement, 1) == SQLITE_INTEGER,
                  sqlite3_column_int64(statement, 1) >= 0,
                  sqlite3_column_type(statement, 2) == SQLITE_BLOB else { throw DiaryError.invalidData }
            func bytes(_ column: Int32) -> Data {
                guard let pointer = sqlite3_column_blob(statement, column) else { return Data() }
                return Data(bytes: pointer, count: Int(sqlite3_column_bytes(statement, column)))
            }
            result.append(Record(id: String(cString: id), ordinal: Int(sqlite3_column_int64(statement, 1)),
                payload: bytes(2), parent: sqlite3_column_text(statement, 3).map { String(cString: $0) }, bytes: bytes(4)))
        }
    }

    func readArchiveSnapshot(expectedProfileID: UUID, maximumBytes: Int) throws -> DiarySnapshot {
        try execute("BEGIN")
        defer { try? execute("ROLLBACK") }
        // The physical scan still validates old meta's row, but its retired payload is not part of v1 portable size.
        let legacyBytes = try mutationInteger("SELECT COALESCE(SUM(length(payload)),0) FROM meta")
        let (physicalCeiling, overflow) = maximumBytes.addingReportingOverflow(legacyBytes)
        guard legacyBytes >= 0, !overflow else { throw DiaryError.invalidData }
        try preflight(maximumBytes: physicalCeiling)
        guard try mutationInteger("SELECT COUNT(*) FROM pragma_foreign_key_check") == 0,
              try mutationInteger("SELECT COUNT(*) FROM storage_head") == 1 else { throw DiaryError.invalidData }
        let head = try readHead(expectedProfileID: expectedProfileID)
        var snapshot = DiarySnapshot(revision: head.revision, profile: head.profile,
            activeDayID: head.activeDayID, previousDayConfirmedAt: head.previousDayConfirmedAt,
            lineage: head.lineage, activeConversationSegmentID: head.activeConversationSegmentID)
        snapshot.days = try archiveRows("day").map { try decode(TrackingDay.self, $0) }
        let submissions = try archiveRows("submission"), items = try archiveRows("item"), photos = try archiveRows("photo")
        let groupedSubmissions = Dictionary(grouping: submissions, by: \.parent)
        let groupedItems = Dictionary(grouping: items, by: \.parent)
        let groupedPhotos = Dictionary(grouping: photos, by: \.parent)
        var consumedSubmissions = 0, consumedItems = 0, consumedPhotos = 0
        snapshot.meals = try archiveRows("meal").map { row in
            var meal = try decode(DiaryMeal.self, row)
            guard row.parent == meal.dayID.uuidString, meal.submissions.isEmpty,
                  meal.items.isEmpty, meal.photos.isEmpty else { throw DiaryError.invalidData }
            let children = groupedSubmissions[row.id] ?? [], food = groupedItems[row.id] ?? [], originals = groupedPhotos[row.id] ?? []
            consumedSubmissions += children.count; consumedItems += food.count; consumedPhotos += originals.count
            meal.submissions = try children.map { try decode(MealSubmission.self, $0) }
            meal.items = try food.map { try decode(FoodItem.self, $0, composite: true) }
            meal.photos = try originals.map(archivePhoto)
            return meal
        }
        guard consumedSubmissions == submissions.count, consumedItems == items.count,
              consumedPhotos == photos.count else { throw DiaryError.invalidData }
        snapshot.weights = try archiveRows("weight").map { row in
            let value = try decode(WeightEntry.self, row)
            guard row.parent == value.dayID?.uuidString else { throw DiaryError.invalidData }
            return value
        }
        snapshot.workouts = try archiveRows("workout").map { row in
            let value = try decode(WorkoutSession.self, row)
            guard row.parent == value.dayID.uuidString else { throw DiaryError.invalidData }
            return value
        }
        for (table, limit) in [("goal", 10_000), ("weight_tombstone", 10_000), ("workout_tombstone", 50_000)] {
            let count = try mutationInteger("SELECT COUNT(*) FROM \(table)")
            guard count <= limit,
                  try mutationInteger("SELECT COALESCE(SUM(length(payload)),0) FROM \(table)") <= maximumBytes else { throw DiaryError.invalidData }
        }
        snapshot.goals = try archiveRows("goal").map { try decode(GoalRecord.self, $0) }
        func tombstones(_ table: String) throws -> [UUID] {
            try archiveRows(table).map { row in
                let value = try JSONDecoder().decode(UUID.self, from: row.payload)
                guard row.id == value.uuidString else { throw DiaryError.invalidData }
                return value
            }
        }
        snapshot.deletedMealIDs = try tombstones("tombstone")
        snapshot.deletedWeightIDs = try tombstones("weight_tombstone")
        snapshot.deletedWorkoutIDs = try tombstones("workout_tombstone")
        let coachPhotos = try archiveRows("coach_photo")
        let groupedCoachPhotos = Dictionary(grouping: coachPhotos, by: \.parent)
        let turns = try archiveRows("coach_turn", sequenceOrder: true)
        guard turns.count == (try mutationInteger("SELECT COUNT(*) FROM coach_turn")),
              turns.count == (try mutationInteger("SELECT COUNT(*) FROM coach_index")) else { throw DiaryError.invalidData }
        var consumedCoachPhotos = 0
        snapshot.coachTurns = try turns.map { row in
            var turn = try decode(CoachTurn.self, row)
            guard turn.photos.isEmpty else { throw DiaryError.invalidData }
            let children = groupedCoachPhotos[row.id] ?? []; consumedCoachPhotos += children.count
            turn.photos = try children.map(archivePhoto)
            return turn
        }
        guard consumedCoachPhotos == coachPhotos.count else { throw DiaryError.invalidData }
        let index = try prepare("SELECT turnID,sequence,capturedAt,captureTimeZoneID,trackingDayID,state,pendingMealID,segmentID FROM coach_index ORDER BY sequence")
        defer { sqlite3_finalize(index) }
        var priorSequence: Int64 = 0
        for turn in snapshot.coachTurns {
            guard sqlite3_step(index) == SQLITE_ROW,
                  try mutationText(index, 0) == turn.id.uuidString,
                  sqlite3_column_int64(index, 1) > priorSequence,
                  sqlite3_column_double(index, 2) == turn.capturedAt.timeIntervalSinceReferenceDate,
                  try mutationText(index, 3) == turn.captureTimeZoneID,
                  try mutationOptionalUUID(index, 4) == turn.activeDayID,
                  try mutationText(index, 5) == turn.state.rawValue,
                  try mutationOptionalUUID(index, 6) == turn.pendingMealID,
                  try (turn.captureSegmentID == nil || turn.captureSegmentID == mutationOptionalUUID(index, 7)) else { throw DiaryError.invalidData }
            priorSequence = sqlite3_column_int64(index, 1)
        }
        guard sqlite3_step(index) == SQLITE_DONE else { throw DiaryError.invalidData }
        try DiaryArchive.validate(snapshot)
        let encodedBytes = try JSONEncoder().encode(snapshot).count
        let originalBytes = snapshot.meals.flatMap(\.photos).reduce(0) { $0 + $1.data.count }
            + snapshot.coachTurns.flatMap(\.photos).reduce(0) { $0 + $1.data.count }
        guard encodedBytes <= maximumBytes,
              encodedBytes == (try mutationInteger("SELECT portableBytes FROM storage_quota WHERE id=1")),
              originalBytes == (try mutationInteger("SELECT originalPhotoBytes FROM storage_quota WHERE id=1")) else { throw DiaryError.invalidData }
        try execute("COMMIT")
        return snapshot
    }

    func archivePhoto(_ row: Record) throws -> MealPhoto {
        var photo = try decode(MealPhoto.self, row, composite: true)
        guard photo.data.isEmpty else { throw DiaryError.invalidData }
        photo.data = row.bytes
        return photo
    }
}

/// The only security-scoped access boundary; the resource is held through synchronous file coordination.
enum BackupFileAccess {
    static func withAccess<T>(to url: URL, _ operation: () throws -> T) throws -> T {
        let accessed = url.startAccessingSecurityScopedResource()
        let path = url.standardizedFileURL.path
        let ownedRoots = [NSHomeDirectory(), FileManager.default.temporaryDirectory.standardizedFileURL.path]
        let owned = ownedRoots.contains { path == $0 || path.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }
        return try withAccess(acquired: accessed, requiresAccess: !owned,
            stop: { url.stopAccessingSecurityScopedResource() }, operation)
    }

    static func withAccess<T>(acquired: Bool, requiresAccess: Bool, stop: () -> Void, _ operation: () throws -> T) throws -> T {
        guard acquired || !requiresAccess else { throw DiaryError.persistenceFailed }
        defer { if acquired { stop() } }
        return try operation()
    }
}
