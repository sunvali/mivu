import Foundation
import SQLite3
import CryptoKit

extension DiaryDatabase {
    func readHead(expectedProfileID: UUID) throws -> DiaryHead {
        try validateFileIdentity()
        guard try mutationInteger("PRAGMA user_version") == 1 else { throw DiaryError.invalidData }
        let statement = try mutationStatement("SELECT schemaVersion, profileID, profilePayload, revision, lineagePayload, activeDayID, previousDayConfirmedAt, timelineGeneration, activeConversationSegmentID FROM storage_head WHERE id = 1")
        defer { sqlite3_finalize(statement) }
        guard try mutationStep(statement), try mutationText(statement, 1) == expectedProfileID.uuidString else { throw DiaryError.wrongOwner }
        let profile = try JSONDecoder().decode(DiaryProfile.self, from: mutationBlob(statement, 2))
        guard profile.id == expectedProfileID,
              let generation = UUID(uuidString: try mutationText(statement, 7)) else { throw DiaryError.invalidData }
        let lineage = try sqlite3_column_type(statement, 4) == SQLITE_NULL ? nil : JSONDecoder().decode([UUID].self, from: mutationBlob(statement, 4))
        let confirmation = sqlite3_column_type(statement, 6) == SQLITE_NULL ? nil : Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 6))
        let revision = Int(sqlite3_column_int64(statement, 3))
        try validateDiaryMetadataFields(schemaVersion: Int(sqlite3_column_int64(statement, 0)), revision: revision,
            profile: profile, lineage: lineage, previousDayConfirmedAt: confirmation)
        var head = DiaryHead(profile: profile, revision: revision, lineage: lineage,
            activeDayID: try mutationOptionalUUID(statement, 5), previousDayConfirmedAt: confirmation, timelineGeneration: generation,
            activeConversationSegmentID: try mutationOptionalUUID(statement, 8))
        head.effectiveConversationSegmentID = try effectiveConversationSegmentID(for: head)
        return head
    }

    func trackingDay(id: UUID) throws -> TrackingDay {
        let statement = try mutationStatement("SELECT payload FROM day WHERE id = ?", [.text(id.uuidString)])
        defer { sqlite3_finalize(statement) }
        guard try mutationStep(statement) else { throw DiaryError.notFound }
        let day = try decode(TrackingDay.self, Record(id: id.uuidString, ordinal: 0, payload: mutationBlob(statement, 0)))
        try validateTrackingDayFields(day)
        return day
    }

    struct CaptureSegment {
        var id: UUID
        var dayID: UUID?
        var date: String
        var zone: String
        var lastSequence: Int
    }

    func captureSegment(id: UUID? = nil) throws -> CaptureSegment? {
        let statement = try mutationStatement("SELECT segmentID, trackingDayID, displayLocalDate, displayTimeZoneID, lastSequence FROM coach_segment \(id == nil ? "ORDER BY lastSequence DESC, segmentID DESC LIMIT 1" : "WHERE segmentID = ?")",
            id.map { [.text($0.uuidString)] } ?? [])
        defer { sqlite3_finalize(statement) }
        guard try mutationStep(statement) else { return nil }
        guard let segmentID = UUID(uuidString: try mutationText(statement, 0)) else { throw DiaryError.invalidData }
        return CaptureSegment(id: segmentID, dayID: try mutationOptionalUUID(statement, 1), date: try mutationText(statement, 2),
            zone: try mutationText(statement, 3), lastSequence: Int(sqlite3_column_int64(statement, 4)))
    }

    /// Raw legacy nil remains portable nil. Only available day/last-run evidence supplies a context token.
    func effectiveConversationSegmentID(for head: DiaryHead) throws -> UUID? {
        guard let dayID = head.activeDayID else {
            guard head.activeConversationSegmentID == nil else { throw DiaryError.invalidData }
            return nil
        }
        let day = try trackingDay(id: dayID)
        let last = try captureSegment()
        if let raw = head.activeConversationSegmentID {
            if let segment = try captureSegment(id: raw) {
                guard segment.id == last?.id, segment.dayID == dayID, segment.date == day.localDate,
                      segment.zone == day.timeZoneID else { throw DiaryError.invalidData }
            }
            return raw
        }
        if let last, last.dayID == dayID, last.date == day.localDate, last.zone == day.timeZoneID { return last.id }
        return try inferredEmptyConversationSegmentID(for: head)
    }

    private func inferredEmptyConversationSegmentID(for head: DiaryHead) throws -> UUID {
        struct Seed: Encodable {
            let domain = "mivu.coach.empty-segment.v1"
            var timelineGeneration: UUID
            var profileID: UUID
            var dayID: UUID
            var attempt: Int
        }
        guard let dayID = head.activeDayID else { throw DiaryError.invalidData }
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        // The turn quota bounds populated segments and the maximum probe count.
        for attempt in 0...10_000 {
            let seed = Seed(timelineGeneration: head.timelineGeneration, profileID: head.profile.id, dayID: dayID, attempt: attempt)
            var bytes = Array(SHA256.hash(data: try encoder.encode(seed)).prefix(16))
            bytes[6] = (bytes[6] & 0x0f) | 0x80; bytes[8] = (bytes[8] & 0x3f) | 0x80
            let id = UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                                 bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
            if try captureSegment(id: id) == nil { return id }
        }
        throw DiaryError.invalidData
    }

    func captureCoachSubmission(_ payload: CoachSubmissionPayload, expected: DiaryHead,
                                maximumBytes: Int) throws -> DiaryCommit<CoachExchangeSummary> {
        try transaction(expected: expected, maximumBytes: maximumBytes) { transaction in
            if let existing = try transaction.turn(id: payload.submissionID) {
                guard existing.submissionManifest == payload.manifest else { throw DiaryError.staleRevision }
            } else {
                guard payload.context.timeZoneID == expected.profile.timeZoneID,
                      payload.context.activeDayID == expected.activeDayID,
                      payload.context.previousDayConfirmedAt == expected.previousDayConfirmedAt,
                      payload.context.activeConversationSegmentID == expected.effectiveConversationSegmentID else { throw DiaryError.staleRevision }
                // Pending meal adapters compose their own validated meal/turn batch in the next stage.
                guard payload.manifest.pendingMealID == nil else { throw DiaryError.invalidData }
                try transaction.appendCapture(payload)
            }
            return try coachExchangeSummary(turnID: payload.submissionID, expectedProfileID: expected.profile.id)
        }
    }

    func updateCoachTurn(turnID: UUID, state: CoachTurnState, assistantText: String?, needsDayChoice: Bool,
                         expected: DiaryHead, maximumBytes: Int) throws -> DiaryCommit<CoachExchangeSummary> {
        try transaction(expected: expected, maximumBytes: maximumBytes) { transaction in
            guard var turn = try transaction.turn(id: turnID) else { throw DiaryError.notFound }
            turn.state = state; turn.assistantText = assistantText
            turn.needsDayChoice = state == .needsClarification && needsDayChoice ? true : nil
            try transaction.saveTurn(turn)
            return try coachExchangeSummary(turnID: turnID, expectedProfileID: expected.profile.id)
        }
    }

    func reconcileCoachCapture(submissionID: UUID, expectedManifest: CoachSubmissionManifest,
                               expectedProfileID: UUID) throws -> CoachCaptureReconciliation {
        try validateFileIdentity()
        try execute("BEGIN")
        do {
            let transaction = DiaryTransaction(database: self, head: try readHead(expectedProfileID: expectedProfileID))
            let result: CoachCaptureReconciliation
            if let turn = try transaction.turn(id: submissionID) {
                if expectedManifest.submissionID == submissionID, turn.submissionManifest == expectedManifest {
                    result = .accepted(try coachExchangeSummary(turnID: submissionID, expectedProfileID: expectedProfileID))
                } else { result = .conflictingPayload }
            } else { result = .absent }
            try validateFileIdentity()
            try execute("COMMIT")
            return result
        } catch { try? execute("ROLLBACK"); throw error }
    }

    /// One owner of BEGIN/COMMIT; meal/progress batches compose the same touched-row primitives.
    func transaction<Value: Sendable>(expected: DiaryHead, maximumBytes: Int,
                                     _ body: (DiaryTransaction) throws -> Value) throws -> DiaryCommit<Value> {
        try validateFileIdentity()
        try execute("BEGIN IMMEDIATE")
        do {
            guard try readHead(expectedProfileID: expected.profile.id) == expected else { throw DiaryError.staleRevision }
            let transaction = DiaryTransaction(database: self, head: expected)
            let value = try body(transaction)
            try transaction.finish(maximumBytes: min(maximumBytes, 350_000_000))
            try validateFileIdentity()
            try execute("COMMIT")
            return DiaryCommit(value: value, head: transaction.head, changes: transaction.changes)
        } catch { try? execute("ROLLBACK"); throw error }
    }

    func mutationStatement(_ sql: String, _ values: [Value] = []) throws -> OpaquePointer {
        let statement = try prepare(sql)
        do {
            for (index, value) in values.enumerated() {
                let position = Int32(index + 1), transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
                let status: Int32
                switch value {
                case .text(let text): status = sqlite3_bind_text(statement, position, text, Int32(text.utf8.count), transient)
                case .blob(let data): status = data.withUnsafeBytes { sqlite3_bind_blob(statement, position, $0.baseAddress, Int32($0.count), transient) }
                case .integer(let value): status = sqlite3_bind_int64(statement, position, Int64(value))
                case .real(let value): status = sqlite3_bind_double(statement, position, value)
                case .null: status = sqlite3_bind_null(statement, position)
                }
                guard status == SQLITE_OK else { throw DiaryError.persistenceFailed }
            }
            return statement
        } catch { sqlite3_finalize(statement); throw error }
    }

    func mutationInteger(_ sql: String, _ values: [Value] = []) throws -> Int {
        let statement = try mutationStatement(sql, values); defer { sqlite3_finalize(statement) }
        guard try mutationStep(statement) else { throw DiaryError.invalidData }
        return Int(sqlite3_column_int64(statement, 0))
    }

    func mutationStep(_ statement: OpaquePointer) throws -> Bool {
        let status = sqlite3_step(statement)
        guard status == SQLITE_ROW || status == SQLITE_DONE else { throw DiaryError.persistenceFailed }
        return status == SQLITE_ROW
    }
    func mutationText(_ statement: OpaquePointer, _ column: Int32) throws -> String {
        guard let bytes = sqlite3_column_text(statement, column),
              let text = String(bytes: UnsafeBufferPointer(start: bytes, count: Int(sqlite3_column_bytes(statement, column))), encoding: .utf8) else { throw DiaryError.invalidData }
        return text
    }
    func mutationBlob(_ statement: OpaquePointer, _ column: Int32) throws -> Data {
        guard let bytes = sqlite3_column_blob(statement, column) else { throw DiaryError.invalidData }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, column)))
    }
    func mutationOptionalUUID(_ statement: OpaquePointer, _ column: Int32) throws -> UUID? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL else { return nil }
        guard let id = UUID(uuidString: try mutationText(statement, column)) else { throw DiaryError.invalidData }
        return id
    }
}

/// Synchronous, connection-local state. It never escapes the owning transaction.
final class DiaryTransaction {
    let database: DiaryDatabase
    private let originalHead: DiaryHead
    var head: DiaryHead
    var changes = DiaryChanges()
    private var changed = false

    init(database: DiaryDatabase, head: DiaryHead) { self.database = database; self.originalHead = head; self.head = head }

    func turn(id: UUID) throws -> CoachTurn? {
        let statement = try database.mutationStatement("SELECT payload FROM coach_turn WHERE id = ?", [.text(id.uuidString)])
        defer { sqlite3_finalize(statement) }
        guard try database.mutationStep(statement) else { return nil }
        let turn = try database.decode(CoachTurn.self, DiaryDatabase.Record(id: id.uuidString, ordinal: 0,
            payload: database.mutationBlob(statement, 0)))
        try validateCoachTurnFields(turn)
        guard turn.photos.isEmpty else { throw DiaryError.invalidData }
        for receipt in turn.receipts { try validateCoachReceiptFields(receipt, turnID: id, revision: head.revision) }
        return turn
    }

    func saveTurn(_ turn: CoachTurn) throws {
        try validateCoachTurnFields(turn)
        guard turn.photos.isEmpty, let original = try self.turn(id: turn.id) else { throw DiaryError.notFound }
        guard original.submissionManifest == turn.submissionManifest, original.capturedAt == turn.capturedAt,
              original.captureTimeZoneID == turn.captureTimeZoneID, original.activeDayID == turn.activeDayID,
              original.text == turn.text, original.captureSegmentID == turn.captureSegmentID else { throw DiaryError.staleRevision }
        for receipt in turn.receipts { try validateCoachReceiptFields(receipt, turnID: turn.id, revision: head.revision + 1) }
        let payload = try JSONEncoder().encode(turn)
        try database.execute("UPDATE coach_turn SET payload = ? WHERE id = ?", [.blob(payload), .text(turn.id.uuidString)])
        guard sqlite3_changes(database.connection) == 1 else { throw DiaryError.notFound }
        try database.execute("UPDATE coach_index SET state = ?, pendingMealID = ? WHERE turnID = ?",
            [.text(turn.state.rawValue), turn.pendingMealID.map { .text($0.uuidString) } ?? .null, .text(turn.id.uuidString)])
        guard sqlite3_changes(database.connection) == 1 else { throw DiaryError.invalidData }
        try contribution(table: "coach_turn", rowID: turn.id.uuidString, encodedBytes: payload.count)
        changes.turnIDs.insert(turn.id)
    }

    func appendCapture(_ payload: CoachSubmissionPayload) throws {
        let sequence = try database.mutationInteger("SELECT nextSequence FROM storage_head WHERE id = 1")
        guard sequence > 0, sequence < Int.max else { throw DiaryError.invalidData }
        let ordinal = try database.mutationInteger("SELECT rowCount FROM storage_row_count WHERE tableName = 'coach_turn'")
        guard ordinal < 10_000 else { throw DiaryError.invalidData }
        let last = try database.captureSegment()
        let day = try head.activeDayID.map { try database.trackingDay(id: $0) }
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: payload.context.timeZoneID)
        let date = day?.localDate ?? formatter.string(from: payload.context.capturedAt)
        let zone = day?.timeZoneID ?? payload.context.timeZoneID
        guard validLocalDate(date) else { throw DiaryError.invalidData }
        let segmentID: UUID
        if day != nil {
            guard let effective = head.effectiveConversationSegmentID else { throw DiaryError.invalidData }
            segmentID = effective
            head.activeConversationSegmentID = effective
        } else if let last, last.dayID == nil, last.date == date, last.zone == zone {
            segmentID = last.id
        } else { segmentID = UUID() }
        let turn = CoachTurn(id: payload.submissionID, capturedAt: payload.context.capturedAt, text: payload.text,
            captureTimeZoneID: payload.context.timeZoneID, activeDayID: payload.context.activeDayID,
            photoIDs: payload.attachments.map(\.id), submissionManifest: payload.manifest, captureSegmentID: segmentID)
        try validateCoachTurnFields(turn)
        let encoded = try JSONEncoder().encode(turn)
        try database.execute("INSERT INTO coach_turn(id, ordinal, payload) VALUES (?, ?, ?)",
            [.text(turn.id.uuidString), .integer(ordinal), .blob(encoded)])
        try contribution(table: "coach_turn", rowID: turn.id.uuidString, encodedBytes: encoded.count)
        for (ordinal, original) in payload.attachments.enumerated() {
            let physicalID = turn.id.uuidString + "/" + original.id.uuidString
            var metadata = original; metadata.data = Data()
            try database.execute("INSERT INTO coach_photo(id, parent, ordinal, payload, bytes) VALUES (?, ?, ?, ?, ?)",
                [.text(physicalID), .text(turn.id.uuidString), .integer(ordinal), .blob(try JSONEncoder().encode(metadata)), .blob(original.data)])
            try contribution(table: "coach_photo", rowID: physicalID, parentID: turn.id.uuidString,
                encodedBytes: JSONEncoder().encode(original).count, originalPhotoBytes: original.data.count)
            try database.execute("INSERT INTO photo_content(ownerKind, parentID, photoID, physicalID, contentToken, mealPhysicalID, coachPhysicalID) VALUES ('coachTurn', ?, ?, ?, ?, NULL, ?)",
                [.text(turn.id.uuidString), .text(original.id.uuidString), .text(physicalID), .text(UUID().uuidString), .text(physicalID)])
            try database.execute("INSERT INTO photo_consumer(ownerKind, parentID, photoID, turnID) VALUES ('coachTurn', ?, ?, ?)",
                [.text(turn.id.uuidString), .text(original.id.uuidString), .text(turn.id.uuidString)])
        }
        try appendCaptureIndex(turn, sequence: sequence, segmentID: segmentID, date: date, zone: zone, last: last)
        try database.execute("UPDATE storage_head SET nextSequence = ? WHERE id = 1", [.integer(sequence + 1)])
        changes.turnIDs.insert(turn.id)
        changes.coachLatestChanged = true
    }

    private func appendCaptureIndex(_ turn: CoachTurn, sequence: Int, segmentID: UUID, date: String, zone: String,
                                    last: DiaryDatabase.CaptureSegment?) throws {
        if let segment = try database.captureSegment(id: segmentID) {
            guard segment.id == last?.id, segment.dayID == turn.activeDayID, segment.date == date,
                  segment.zone == zone, segment.lastSequence == sequence - 1 else { throw DiaryError.invalidData }
            try database.execute("UPDATE coach_segment SET lastSequence = ? WHERE segmentID = ?", [.integer(sequence), .text(segmentID.uuidString)])
        } else {
            try database.execute("INSERT INTO coach_segment(segmentID, trackingDayID, displayLocalDate, displayTimeZoneID, firstTurnID, firstCapturedAt, firstSequence, lastSequence, preview) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                [.text(segmentID.uuidString), turn.activeDayID.map { .text($0.uuidString) } ?? .null, .text(date), .text(zone),
                 .text(turn.id.uuidString), .real(turn.capturedAt.timeIntervalSinceReferenceDate), .integer(sequence), .integer(sequence), .text(String(turn.text.prefix(160)))])
        }
        try database.execute("INSERT INTO coach_index(turnID, sequence, capturedAt, captureTimeZoneID, trackingDayID, displayLocalDate, displayTimeZoneID, state, pendingMealID, segmentID) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            [.text(turn.id.uuidString), .integer(sequence), .real(turn.capturedAt.timeIntervalSinceReferenceDate), .text(turn.captureTimeZoneID),
             turn.activeDayID.map { .text($0.uuidString) } ?? .null, .text(date), .text(zone), .text(turn.state.rawValue),
             turn.pendingMealID.map { .text($0.uuidString) } ?? .null, .text(segmentID.uuidString)])
    }

    /// Exact portable-encoding deltas; only the touched row and its indexed sibling count are read.
    func contribution(table: String, rowID: String, parentID: String? = nil, encodedBytes: Int,
                      originalPhotoBytes: Int = 0) throws {
        guard encodedBytes > 0, originalPhotoBytes >= 0 else { throw DiaryError.invalidData }
        let values: [DiaryDatabase.Value] = [.text(table), .text(rowID)]
        let statement = try database.mutationStatement("SELECT encodedBytes, originalPhotoBytes, parentID FROM storage_contribution WHERE tableName = ? AND rowID = ?", values)
        defer { sqlite3_finalize(statement) }
        let exists = try database.mutationStep(statement)
        let oldBytes = exists ? Int(sqlite3_column_int64(statement, 0)) : 0
        let oldOriginals = exists ? Int(sqlite3_column_int64(statement, 1)) : 0
        if exists {
            let oldParent = sqlite3_column_type(statement, 2) == SQLITE_NULL ? nil : try database.mutationText(statement, 2)
            guard oldParent == parentID else { throw DiaryError.invalidData }
        }
        var separator = 0
        if !exists {
            let count = try database.mutationInteger("SELECT rowCount FROM storage_row_count WHERE tableName = ?", [.text(table)])
            let limits = ["meta": 1, "day": 10_000, "meal": 50_000, "submission": 50_000_000, "item": 10_000_000,
                "photo": 1_500_000, "weight": 10_000, "workout": 50_000, "tombstone": 50_000,
                "coach_turn": 10_000, "coach_photo": 300_000, "goal": 10_000, "weight_tombstone": 10_000, "workout_tombstone": 50_000]
            guard let limit = limits[table], count < limit else { throw DiaryError.invalidData }
            if table != "meta" {
                let siblings = try parentID.map { parent in
                    try database.mutationInteger("SELECT COUNT(*) FROM storage_contribution WHERE tableName = ? AND parentID = ?",
                        [.text(table), .text(parent)])
                } ?? count
                separator = siblings > 0 ? 1 : 0
                if let limit = ["submission": 1000, "item": 200, "photo": 30, "coach_photo": 30][table] {
                    guard siblings < limit else { throw DiaryError.invalidData }
                }
            }
            try database.execute("UPDATE storage_row_count SET rowCount = rowCount + 1 WHERE tableName = ?", [.text(table)])
        }
        try database.execute("INSERT INTO storage_contribution(tableName, rowID, parentID, encodedBytes, originalPhotoBytes) VALUES (?, ?, ?, ?, ?) ON CONFLICT(tableName, rowID) DO UPDATE SET encodedBytes = excluded.encodedBytes, originalPhotoBytes = excluded.originalPhotoBytes",
            [.text(table), .text(rowID), parentID.map(DiaryDatabase.Value.text) ?? .null, .integer(encodedBytes), .integer(originalPhotoBytes)])
        try database.execute("UPDATE storage_quota SET portableBytes = portableBytes + ?, originalPhotoBytes = originalPhotoBytes + ? WHERE id = 1",
            [.integer(encodedBytes - oldBytes + separator), .integer(originalPhotoBytes - oldOriginals)])
        changed = true
    }

    /// Remove one exact portable contribution before its physical row/cascade disappears.
    func removeContribution(table: String, rowID: String) throws {
        let statement = try database.mutationStatement("SELECT encodedBytes, originalPhotoBytes, parentID FROM storage_contribution WHERE tableName = ? AND rowID = ?", [.text(table), .text(rowID)])
        defer { sqlite3_finalize(statement) }
        guard try database.mutationStep(statement) else { throw DiaryError.invalidData }
        let bytes = Int(sqlite3_column_int64(statement, 0)), originals = Int(sqlite3_column_int64(statement, 1))
        let parent = sqlite3_column_type(statement, 2) == SQLITE_NULL ? nil : try database.mutationText(statement, 2)
        let siblings = try parent.map { parent in
            try database.mutationInteger("SELECT COUNT(*) FROM storage_contribution WHERE tableName = ? AND parentID = ?", [.text(table), .text(parent)])
        } ?? database.mutationInteger("SELECT rowCount FROM storage_row_count WHERE tableName = ?", [.text(table)])
        guard table != "meta", siblings > 0 else { throw DiaryError.invalidData }
        try database.execute("DELETE FROM storage_contribution WHERE tableName = ? AND rowID = ?", [.text(table), .text(rowID)])
        try database.execute("UPDATE storage_row_count SET rowCount = rowCount - 1 WHERE tableName = ?", [.text(table)])
        try database.execute("UPDATE storage_quota SET portableBytes = portableBytes - ?, originalPhotoBytes = originalPhotoBytes - ? WHERE id = 1", [.integer(bytes + (siblings > 1 ? 1 : 0)), .integer(originals)])
        changed = true
    }

    func finish(maximumBytes: Int) throws {
        guard changed || head != originalHead else { return }
        guard head.profile.id == originalHead.profile.id, head.timelineGeneration == originalHead.timelineGeneration,
              head.revision == originalHead.revision, head.lineage == originalHead.lineage else { throw DiaryError.staleRevision }
        let previousRevision = originalHead.revision
        head.revision = previousRevision + 1
        head.lineage = Array((originalHead.lineage ?? []).suffix(255)) + [UUID()]
        try validateDiaryMetadataFields(schemaVersion: 1, revision: head.revision, profile: head.profile,
            lineage: head.lineage, previousDayConfirmedAt: head.previousDayConfirmedAt)
        head.effectiveConversationSegmentID = try database.effectiveConversationSegmentID(for: head)
        if head.activeDayID != originalHead.activeDayID || head.activeConversationSegmentID != originalHead.activeConversationSegmentID {
            changes.coachLatestChanged = true
        }
        try database.execute("UPDATE storage_head SET profilePayload = ?, revision = ?, lineagePayload = ?, activeDayID = ?, previousDayConfirmedAt = ?, activeConversationSegmentID = ? WHERE id = 1 AND revision = ?",
            [.blob(try JSONEncoder().encode(head.profile)), .integer(head.revision), .blob(try JSONEncoder().encode(head.lineage)),
             head.activeDayID.map { .text($0.uuidString) } ?? .null, head.previousDayConfirmedAt.map { .real($0.timeIntervalSinceReferenceDate) } ?? .null,
             head.activeConversationSegmentID.map { .text($0.uuidString) } ?? .null, .integer(previousRevision)])
        guard sqlite3_changes(database.connection) == 1 else { throw DiaryError.staleRevision }
        try contribution(table: "meta", rowID: head.profile.id.uuidString, encodedBytes: JSONEncoder().encode(PortableMetadata(head)).count)
        guard maximumBytes > 0,
              try database.mutationInteger("SELECT portableBytes FROM storage_quota WHERE id = 1") <= maximumBytes,
              try database.mutationInteger("SELECT originalPhotoBytes FROM storage_quota WHERE id = 1") <= 250_000_000 else { throw DiaryError.invalidData }
    }

    /// Interchange encoding overhead for quota only, never a partial snapshot/read projection.
    private struct PortableMetadata: Encodable {
        var schemaVersion = 1
        var revision: Int
        var profile: DiaryProfile
        var days: [TrackingDay] = []
        var meals: [DiaryMeal] = []
        var weights: [WeightEntry] = []
        var goals: [GoalRecord] = []
        var workouts: [WorkoutSession] = []
        var coachTurns: [CoachTurn] = []
        var activeDayID: UUID?
        var previousDayConfirmedAt: Date?
        var deletedMealIDs: [UUID] = []
        var deletedWeightIDs: [UUID] = []
        var deletedWorkoutIDs: [UUID] = []
        var lineage: [UUID]?
        var activeConversationSegmentID: UUID?
        init(_ head: DiaryHead) {
            revision = head.revision; profile = head.profile; activeDayID = head.activeDayID
            previousDayConfirmedAt = head.previousDayConfirmedAt; lineage = head.lineage
            activeConversationSegmentID = head.activeConversationSegmentID
        }
    }
}
