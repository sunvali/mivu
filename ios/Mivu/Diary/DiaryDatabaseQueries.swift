import Foundation
import SQLite3

extension DiaryDatabase {
    /// The caller owns the read/write transaction; this never opens a nested transaction.
    func coachExchangeSummary(turnID: UUID, expectedProfileID: UUID) throws -> CoachExchangeSummary {
        let context = try coachContext(expectedProfileID: expectedProfileID)
        guard let row = try coachIndexRows("turnID = ?", values: [.text(turnID.uuidString)], limit: 1).first else { throw DiaryError.notFound }
        return try coachExchange(row, context: context)
    }

    func coachPage(_ request: CoachPageRequest, expectedProfileID: UUID) throws -> CoachPage {
        diagnostics?.recordCoachPageRead()
        return try coachRead {
            let context = try coachContext(expectedProfileID: expectedProfileID)
            var rows: [CoachIndexRow]
            switch request {
            case .latest:
                rows = Array(try coachIndexRows("sequence > 0", order: "DESC", limit: 20).reversed())
            case .before(let cursor):
                try validateCoachCursor(cursor, identity: context.identity)
                rows = Array(try coachIndexRows("sequence < ?", values: [.integer(Int(cursor.sequence))], order: "DESC", limit: 20).reversed())
            case .after(let cursor):
                try validateCoachCursor(cursor, identity: context.identity)
                rows = try coachIndexRows("sequence > ?", values: [.integer(Int(cursor.sequence))], limit: 20)
            case .aroundTurn(let id):
                let statement = try coachStatement("SELECT sequence FROM coach_index WHERE turnID = ?", [.text(id.uuidString)])
                defer { sqlite3_finalize(statement) }
                guard try coachStep(statement) else { throw CoachQueryError.missingTurn(id) }
                rows = try coachWindow(around: sqlite3_column_int64(statement, 0))
            case .atDay(let id):
                let statement = try coachStatement("SELECT sequence FROM coach_index WHERE trackingDayID = ? ORDER BY sequence LIMIT 1", [.text(id.uuidString)])
                defer { sqlite3_finalize(statement) }
                guard try coachStep(statement) else { throw CoachQueryError.noChatForDay(id) }
                rows = try coachWindow(around: sqlite3_column_int64(statement, 0))
            }
            let earlier = try rows.first.flatMap { try coachIndexRows("sequence < ?", values: [.integer(Int($0.sequence))], order: "DESC", limit: 1).first }
            let later = try rows.last.flatMap { try coachIndexRows("sequence > ?", values: [.integer(Int($0.sequence))], limit: 1).first }
            let exchanges = try rows.map { try coachExchange($0, context: context) }
            let atLatest: Bool
            if !rows.isEmpty { atLatest = later == nil }
            else {
                switch request {
                case .latest, .after: atLatest = true
                default: atLatest = false
                }
            }
            return CoachPage(identity: context.identity, exchanges: exchanges,
                before: rows.first.map { CoachCursor(identity: context.identity, sequence: $0.sequence, turnID: $0.id) },
                after: rows.last.map { CoachCursor(identity: context.identity, sequence: $0.sequence, turnID: $0.id) },
                hasEarlier: earlier != nil, hasLater: later != nil,
                earlierSegment: try earlier.map { try coachSegment(id: $0.segmentID) },
                laterSegment: try later.map { try coachSegment(id: $0.segmentID) },
                latestEmptySegment: atLatest ? try coachEmptySegment(expectedProfileID: expectedProfileID) : nil)
        }
    }

    private func coachEmptySegment(expectedProfileID: UUID) throws -> CoachEmptySegment? {
        let head = try readHead(expectedProfileID: expectedProfileID)
        guard let dayID = head.activeDayID, let segmentID = head.effectiveConversationSegmentID,
              try captureSegment(id: segmentID) == nil else { return nil }
        let day = try trackingDay(id: dayID)
        return CoachEmptySegment(segmentID: segmentID, trackingDayID: day.id, displayLocalDate: day.localDate, displayTimeZoneID: day.timeZoneID)
    }

    func coachDays(before: CoachDayCursor?, expectedProfileID: UUID) throws -> CoachDayPage {
        try coachRead {
            let context = try coachContext(expectedProfileID: expectedProfileID)
            return try coachSegmentPage(before: before, identity: context.identity, date: nil)
        }
    }

    func coachSegments(displayLocalDate: String, before: CoachDayCursor?, expectedIdentity: CoachTimelineIdentity) throws -> CoachDayPage {
        guard validLocalDate(displayLocalDate) else { throw CoachQueryError.invalidDateFilter }
        return try coachRead {
            let context = try coachContext(expectedProfileID: expectedIdentity.profileID)
            guard context.identity == expectedIdentity else { throw CoachQueryError.wrongTimeline }
            return try coachSegmentPage(before: before, identity: context.identity, date: displayLocalDate)
        }
    }

    private struct CoachReadContext {
        var identity: CoachTimelineIdentity
        var revision: Int
    }
    private struct CoachIndexRow {
        var id: UUID
        var sequence: Int64
        var capturedAt: Date
        var captureTimeZoneID: String
        var trackingDayID: UUID?
        var displayLocalDate: String
        var displayTimeZoneID: String
        var state: CoachTurnState
        var segmentID: UUID
    }

    private func coachRead<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN")
        do {
            let value = try body()
            try execute("COMMIT")
            return value
        } catch { try? execute("ROLLBACK"); throw error }
    }

    private func coachContext(expectedProfileID: UUID) throws -> CoachReadContext {
        let statement = try coachStatement("SELECT profileID, timelineGeneration, revision FROM storage_head WHERE id = 1")
        defer { sqlite3_finalize(statement) }
        guard try coachStep(statement) else { throw DiaryError.invalidData }
        let profileID = try coachUUID(statement, 0)
        guard profileID == expectedProfileID else { throw CoachQueryError.wrongTimeline }
        return CoachReadContext(identity: CoachTimelineIdentity(profileID: profileID, timelineGeneration: try coachUUID(statement, 1)),
            revision: Int(sqlite3_column_int64(statement, 2)))
    }

    private func validateCoachCursor(_ cursor: CoachCursor, identity: CoachTimelineIdentity) throws {
        guard cursor.identity == identity else { throw CoachQueryError.wrongTimeline }
        guard cursor.sequence > 0 else { throw CoachQueryError.invalidCursor }
        let statement = try coachStatement("SELECT 1 FROM coach_index WHERE turnID = ? AND sequence = ?", [.text(cursor.turnID.uuidString), .integer(Int(cursor.sequence))])
        defer { sqlite3_finalize(statement) }
        guard try coachStep(statement) else { throw CoachQueryError.invalidCursor }
    }

    private func coachWindow(around sequence: Int64) throws -> [CoachIndexRow] {
        let preceding = try coachIndexRows("sequence < ?", values: [.integer(Int(sequence))], order: "DESC", limit: 9)
        let first = preceding.last?.sequence ?? sequence
        let rows = try coachIndexRows("sequence >= ?", values: [.integer(Int(first))], limit: 20)
        guard rows.count < 20, let last = rows.last else { return rows }
        return Array(try coachIndexRows("sequence <= ?", values: [.integer(Int(last.sequence))], order: "DESC", limit: 20).reversed())
    }

    private func coachIndexRows(_ predicate: String, values: [Value] = [], order: String = "ASC", limit: Int) throws -> [CoachIndexRow] {
        let statement = try coachStatement("SELECT turnID, sequence, capturedAt, captureTimeZoneID, trackingDayID, displayLocalDate, displayTimeZoneID, state, segmentID FROM coach_index WHERE \(predicate) ORDER BY sequence \(order) LIMIT \(limit)", values)
        defer { sqlite3_finalize(statement) }
        var rows: [CoachIndexRow] = []
        while try coachStep(statement) {
            guard let state = CoachTurnState(rawValue: try coachText(statement, 7)) else { throw DiaryError.invalidData }
            rows.append(CoachIndexRow(id: try coachUUID(statement, 0), sequence: sqlite3_column_int64(statement, 1),
                capturedAt: Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 2)),
                captureTimeZoneID: try coachText(statement, 3), trackingDayID: try coachOptionalUUID(statement, 4),
                displayLocalDate: try coachText(statement, 5), displayTimeZoneID: try coachText(statement, 6), state: state,
                segmentID: try coachUUID(statement, 8)))
        }
        return rows
    }

    private func coachExchange(_ row: CoachIndexRow, context: CoachReadContext) throws -> CoachExchangeSummary {
        let statement = try coachStatement("SELECT payload FROM coach_turn WHERE id = ?", [.text(row.id.uuidString)])
        defer { sqlite3_finalize(statement) }
        guard try coachStep(statement) else { throw DiaryError.invalidData }
        let turn = try decode(CoachTurn.self, Record(id: row.id.uuidString, ordinal: 0, payload: try coachBlob(statement, 0)))
        try validateCoachTurnFields(turn)
        guard turn.photos.isEmpty, turn.capturedAt == row.capturedAt, turn.captureTimeZoneID == row.captureTimeZoneID,
              turn.activeDayID == row.trackingDayID, turn.state == row.state,
              turn.captureSegmentID == nil || turn.captureSegmentID == row.segmentID else { throw DiaryError.invalidData }
        let receipts = try turn.receipts.map { receipt in
            try validateCoachReceiptFields(receipt, turnID: turn.id, revision: context.revision)
            return Self.coachCommittedReceipt(receipt)
        }
        return CoachExchangeSummary(id: turn.id, sequence: row.sequence, capturedAt: row.capturedAt,
            captureTimeZoneID: row.captureTimeZoneID, segmentID: row.segmentID, trackingDayID: row.trackingDayID,
            displayLocalDate: row.displayLocalDate, displayTimeZoneID: row.displayTimeZoneID,
            text: turn.text, assistantText: turn.assistantText, state: row.state,
            photos: try coachPhotoReferences(turn: turn, profileID: context.identity.profileID), receipts: receipts)
    }

    private func coachPhotoReferences(turn: CoachTurn, profileID: UUID) throws -> [DiaryPhotoReference] {
        // Metadata payloads have empty Data; never select the originals' bytes column.
        let sql = "SELECT c.ownerKind, c.parentID, c.photoID, c.contentToken, p.payload FROM photo_consumer u JOIN photo_content c USING(ownerKind, parentID, photoID) JOIN coach_photo p ON c.coachPhysicalID = p.id WHERE u.turnID = ? UNION ALL SELECT c.ownerKind, c.parentID, c.photoID, c.contentToken, p.payload FROM photo_consumer u JOIN photo_content c USING(ownerKind, parentID, photoID) JOIN photo p ON c.mealPhysicalID = p.id WHERE u.turnID = ?"
        let statement = try coachStatement(sql, [.text(turn.id.uuidString), .text(turn.id.uuidString)])
        defer { sqlite3_finalize(statement) }
        let linkedMeals = Set(turn.receipts.compactMap(\.mealID) + (turn.pendingMealID.map { [$0] } ?? []))
        // Each of <=30 IDs has one direct owner or <=17 linked meals (16 receipts + pending): <=510 references.
        let maximumReferences = turn.photoIDs.count * max(1, linkedMeals.count)
        var references: [DiaryPhotoReference] = []
        while try coachStep(statement) {
            let kind = try coachText(statement, 0), parentID = try coachUUID(statement, 1), photoID = try coachUUID(statement, 2)
            let photo = try JSONDecoder().decode(MealPhoto.self, from: coachBlob(statement, 4))
            guard photo.id == photoID, photo.data.isEmpty, turn.photoIDs.contains(photoID), photo.createdAt.timeIntervalSinceReferenceDate.isFinite,
                  references.count < maximumReferences else { throw DiaryError.invalidData }
            let owner: DiaryPhotoOwner
            switch kind {
            case "coachTurn":
                guard parentID == turn.id else { throw DiaryError.invalidData }
                owner = .coachTurn(parentID)
            case "meal":
                guard linkedMeals.contains(parentID) else { throw DiaryError.invalidData }
                owner = .meal(parentID)
            default: throw DiaryError.invalidData
            }
            references.append(DiaryPhotoReference(profileID: profileID, owner: owner, photoID: photoID,
                createdAt: photo.createdAt, role: photo.role, contentToken: try coachUUID(statement, 3)))
        }
        let positions = Dictionary(uniqueKeysWithValues: turn.photoIDs.enumerated().map { ($0.element, $0.offset) })
        return references.sorted {
            let left = positions[$0.photoID]!, right = positions[$1.photoID]!
            return left == right ? coachPhotoOwnerKey($0.owner) < coachPhotoOwnerKey($1.owner) : left < right
        }
    }

    private func coachPhotoOwnerKey(_ owner: DiaryPhotoOwner) -> String {
        switch owner {
        case .meal(let id): "meal/" + id.uuidString
        case .coachTurn(let id): "coachTurn/" + id.uuidString
        }
    }

    private static let coachSegmentColumns = "segmentID, trackingDayID, displayLocalDate, displayTimeZoneID, firstTurnID, firstCapturedAt, firstSequence, lastSequence, preview"

    private func coachSegmentPage(before: CoachDayCursor?, identity: CoachTimelineIdentity, date: String?) throws -> CoachDayPage {
        if let before {
            guard before.identity == identity else { throw CoachQueryError.wrongTimeline }
            guard before.dateFilterScope == date, before.lastSequence > 0 else { throw CoachQueryError.invalidCursor }
            let segment = try coachSegment(id: before.segmentID)
            guard segment.lastSequence == before.lastSequence, date == nil || segment.displayLocalDate == date else { throw CoachQueryError.invalidCursor }
        }
        var clauses = ["lastSequence > 0"], values: [Value] = []
        if let date { clauses.append("displayLocalDate = ?"); values.append(.text(date)) }
        if let before {
            clauses.append("(lastSequence, segmentID) < (?, ?)")
            values += [.integer(Int(before.lastSequence)), .text(before.segmentID.uuidString)]
        }
        let statement = try coachStatement("SELECT \(Self.coachSegmentColumns) FROM coach_segment WHERE \(clauses.joined(separator: " AND ")) ORDER BY lastSequence DESC, segmentID DESC LIMIT 31", values)
        defer { sqlite3_finalize(statement) }
        var segments: [CoachSegmentSummary] = []
        while try coachStep(statement) { segments.append(try coachSegmentRow(statement)) }
        let hasMore = segments.count > 30
        if hasMore { segments.removeLast() }
        return CoachDayPage(identity: identity, segments: segments,
            cursor: segments.last.map { CoachDayCursor(identity: identity, lastSequence: $0.lastSequence, segmentID: $0.segmentID, dateFilterScope: date) }, hasMore: hasMore)
    }

    private func coachSegment(id: UUID) throws -> CoachSegmentSummary {
        let statement = try coachStatement("SELECT \(Self.coachSegmentColumns) FROM coach_segment WHERE segmentID = ?", [.text(id.uuidString)])
        defer { sqlite3_finalize(statement) }
        guard try coachStep(statement) else { throw CoachQueryError.invalidCursor }
        return try coachSegmentRow(statement)
    }

    private func coachSegmentRow(_ statement: OpaquePointer) throws -> CoachSegmentSummary {
        CoachSegmentSummary(segmentID: try coachUUID(statement, 0), trackingDayID: try coachOptionalUUID(statement, 1),
            displayLocalDate: try coachText(statement, 2), displayTimeZoneID: try coachText(statement, 3),
            firstExchangeID: try coachUUID(statement, 4), firstCapturedAt: Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 5)),
            firstSequence: sqlite3_column_int64(statement, 6), lastSequence: sqlite3_column_int64(statement, 7), preview: try coachText(statement, 8))
    }

    private struct ReceiptFacts: Decodable {
        var id: UUID?
        var mealID: UUID?
        var dayID: UUID?
        var localDate: String?
        var effectiveLocalDate: String?
        var targetLocalDate: String?
        var state: SubmissionState?
        var items: [FoodItem]?
        var item: FoodItem?
    }

    static func coachCommittedReceipt(_ receipt: CoachReceipt) -> CoachCommittedReceipt {
        var value = CoachCommittedReceipt(operationKey: receipt.operationKey, turnID: receipt.turnID, dayID: receipt.dayID,
            mealID: receipt.mealID, itemID: receipt.itemID, weightID: receipt.weightID, workoutID: receipt.workoutID,
            goalID: receipt.goalID, destination: receipt.destination, committedRevision: receipt.committedRevision)
        let foodPrefix = receipt.turnID.uuidString + "/food/"
        if receipt.operationKey.hasPrefix(foodPrefix) {
            let date = String(receipt.operationKey.dropFirst(foodPrefix.count))
            if validLocalDate(date) { value.targetLocalDate = date }
        }
        // Unrecognized legacy results remain replay authority without invented presentation facts.
        guard let facts = try? JSONDecoder().decode(ReceiptFacts.self, from: Data(receipt.resultJSON.utf8)) else { return value }
        if value.targetLocalDate == nil, let date = facts.targetLocalDate, validLocalDate(date) { value.targetLocalDate = date }
        if let id = receipt.dayID, facts.id == id, let date = facts.localDate, validLocalDate(date) { value.targetLocalDate = date }
        if let id = receipt.goalID, facts.id == id, let date = facts.effectiveLocalDate, validLocalDate(date) { value.targetLocalDate = date }
        var items: [FoodItem] = []
        if facts.state == .saved {
            if let id = receipt.mealID, facts.id == id, facts.dayID == receipt.dayID { items = facts.items ?? [] }
            if let id = receipt.mealID, facts.mealID == id, let item = facts.item, item.id == receipt.itemID { items = [item] }
        }
        do { try validateItems(items) } catch { return value }
        value.items = items.map { CoachCommittedItem(itemID: $0.id, name: $0.name, quantity: $0.quantity, unit: $0.unit) }
        return value
    }

    private func coachStatement(_ sql: String, _ values: [Value] = []) throws -> OpaquePointer {
        if let diagnostics {
            let plan = try prepare("EXPLAIN QUERY PLAN " + sql)
            defer { sqlite3_finalize(plan) }
            try bindCoachValues(values, to: plan)
            while try coachStep(plan) { diagnostics.recordQueryPlan(try coachText(plan, 3)) }
        }
        let statement = try prepare(sql)
        do { try bindCoachValues(values, to: statement); return statement }
        catch { sqlite3_finalize(statement); throw error }
    }

    private func bindCoachValues(_ values: [Value], to statement: OpaquePointer) throws {
        for (index, value) in values.enumerated() {
            let position = Int32(index + 1), transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            let status: Int32
            switch value {
            case .text(let text): status = sqlite3_bind_text(statement, position, text, Int32(text.utf8.count), transient)
            case .integer(let integer): status = sqlite3_bind_int64(statement, position, Int64(integer))
            default: throw DiaryError.invalidData
            }
            guard status == SQLITE_OK else { throw DiaryError.persistenceFailed }
        }
    }

    private func coachStep(_ statement: OpaquePointer) throws -> Bool {
        let status = sqlite3_step(statement)
        guard status == SQLITE_ROW || status == SQLITE_DONE else { throw DiaryError.persistenceFailed }
        return status == SQLITE_ROW
    }
    private func coachText(_ statement: OpaquePointer, _ column: Int32) throws -> String {
        guard let bytes = sqlite3_column_text(statement, column),
              let text = String(bytes: UnsafeBufferPointer(start: bytes, count: Int(sqlite3_column_bytes(statement, column))), encoding: .utf8) else { throw DiaryError.invalidData }
        return text
    }
    private func coachUUID(_ statement: OpaquePointer, _ column: Int32) throws -> UUID {
        guard let id = UUID(uuidString: try coachText(statement, column)) else { throw DiaryError.invalidData }
        return id
    }
    private func coachOptionalUUID(_ statement: OpaquePointer, _ column: Int32) throws -> UUID? {
        try sqlite3_column_type(statement, column) == SQLITE_NULL ? nil : coachUUID(statement, column)
    }
    private func coachBlob(_ statement: OpaquePointer, _ column: Int32) throws -> Data {
        guard let bytes = sqlite3_column_blob(statement, column) else { throw DiaryError.invalidData }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, column)))
    }
}

extension DiaryDatabase {
    func coachReceiptSummary(turnID: UUID, expectedProfileID: UUID) throws -> String {
        try domainRead(expectedProfileID: expectedProfileID) { head in
            let transaction = DiaryTransaction(database: self, head: head)
            guard let turn = try transaction.turn(id: turnID) else { throw DiaryError.notFound }
            var summaries: [String] = []
            func number(_ value: Double) -> String { value.formatted(.number.grouping(.never).locale(Locale(identifier: "en_US"))) }
            for receipt in turn.receipts {
                let facts = Self.coachCommittedReceipt(receipt)
                if let id = receipt.mealID {
                    let meal: MealReadModel
                    do { meal = try transaction.mealProjection(id: id) }
                    catch DiaryError.notFound { summaries.append("This meal was deleted. Its prior receipt is retained."); continue }
                    if let itemID = receipt.itemID, !meal.items.contains(where: { $0.id == itemID }) {
                        summaries.append("This item was deleted. Its prior receipt is retained."); continue
                    }
                    if !facts.items.isEmpty {
                        let items = facts.items.map { "\($0.name) (\(number($0.quantity)) \($0.unit))" }.joined(separator: ", ")
                        let date = facts.targetLocalDate.map { " on " + $0 } ?? ""
                        summaries.append("\(receipt.itemID == nil ? "Logged" : "Updated") \(items)\(date). Nutrition may be uncertain.")
                    } else if meal.state == .awaitingReview { summaries.append("Estimate ready for review.") }
                    else if receipt.operationKey.contains("/retry_meal/") { summaries.append("Queued the original saved meal input for analysis.") }
                    else { summaries.append("The requested meal change was recorded.") }
                } else if let id = receipt.weightID {
                    do {
                        let weight = try transaction.weight(id: id)
                        summaries.append("Recorded weight: \(number(weight.value)) \(weight.unit).")
                    } catch DiaryError.notFound { summaries.append("This weight was deleted.") }
                } else if let id = receipt.workoutID {
                    do {
                        let workout = try transaction.workout(id: id)
                        summaries.append("Recorded \(workout.kind.rawValue): \(workout.durationMinutes) minutes.")
                    } catch DiaryError.notFound { summaries.append("This workout was deleted.") }
                } else if let id = receipt.goalID {
                    guard try transaction.records("goal", clause: "id = ?", values: [.text(id.uuidString)], limit: 1).first != nil else { throw DiaryError.notFound }
                    summaries.append("Saved your requested goals.")
                } else if receipt.destination != nil { summaries.append("Use the Settings link to continue.") }
                else if receipt.operationKey.contains("/update_preferences") { summaries.append("Saved your diary preferences. Timezone: \(head.profile.timeZoneID).") }
                else if let id = receipt.dayID {
                    let day = try trackingDay(id: id)
                    summaries.append("\(day.localDate): \(day.completeness.rawValue).")
                }
            }
            return summaries.joined(separator: "\n")
        }
    }
}
