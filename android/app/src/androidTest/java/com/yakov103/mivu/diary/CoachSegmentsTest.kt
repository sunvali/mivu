package com.yakov103.mivu.diary

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import androidx.test.core.app.ApplicationProvider
import com.yakov103.mivu.coach.CoachManualEdit
import com.yakov103.mivu.coach.CoachWrite
import java.io.File
import java.time.Duration
import java.time.Instant
import java.util.UUID
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test

/** Synthetic diaries only: the derived coach_segment index behind Coach history and seek (iOS coachSegmentPage/coachWindow). */
class CoachSegmentsTest {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val profile = DiaryProfile(UUID.randomUUID(), "Synthetic", "en", "UTC", "")
    private lateinit var db: DiaryDatabase
    private val at = Instant.parse("2026-10-24T12:00:00Z")

    @Before fun open() {
        File(context.filesDir, "profiles").deleteRecursively()
        db = DiaryDatabase.create(context, profile)
    }

    @After fun close() {
        db.close()
        File(context.filesDir, "profiles").deleteRecursively()
    }

    private inline fun <reified E : Throwable> throws(block: () -> Unit): E {
        try { block() } catch (e: Throwable) { if (e is E) return e; throw e }
        fail("expected ${E::class.simpleName}"); error("unreachable")
    }

    private fun capture(text: String = "Synthetic lunch", time: Instant = at, zone: String = "UTC"): CoachTurn {
        if (db.head().profile.timeZoneID != zone) db.transaction(null) { it.head = it.head.copy(profile = it.head.profile.copy(timeZoneID = zone)) }
        val h = db.head()
        return db.captureCoachSubmission(CoachSubmissionPayload(UUID.randomUUID(), text, emptyList(),
            CoachCaptureContext(time, zone, h.activeDayID, h.previousDayConfirmedAt, h.activeConversationSegmentID)), h.revision)
    }

    private fun day(n: Long) = at.plus(Duration.ofDays(n))

    private fun stored(text: String, time: Instant, dayID: UUID? = null, segmentID: UUID? = null) = CoachTurn(UUID.randomUUID(), time, text,
        emptyList(), CoachTurnState.completed, "Synthetic reply", emptyList(), "UTC", dayID, emptyList(), captureSegmentID = segmentID)

    private fun seed(turns: List<CoachTurn>): List<CoachTurn> {
        db.replaceAll(db.snapshot().copy(revision = 5, coachTurns = turns))
        db.snapshotReads = 0
        return turns
    }

    @Test fun turnsInOneActiveSegmentShareOneRow() {
        db.startDay(at, db.head().revision)
        val first = capture("Synthetic breakfast")
        capture("Synthetic lunch", at.plusSeconds(60))
        val segment = db.coachDays().segments.single()
        assertEquals(db.head().activeConversationSegmentID, segment.segmentID)
        assertEquals(db.head().activeDayID, segment.trackingDayID)
        assertEquals("2026-10-24", segment.displayLocalDate)
        assertEquals(first.id, segment.firstTurnID)
        assertEquals(first.capturedAt, segment.firstCapturedAt)
        assertEquals(segment.firstOrdinal + 1, segment.lastOrdinal)
        assertEquals("Synthetic breakfast", segment.preview)
    }

    @Test fun dateOrZoneChangeStartsNewSegment() {
        val a = capture()
        capture(time = at.plusSeconds(60))
        val b = capture(time = day(1))
        val c = capture(time = day(1).plusSeconds(60), zone = "Asia/Jerusalem")
        val segments = db.coachDays().segments
        assertEquals(listOf(c.id, b.id, a.id), segments.map { it.firstTurnID })
        assertEquals(listOf("Asia/Jerusalem", "UTC", "UTC"), segments.map { it.displayTimeZoneID })
        assertEquals(1, segments.last().lastOrdinal - segments.last().firstOrdinal)
        assertTrue(segments.all { it.trackingDayID == null })
    }

    @Test fun daysPageIs30NewestFirstWithCursor() {
        val turns = (0L until 31).map { capture("Synthetic $it", day(it)) }
        val first = db.coachDays()
        assertEquals(turns.takeLast(30).reversed().map { it.id }, first.segments.map { it.firstTurnID })
        assertTrue(first.hasMore)
        val second = db.coachDays(first.cursor)
        assertEquals(listOf(turns.first().id), second.segments.map { it.firstTurnID })
        assertFalse(second.hasMore)
    }

    @Test fun dateFilterKeepsSeparateVisits() {
        val a = capture(time = day(-1))
        capture(time = at)
        val c = capture(time = day(-1).plusSeconds(60))
        val page = db.coachSegments("2026-10-23")
        assertEquals(listOf(c.id, a.id), page.segments.map { it.firstTurnID })
        assertFalse(page.hasMore)
        assertTrue(db.coachSegments("2026-10-22").segments.isEmpty())
    }

    @Test fun staleCursorRejected() {
        capture()
        val cursor = db.coachDays().cursor!!
        assertEquals("2026-10-24", db.coachSegments("2026-10-24").cursor!!.dateFilter)
        // The cursor's filter must match the read.
        assertEquals("cursor", throws<DiaryError.InvalidData> { db.coachSegments("2026-10-24", cursor) }.reason)
        capture(time = at.plusSeconds(60)) // extends the segment past the cursor
        assertEquals("cursor", throws<DiaryError.InvalidData> { db.coachDays(cursor) }.reason)
        assertEquals("cursor", throws<DiaryError.InvalidData> { db.coachDays(cursor.copy(segmentID = UUID.randomUUID())) }.reason)
    }

    @Test fun badDateFilterRejected() {
        for (bad in listOf("2026-1-01", "2026-13-01", "24-10-2026", "")) {
            assertEquals("date filter", throws<DiaryError.InvalidData> { db.coachSegments(bad) }.reason)
        }
    }

    @Test fun aroundTurnReturnsNinePrecedingAndAtMost20() {
        val turns = seed(List(50) { stored("Synthetic $it", at) })
        val middle = db.coachPage(CoachPageRequest.AroundTurn(turns[25].id))
        assertEquals(turns.subList(16, 36).map { it.id }, middle.exchanges.map { it.turn.id })
        assertTrue(middle.hasEarlier && middle.hasLater)
        // Near the newest turn the page still holds 20, ending at the latest.
        val end = db.coachPage(CoachPageRequest.AroundTurn(turns[45].id))
        assertEquals(turns.subList(30, 50).map { it.id }, end.exchanges.map { it.turn.id })
        assertFalse(end.hasLater)
        val start = db.coachPage(CoachPageRequest.AroundTurn(turns[3].id))
        assertEquals(turns.take(20).map { it.id }, start.exchanges.map { it.turn.id })
        assertFalse(start.hasEarlier)
        throws<DiaryError.NotFound> { db.coachPage(CoachPageRequest.AroundTurn(UUID.randomUUID())) }
    }

    @Test fun atDayOpensFirstConversationOfDay() {
        db.startDay(at, db.head().revision)
        val dayID = db.head().activeDayID!!
        val (first, second) = UUID.randomUUID() to UUID.randomUUID()
        val turns = seed(List(15) { stored("Synthetic before $it", day(-1)) } + List(10) { stored("Synthetic first $it", at, dayID, first) } +
            List(10) { stored("Synthetic second $it", at, dayID, second) })
        val page = db.coachPage(CoachPageRequest.AtDay(dayID))
        assertEquals(turns.subList(6, 26).map { it.id }, page.exchanges.map { it.turn.id })
        assertEquals(listOf(second, first), db.coachSegments("2026-10-24").segments.map { it.segmentID })
    }

    @Test fun atDayWithoutChatIsNotFound() {
        db.startDay(at, db.head().revision)
        capture() // chat on the active day only
        val other = db.transaction(null) { it.resolveDay("2026-10-20", "UTC", at) }
        throws<DiaryError.NotFound> { db.coachPage(CoachPageRequest.AtDay(other.id)) }
        throws<DiaryError.NotFound> { db.coachPage(CoachPageRequest.AtDay(UUID.randomUUID())) }
    }

    @Test fun replaceRebuildsSegments() {
        capture()
        capture(time = day(1))
        val turns = seed(listOf(stored("Synthetic a", day(-3)), stored("Synthetic b", day(-3)), stored("Synthetic c", day(-2))))
        val segments = db.coachDays().segments
        assertEquals(listOf(turns[2].id, turns[0].id), segments.map { it.firstTurnID })
        assertEquals(listOf(2L, 1L), segments.map { it.lastOrdinal })
    }

    @Test fun openRebuildsMissingIndex() {
        db.startDay(at, db.head().revision)
        capture()
        capture(time = at.plusSeconds(60))
        db.transaction(null) { it.head = it.head.copy(activeDayID = null, activeConversationSegmentID = null) }
        capture(time = day(1))
        capture(time = day(1).plusSeconds(60), zone = "Asia/Jerusalem")
        val before = db.coachDays()
        assertEquals(3, before.segments.size)
        db.close()
        SQLiteDatabase.openDatabase(db.file.path, null, SQLiteDatabase.OPEN_READWRITE).use { it.execSQL("DELETE FROM coach_segment") }
        db = DiaryDatabase.open(context, profile.id)
        assertEquals(before, db.coachDays())
    }

    @Test fun sourceTurnIsEarliestTurnNamingMeal() {
        db.startDay(at, db.head().revision)
        capture("Synthetic hello")
        val first = capture()
        val apple = FoodItem(UUID.randomUUID(), "Synthetic apple", 1.0, "piece", NutritionValues(kcal = 95.0), NutritionProvenance.estimate,
            "Synthetic", true, emptyMap())
        val mealID = db.applyCoachWrites(first.id, listOf(CoachWrite.Food("2026-10-24", listOf(apple), null)), at = at).single().mealID!!
        db.applyCoachWrites(capture().id, listOf(CoachWrite.Manual(CoachManualEdit.ScaleMeal(mealID, 190.0, 1))), at = at)
        assertEquals(first.id, db.coachSourceTurn(mealID))
        assertNull(db.coachSourceTurn(UUID.randomUUID()))
    }

    @Test fun tenThousandTurnsHistoryAndSeekStayBounded() {
        val turns = seed(List(10_000) { stored("Synthetic $it", day(-(it / 3).toLong())) })
        val first = db.coachDays()
        assertEquals(30, first.segments.size)
        assertEquals(turns[9999].id, first.segments.first().firstTurnID)
        val second = db.coachDays(first.cursor)
        assertEquals(30, second.segments.size)
        assertTrue(first.hasMore && second.hasMore)
        assertTrue(db.coachSegments(diaryDateLabel(day(-1000), "UTC")).segments.size in 1..30)
        val around = db.coachPage(CoachPageRequest.AroundTurn(turns[5000].id))
        assertEquals(turns.subList(4991, 5011).map { it.id }, around.exchanges.map { it.turn.id })
        assertTrue(around.exchanges.size <= 20)
        assertEquals(0, db.snapshotReads)
    }
}
