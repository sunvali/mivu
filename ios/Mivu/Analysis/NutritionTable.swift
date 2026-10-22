import Foundation
import SQLite3

/// Read-only USDA FNDDS 2021–2023 table bundled for on-device estimates; built by scripts/nutrition/build_fndds.py.
struct NutritionTable: Sendable {
    struct Food: Equatable, Sendable {
        let code: Int
        let description: String
        let per100Grams: NutritionValues
    }

    static let bundled = NutritionTable(url: Bundle.main.url(forResource: "fndds", withExtension: "sqlite"))
    let url: URL?

    /// Lowercased words of three or more letters with a plural "s" dropped, so "eggs" names "Boiled egg" and "glass" stays whole.
    static func words(_ text: String) -> Set<String> {
        Set(text.lowercased().split { !$0.isLetter }.filter { $0.count >= 3 }
            .map { $0.hasSuffix("s") && !$0.hasSuffix("ss") ? String($0.dropLast()) : String($0) })
    }

    /// Full-text matches, re-ranked so plain foods ("Apple, raw") beat dishes that mention them ("Pie, apple").
    func search(_ phrase: String, limit: Int = 5) throws -> [Food] {
        let terms = Self.words(phrase).sorted()
        guard !terms.isEmpty else { return [] }
        let query = terms.map { "\"\($0)\"" }.joined(separator: " OR ")
        let foods = try rows("""
            select f.code, f.description, f.kcal, f.carbs, f.protein, f.fat from foods_fts join foods f on f.code = foods_fts.rowid
            where foods_fts match ? order by rank limit 50
            """, query) { statement in
            Food(code: Int(sqlite3_column_int64(statement, 0)), description: String(cString: sqlite3_column_text(statement, 1)),
                 per100Grams: NutritionValues(kcal: sqlite3_column_double(statement, 2), carbs: sqlite3_column_double(statement, 3),
                                              protein: sqlite3_column_double(statement, 4), fat: sqlite3_column_double(statement, 5)))
        }
        let lead = Self.words(phrase.split(separator: " ").first.map(String.init) ?? "")
        func score(_ food: Food) -> (Int, Int, Int) {
            let words = Self.words(food.description)
            let firstWord = Self.words(food.description.split(separator: ",").first.map(String.init) ?? "")
            return (words.intersection(terms).count, firstWord.isDisjoint(with: Set(terms).union(lead)) ? 0 : 1, -food.description.count)
        }
        return Array(foods.enumerated().sorted { score($0.element) != score($1.element) ? score($0.element) > score($1.element) : $0.offset < $1.offset }
            .map(\.element).prefix(limit))
    }

    /// Grams for one of `unit`: a matching portion (general "NFS" first), else the "Quantity not specified" serving.
    func portionGrams(code: Int, unit: String) throws -> Double? {
        let portions = try rows("select description, grams from portions where code = ?", code) { statement in
            (description: String(cString: sqlite3_column_text(statement, 0)), grams: sqlite3_column_double(statement, 1))
        }
        let synonyms: [String: [String]] = ["slice": ["slice", "piece"], "glass": ["glass", "cup"],
                                            "bowl": ["bowl", "cup"], "mug": ["mug", "cup"], "bar": ["bar", "piece"]]
        let unitWords = Self.words(unit)
        let wanted = Set(unitWords.flatMap { synonyms[$0] ?? [$0] })
        let matches = portions.filter { !Self.words($0.description).isDisjoint(with: wanted) }
        if let match = matches.first(where: { $0.description.contains("NFS") }) ?? matches.min(by: { $0.description.count < $1.description.count }) {
            return match.grams
        }
        return portions.first { $0.description == "Quantity not specified" }?.grams
    }

    private func rows<T>(_ sql: String, _ value: Any, _ read: (OpaquePointer) -> T) throws -> [T] {
        var connection: OpaquePointer?
        guard let url, sqlite3_open_v2(url.path, &connection, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let connection else {
            sqlite3_close(connection); throw DiaryError.persistenceFailed
        }
        defer { sqlite3_close(connection) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw DiaryError.persistenceFailed }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let bound = if let text = value as? String { sqlite3_bind_text(statement, 1, text, -1, transient) }
            else { sqlite3_bind_int64(statement, 1, Int64(value as? Int ?? 0)) }
        guard bound == SQLITE_OK else { throw DiaryError.persistenceFailed }
        var result: [T] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return result }
            guard status == SQLITE_ROW else { throw DiaryError.persistenceFailed }
            result.append(read(statement))
        }
    }
}
