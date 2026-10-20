import Foundation
import SQLite3

struct DiaryRecordPage<Value: Sendable>: Sendable {
    var values: [Value]
    var cursor: Int?
    var hasMore: Bool
}

struct CoachWorkStatus: Equatable, Sendable {
    var pendingTurnID: UUID?
    var latestState: CoachTurnState?
}

extension DiaryDatabase {
    func profileMetadata(expectedProfileID: UUID) throws -> DiaryProfile {
        if try mutationInteger("PRAGMA user_version") == 1 { return try readHead(expectedProfileID: expectedProfileID).profile }
        let query = try domainStatement("SELECT json_extract(CAST(payload AS TEXT), '$.profile') FROM meta WHERE id = ?", [.text(expectedProfileID.uuidString)])
        defer { sqlite3_finalize(query) }
        guard try mutationStep(query) else { throw DiaryError.notFound }
        let profile = try JSONDecoder().decode(DiaryProfile.self, from: Data(mutationText(query, 0).utf8))
        guard profile.id == expectedProfileID else { throw DiaryError.wrongOwner }
        return profile
    }
    func coachWorkStatus(expectedProfileID: UUID) throws -> CoachWorkStatus {
        try domainRead(expectedProfileID: expectedProfileID) { _ in
            let pending = try domainStatement("SELECT turnID FROM coach_index WHERE state IN ('captured','analyzing','waitingForNetwork') ORDER BY sequence LIMIT 1")
            defer { sqlite3_finalize(pending) }
            let id = try mutationStep(pending) ? mutationOptionalUUID(pending, 0) : nil
            let latest = try domainStatement("SELECT state FROM coach_index ORDER BY sequence DESC LIMIT 1")
            defer { sqlite3_finalize(latest) }
            return CoachWorkStatus(pendingTurnID: id, latestState: try mutationStep(latest) ? CoachTurnState(rawValue: mutationText(latest, 0)) : nil)
        }
    }
    func coachTurnForMeal(_ mealID: UUID, expectedProfileID: UUID) throws -> UUID? {
        try domainRead(expectedProfileID: expectedProfileID) { _ in
            let query = try domainStatement("SELECT i.turnID FROM coach_index i JOIN submission s ON s.id = i.turnID AND s.parent = i.pendingMealID WHERE i.pendingMealID = ? ORDER BY i.sequence DESC LIMIT 1", [.text(mealID.uuidString)])
            defer { sqlite3_finalize(query) }
            guard try mutationStep(query) else { return nil }; return try mutationOptionalUUID(query, 0)
        }
    }
    /// Recorded days whose local date falls in an inclusive span of at most seven dates.
    func diaryWeek(from start: String, through end: String, expectedProfileID: UUID) throws -> DiaryWeekPage {
        guard let first = ProgressDate.date(start, zone: "UTC"), let last = ProgressDate.date(end, zone: "UTC"),
              (0...6).contains(Int((last.timeIntervalSince(first) / 86_400).rounded()))
        else { throw DiaryError.invalidData }
        return try domainRead(expectedProfileID: expectedProfileID) { head in
            let date = "json_extract(CAST(payload AS TEXT), '$.localDate')"
            let statement = try domainStatement("SELECT id, payload FROM day WHERE \(date) BETWEEN ? AND ? ORDER BY \(date), id", [.text(start), .text(end)])
            defer { sqlite3_finalize(statement) }
            let transaction = DiaryTransaction(database: self, head: head)
            var days: [DiaryDaySummary] = []
            while try mutationStep(statement) {
                let id = try mutationText(statement, 0)
                let day = try decode(TrackingDay.self, Record(id: id, ordinal: 0, payload: mutationBlob(statement, 1)))
                try validateTrackingDayFields(day)
                days.append(try transaction.daySummary(day))
            }
            let earliest = try domainStatement("SELECT MIN(\(date)) FROM day")
            defer { sqlite3_finalize(earliest) }
            return DiaryWeekPage(days: days, earliestLocalDate: try mutationStep(earliest) ? try? mutationText(earliest, 0) : nil)
        }
    }
    func historyCoverage(expectedProfileID: UUID) throws -> [DayCompleteness: Int] {
        try domainRead(expectedProfileID: expectedProfileID) { _ in
            let query = try domainStatement("SELECT json_extract(CAST(payload AS TEXT), '$.completeness'), COUNT(*) FROM day GROUP BY 1")
            defer { sqlite3_finalize(query) }; var result: [DayCompleteness: Int] = [:]
            while try mutationStep(query) { if let status = DayCompleteness(rawValue: try mutationText(query, 0)) { result[status] = Int(sqlite3_column_int64(query, 1)) } }
            return result
        }
    }
    func screenRecords<Value: Decodable & Identifiable & Sendable>(_ type: Value.Type, table: String, before: Int? = nil, expectedProfileID: UUID) throws -> DiaryRecordPage<Value> where Value.ID == UUID {
        guard ["goal", "weight", "workout"].contains(table) else { throw DiaryError.invalidData }
        return try domainRead(expectedProfileID: expectedProfileID) { _ in
            let key = table == "goal" ? "effectiveLocalDate" : "json_extract(CAST(payload AS TEXT), '$.\(table == "weight" ? "measuredAt" : "performedAt")')"
            var values: [DiaryDatabase.Value] = [], clause = ""
            if let before {
                let cursor = try domainStatement("SELECT id, \(key) FROM \(table) WHERE ordinal = ? LIMIT 1", [.integer(before)])
                defer { sqlite3_finalize(cursor) }
                guard try mutationStep(cursor) else { throw DiaryError.notFound }
                let position: DiaryDatabase.Value = try table == "goal" ? .text(mutationText(cursor, 1)) : .real(sqlite3_column_double(cursor, 1))
                values = [position, .integer(before), .text(try mutationText(cursor, 0))]
                clause = "WHERE (\(key), ordinal, id) < (?, ?, ?)"
            }
            let query = try domainStatement("SELECT id, ordinal, payload FROM \(table) \(clause) ORDER BY \(key) DESC, ordinal DESC, id DESC LIMIT 31", values)
            defer { sqlite3_finalize(query) }; var rows: [Record] = []
            while try mutationStep(query) { rows.append(Record(id: try mutationText(query, 0), ordinal: Int(sqlite3_column_int64(query, 1)), payload: try mutationBlob(query, 2))) }
            let records = try rows.prefix(30).map { try decode(type, $0) }
            return DiaryRecordPage(values: records, cursor: rows.count > 30 ? rows[29].ordinal : nil, hasMore: rows.count > 30)
        }
    }
}
