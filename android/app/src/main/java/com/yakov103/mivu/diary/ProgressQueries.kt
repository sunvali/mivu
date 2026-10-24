package com.yakov103.mivu.diary

import com.yakov103.mivu.coach.CoachError
import com.yakov103.mivu.coach.CoachProgress
import com.yakov103.mivu.coach.coachProgress
import com.yakov103.mivu.coach.count
import java.util.UUID
import kotlinx.serialization.KSerializer

// Ports of the Progress screen reads: hasDays, topFoods and progressRange (DiaryDatabaseProgressQueries.swift:12,20,35) and
// screenRecords (DiaryDatabaseScreenQueries.swift:65) behind weightHistory/workoutHistory/goalHistory (DiaryStore.swift:715).

data class TopFood(val name: String, val kcal: Double, val count: Int)

/** One page of records, newest first; [cursor] is the last row's ordinal, passed as `before` for the next page. */
data class RecordPage<T>(val values: List<T>, val cursor: Long?, val hasMore: Boolean)

/** The Coach's `get_progress` for 1, 7 or 30 days; [includeDailyReports] also allows 91 and 365 and fills the display fields. */
fun DiaryDatabase.progressRange(endingOn: String, days: Int, includeDailyReports: Boolean = false): CoachProgress =
    read { it.coachProgress(endingOn, days, includeDailyReports) }

/** Whether any tracking day is older than [before], so paging back can skip empty weeks. */
fun DiaryDatabase.hasDays(before: String): Boolean {
    if (!validLocalDate(before)) throw CoachError.InvalidArguments
    return read { it.count("SELECT EXISTS(SELECT 1 FROM day WHERE json_extract(CAST(payload AS TEXT), '$.localDate') < ?)", listOf(before)) != 0 }
}

/** Saved foods with known energy, grouped by case- and space-insensitive name; the newest spelling names the group. */
fun DiaryDatabase.topFoods(from: String, through: String, limit: Int): List<TopFood> {
    if (!validLocalDate(from) || !validLocalDate(through) || limit <= 0) throw CoachError.InvalidArguments
    val name = "trim(json_extract(CAST(i.payload AS TEXT), '$.name'))"
    val kcal = "json_extract(CAST(i.payload AS TEXT), '$.nutrition.kcal')"
    // SQLite takes the bare `name` column from the row that holds MAX(eatenAt).
    return read { tx ->
        tx.query("SELECT $name, SUM($kcal), COUNT(*), MAX(json_extract(CAST(m.payload AS TEXT), '$.eatenAt')) FROM item i " +
            "JOIN meal m ON m.id = i.parent JOIN day d ON d.id = m.parent WHERE json_extract(CAST(m.payload AS TEXT), '$.revision') > 0 " +
            "AND json_extract(CAST(d.payload AS TEXT), '$.localDate') BETWEEN ? AND ? AND $kcal IS NOT NULL " +
            "GROUP BY lower($name) ORDER BY 2 DESC, 1 LIMIT $limit", listOf(from, through)) { c ->
            buildList { while (c.moveToNext()) add(TopFood(c.getString(0), c.getDouble(1), c.getInt(2))) }
        }
    }
}

fun DiaryDatabase.weightHistory(before: Long? = null): RecordPage<WeightEntry> =
    read { it.screenRecords("weight", "json_extract(CAST(payload AS TEXT), '$.measuredAt')", before, WeightEntry.serializer()) { w -> w.id } }

fun DiaryDatabase.workoutHistory(before: Long? = null): RecordPage<WorkoutSession> =
    read { it.screenRecords("workout", "json_extract(CAST(payload AS TEXT), '$.performedAt')", before, WorkoutSession.serializer()) { w -> w.id } }

fun DiaryDatabase.goalHistory(before: Long? = null): RecordPage<GoalRecord> =
    read { it.screenRecords("goal", "json_extract(CAST(payload AS TEXT), '$.effectiveLocalDate')", before, GoalRecord.serializer()) { g -> g.id } }

/** 30 rows a page by [key], then ordinal, then id, all descending; [before] is the ordinal the previous page ended on. */
private fun <T> DiaryDatabase.Tx.screenRecords(table: String, key: String, before: Long?, serializer: KSerializer<T>, id: (T) -> UUID): RecordPage<T> {
    var clause = ""
    val args = mutableListOf<String>()
    if (before != null) {
        if (count("SELECT COUNT(*) FROM $table WHERE ordinal = ?", listOf(before.toString())) == 0) throw DiaryError.NotFound
        clause = "WHERE ($key, ordinal, id) < (SELECT $key, ordinal, id FROM $table WHERE ordinal = ? LIMIT 1)"
        args += before.toString()
    }
    val rows = query("SELECT id, ordinal, payload FROM $table $clause ORDER BY $key DESC, ordinal DESC, id DESC LIMIT 31", args) { c ->
        buildList { while (c.moveToNext()) add(Triple(c.getString(0), c.getLong(1), c.getBlob(2))) }
    }
    val values = rows.take(30).map { (rowID, _, payload) ->
        SwiftJson.decodeFromString(serializer, payload.decodeToString()).also { if (id(it).swift != rowID) throw DiaryError.InvalidData(table) }
    }
    return RecordPage(values, if (rows.size > 30) rows[29].second else null, rows.size > 30)
}
