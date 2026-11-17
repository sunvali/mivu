import Foundation
import SQLite3

extension DiaryDatabase {
    /// Saved meals on the inclusive local-date range, newest eaten first, at most 60. Coach's quick prompts
    /// pick a meal to log again from these, so the read stays bounded instead of loading whole days.
    func recentMeals(from: String, to: String, expectedProfileID: UUID) throws -> [RecentMeal] {
        guard validLocalDate(from), validLocalDate(to) else { throw DiaryError.invalidData }
        return try domainRead(expectedProfileID: expectedProfileID) { head in
            let transaction = DiaryTransaction(database: self, head: head)
            let statement = try domainStatement("""
                SELECT m.id, json_extract(CAST(d.payload AS TEXT), '$.localDate') FROM meal m JOIN day d ON m.parent = d.id
                WHERE json_extract(CAST(d.payload AS TEXT), '$.localDate') >= ? AND json_extract(CAST(d.payload AS TEXT), '$.localDate') <= ?
                AND json_extract(CAST(m.payload AS TEXT), '$.revision') > 0
                ORDER BY json_extract(CAST(m.payload AS TEXT), '$.eatenAt') DESC, m.ordinal DESC, m.id LIMIT 60
                """, [.text(from), .text(to)])
            defer { sqlite3_finalize(statement) }
            var rows: [(UUID, String)] = []
            while try mutationStep(statement) {
                guard let id = try mutationOptionalUUID(statement, 0) else { throw DiaryError.invalidData }
                rows.append((id, try mutationText(statement, 1)))
            }
            return try rows.map { RecentMeal(localDate: $0.1, meal: try transaction.mealProjection(id: $0.0)) }
        }
    }
}
