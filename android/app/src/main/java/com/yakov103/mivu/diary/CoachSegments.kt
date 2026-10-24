package com.yakov103.mivu.diary

import android.database.Cursor
import java.time.Instant
import java.util.UUID

// Port of the iOS coach_segment index: assignment from appendCapture/appendCaptureIndex (DiaryDatabaseMutations.swift:259-316)
// and the migration rebuild (DiaryDatabaseMigration.swift:277-306); reads from coachSegmentPage and coachWindow
// (DiaryDatabaseQueries.swift:165, 252). The table is derived from coach_turn and never archived.

/** One conversation: consecutive turns on the same tracking day, display date and zone. */
data class CoachSegmentSummary(
    val segmentID: UUID,
    val trackingDayID: UUID?,
    val displayLocalDate: String,
    val displayTimeZoneID: String,
    val firstTurnID: UUID,
    val firstCapturedAt: Instant,
    val firstOrdinal: Long,
    val lastOrdinal: Long,
    val preview: String,
)

/** Continues a history read after its last segment; [dateFilter] is the date the page was read for, if any. */
data class CoachDayCursor(val lastOrdinal: Long, val segmentID: UUID, val dateFilter: String?)

data class CoachDayPage(val segments: List<CoachSegmentSummary>, val cursor: CoachDayCursor?, val hasMore: Boolean)

private const val PAGE = 30
private const val COLUMNS = "segmentID, trackingDayID, displayLocalDate, displayTimeZoneID, firstTurnID, firstCapturedAt, firstOrdinal, lastOrdinal, preview"

/** Every conversation, newest first, 30 at a time. */
fun DiaryDatabase.coachDays(before: CoachDayCursor? = null): CoachDayPage = read { it.segmentPage(before, null) }

/** The conversations shown under [displayLocalDate]; separate visits on one date stay separate. */
fun DiaryDatabase.coachSegments(displayLocalDate: String, before: CoachDayCursor? = null): CoachDayPage {
    if (!validLocalDate(displayLocalDate)) throw DiaryError.InvalidData("date filter")
    return read { it.segmentPage(before, displayLocalDate) }
}

/**
 * The turn whose capture an "Ask Pip" about [mealID] should open at: the earliest turn naming the meal.
 * shortcut: scans coach_turn in ordinal order (at most 10,000 rows, stopping at the first match) with the same query as the
 * meal candidate's description fallback; upgrade with a record_source port that indexes turns by meal.
 */
fun DiaryDatabase.coachSourceTurn(mealID: UUID): UUID? = read { tx ->
    tx.query("SELECT t.id FROM coach_turn t WHERE $COACH_TURN_NAMES_MEAL ORDER BY t.ordinal LIMIT 1", listOf(mealID.swift)) {
        if (it.moveToFirst()) uuid(it, 0) else null
    }
}

/** Turns of `coach_turn t` that name meal `?1` as their pending meal or in a receipt. */
internal const val COACH_TURN_NAMES_MEAL = "json_extract(CAST(t.payload AS TEXT), '$.pendingMealID') = ?1 OR EXISTS (SELECT 1 FROM " +
    "json_each(CAST(t.payload AS TEXT), '$.receipts') r WHERE json_extract(r.value, '$.mealID') = ?1)"

/** iOS `coachWindow`: the turn at [ordinal] with up to nine turns before it, 20 in all when the history has them. */
internal fun DiaryDatabase.Tx.coachWindowStart(request: CoachPageRequest): Long {
    val ordinal = when (request) {
        is CoachPageRequest.AroundTurn -> query("SELECT ordinal FROM coach_turn WHERE id = ?", listOf(request.turnID.swift)) {
            if (it.moveToFirst()) it.getLong(0) else null
        }
        is CoachPageRequest.AtDay -> query("SELECT firstOrdinal FROM coach_segment WHERE trackingDayID = ? ORDER BY firstOrdinal LIMIT 1",
            listOf(request.dayID.swift)) { if (it.moveToFirst()) it.getLong(0) else null }
        else -> error("not a seek")
    } ?: throw DiaryError.NotFound
    fun ordinals(sql: String, arg: Long) = query(sql, listOf(arg.toString())) { c -> buildList { while (c.moveToNext()) add(c.getLong(0)) } }
    val first = ordinals("SELECT ordinal FROM coach_turn WHERE ordinal < ? ORDER BY ordinal DESC LIMIT 9", ordinal).lastOrNull() ?: ordinal
    val rows = ordinals("SELECT ordinal FROM coach_turn WHERE ordinal >= ? ORDER BY ordinal LIMIT 20", first)
    if (rows.size == 20) return first
    // Near the newest turn: the 20 that end at the latest.
    return ordinals("SELECT ordinal FROM coach_turn WHERE ordinal <= ? ORDER BY ordinal DESC LIMIT 20", rows.last()).last()
}

/**
 * Adds a new turn to the index (iOS `appendCaptureIndex`). The display date and zone are its active day's, else its capture
 * date and zone. A captured segment ID is extended or started; without one the turn joins the newest segment when the day,
 * date and zone match, else starts one whose ID is derived from the turn so a rebuild gives the same row.
 */
internal fun DiaryDatabase.Tx.indexCoachSegment(turn: CoachTurn) {
    val newest = segments("1 ORDER BY lastOrdinal DESC, segmentID DESC LIMIT 1", emptyList()).firstOrNull()
    putSegment(segmentFor(turn, turnOrdinal(turn.id), turn.activeDayID?.let(::day), newest) { id ->
        segments("segmentID = ? LIMIT 1", listOf(id.swift)).firstOrNull()
    })
}

/** Rebuilds the index from every turn in ordinal order, after a replace or when it lags coach_turn. */
internal fun DiaryDatabase.Tx.rebuildCoachSegments() {
    exec("DELETE FROM coach_segment", emptyList())
    // One pass in memory, then one insert per segment: 10,000 turns cost one decode each.
    val days = mutableMapOf<UUID, TrackingDay?>()
    val built = LinkedHashMap<UUID, CoachSegmentSummary>()
    var newest: CoachSegmentSummary? = null
    query("SELECT ordinal, payload FROM coach_turn ORDER BY ordinal LIMIT 10000", emptyList()) { c ->
        while (c.moveToNext()) {
            val turn = try { SwiftJson.decodeFromString(CoachTurn.serializer(), c.getBlob(1).decodeToString()) }
            catch (_: IllegalArgumentException) { throw DiaryError.InvalidData("coach turn") }
            val segment = segmentFor(turn, c.getLong(0), turn.activeDayID?.let { id -> days.getOrPut(id) { day(id) } }, newest, built::get)
            built[segment.segmentID] = segment
            newest = segment
        }
    }
    built.values.forEach { putSegment(it) }
}

/** The segment [turn] at [ordinal] belongs to, as it is once the turn is added, given its active [day] and the [newest] segment. */
private fun segmentFor(
    turn: CoachTurn, ordinal: Long, day: TrackingDay?, newest: CoachSegmentSummary?, existing: (UUID) -> CoachSegmentSummary?,
): CoachSegmentSummary {
    val date = day?.localDate ?: diaryDateLabel(turn.capturedAt, turn.captureTimeZoneID)
    val zone = day?.timeZoneID ?: turn.captureTimeZoneID
    val id = turn.captureSegmentID
        ?: newest?.takeIf { it.trackingDayID == day?.id && it.displayLocalDate == date && it.displayTimeZoneID == zone }?.segmentID
        ?: UUID.nameUUIDFromBytes("mivu.coach.segment:${turn.id}".toByteArray())
    val found = if (id == newest?.segmentID) newest else existing(id)
    return found?.copy(lastOrdinal = ordinal)
        ?: CoachSegmentSummary(id, day?.id, date, zone, turn.id, turn.capturedAt, ordinal, ordinal, turn.text.take(160))
}

private fun DiaryDatabase.Tx.putSegment(s: CoachSegmentSummary) = exec("INSERT OR REPLACE INTO coach_segment ($COLUMNS) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
    listOf(s.segmentID.swift, s.trackingDayID?.swift, s.displayLocalDate, s.displayTimeZoneID, s.firstTurnID.swift, s.firstCapturedAt.toString(),
        s.firstOrdinal, s.lastOrdinal, s.preview))

internal fun DiaryDatabase.Tx.coachSegmentExists(id: UUID) = segments("segmentID = ? LIMIT 1", listOf(id.swift)).isNotEmpty()

private fun DiaryDatabase.Tx.turnOrdinal(id: UUID): Long =
    query("SELECT ordinal FROM coach_turn WHERE id = ?", listOf(id.swift)) { if (it.moveToFirst()) it.getLong(0) else throw DiaryError.NotFound }

private fun DiaryDatabase.Tx.segmentPage(before: CoachDayCursor?, date: String?): CoachDayPage {
    if (before != null) {
        val segment = segments("segmentID = ? LIMIT 1", listOf(before.segmentID.swift)).firstOrNull()
        if (before.dateFilter != date || segment?.lastOrdinal != before.lastOrdinal || (date != null && segment.displayLocalDate != date)) {
            throw DiaryError.InvalidData("cursor")
        }
    }
    val clauses = listOfNotNull(date?.let { "displayLocalDate = ?" }, before?.let { "(lastOrdinal, segmentID) < (${it.lastOrdinal}, ?)" })
    val args = listOfNotNull(date, before?.segmentID?.swift)
    val found = segments("${clauses.joinToString(" AND ").ifEmpty { "1" }} ORDER BY lastOrdinal DESC, segmentID DESC LIMIT ${PAGE + 1}", args)
    val page = found.take(PAGE)
    return CoachDayPage(page, page.lastOrNull()?.let { CoachDayCursor(it.lastOrdinal, it.segmentID, date) }, found.size > PAGE)
}

private fun DiaryDatabase.Tx.segments(where: String, args: List<String>): List<CoachSegmentSummary> =
    query("SELECT $COLUMNS FROM coach_segment WHERE $where", args) { c ->
        buildList {
            while (c.moveToNext()) add(CoachSegmentSummary(uuid(c, 0), if (c.isNull(1)) null else uuid(c, 1), c.getString(2), c.getString(3),
                uuid(c, 4), Instant.parse(c.getString(5)), c.getLong(6), c.getLong(7), c.getString(8)))
        }
    }

private fun uuid(c: Cursor, column: Int) = swiftUUID(c.getString(column)) ?: throw DiaryError.InvalidData("coach segment")
