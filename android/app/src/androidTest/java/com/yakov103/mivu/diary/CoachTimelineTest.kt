package com.yakov103.mivu.diary

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import androidx.test.core.app.ApplicationProvider
import com.yakov103.mivu.coach.CoachManualEdit
import com.yakov103.mivu.coach.CoachWrite
import java.io.File
import java.time.Instant
import java.util.UUID
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/** Synthetic diaries only; the Coach timeline reads pages by ordinal, never a whole snapshot. */
class CoachTimelineTest {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val profile = DiaryProfile(UUID.randomUUID(), "Synthetic", "en", "UTC", "")
    private lateinit var db: DiaryDatabase
    private val at = Instant.parse("2026-10-24T12:00:00Z")
    private val today = "2026-10-24"

    @Before fun open() {
        File(context.filesDir, "profiles").deleteRecursively()
        db = DiaryDatabase.create(context, profile)
        db.startDay(at, db.head().revision)
    }

    @After fun close() {
        db.close()
        File(context.filesDir, "profiles").deleteRecursively()
    }

    private fun stored(text: String) = CoachTurn(UUID.randomUUID(), at, text, emptyList(), CoachTurnState.completed, "Synthetic reply",
        emptyList(), "UTC", db.head().activeDayID, emptyList())

    private fun seed(count: Int): List<CoachTurn> {
        val turns = List(count) { stored("Synthetic $it") }
        db.replaceAll(db.snapshot().copy(revision = 5, coachTurns = turns))
        db.snapshotReads = 0
        return turns
    }

    private fun turn(text: String = "Synthetic lunch", photos: List<MealPhoto> = emptyList()): CoachTurn {
        val h = db.head()
        return db.captureCoachSubmission(CoachSubmissionPayload(UUID.randomUUID(), text, photos,
            CoachCaptureContext(at, "UTC", h.activeDayID, h.previousDayConfirmedAt, h.activeConversationSegmentID)), h.revision)
    }

    private fun food() = FoodItem(UUID.randomUUID(), "Synthetic apple", 1.0, "piece", NutritionValues(kcal = 95.0),
        NutritionProvenance.estimate, "Synthetic", true, emptyMap())

    private fun logged(): CoachReceipt = db.applyCoachWrites(turn().id, listOf(CoachWrite.Food(today, listOf(food()), null)), at = at).single()

    private fun exchange(receipt: CoachReceipt) = db.coachPage(CoachPageRequest.Latest).exchanges.single { it.turn.id == receipt.turnID }

    @Test fun latestPageHoldsTwentyNewestOldestFirst() {
        val turns = seed(25)
        val page = db.coachPage(CoachPageRequest.Latest)
        assertEquals(turns.takeLast(20).map { it.id }, page.exchanges.map { it.turn.id })
        assertTrue(page.exchanges.zipWithNext().all { (a, b) -> a.ordinal < b.ordinal })
        assertTrue(page.hasEarlier)
        assertFalse(page.hasLater)
    }

    @Test fun beforeAndAfterCursorsPage() {
        val turns = seed(45)
        val latest = db.coachPage(CoachPageRequest.Latest)
        val earlier = db.coachPage(CoachPageRequest.Before(latest.exchanges.first().ordinal))
        assertEquals(turns.subList(5, 25).map { it.id }, earlier.exchanges.map { it.turn.id })
        assertTrue(earlier.hasEarlier && earlier.hasLater)
        val first = db.coachPage(CoachPageRequest.Before(earlier.exchanges.first().ordinal))
        assertEquals(turns.take(5).map { it.id }, first.exchanges.map { it.turn.id })
        assertFalse(first.hasEarlier)
        val later = db.coachPage(CoachPageRequest.After(first.exchanges.last().ordinal))
        assertEquals(earlier.exchanges.map { it.turn.id }, later.exchanges.map { it.turn.id })
        assertTrue(later.hasEarlier && later.hasLater)
        val range = db.coachPage(CoachPageRequest.Range(earlier.exchanges[2].ordinal, earlier.exchanges[4].ordinal))
        assertEquals(turns.subList(7, 10).map { it.id }, range.exchanges.map { it.turn.id })
    }

    @Test fun tenThousandTurnsStayBounded() {
        seed(10_000)
        var page = db.coachPage(CoachPageRequest.Latest)
        repeat(5) { page = db.coachPage(CoachPageRequest.Before(page.exchanges.first().ordinal)) }
        assertEquals(20, page.exchanges.size)
        assertEquals("Synthetic 9880", page.exchanges.first().turn.text)
        assertEquals(0, db.snapshotReads)
    }

    @Test fun receiptTargetShowsMovedMeal() {
        val receipt = logged()
        val meal = db.read { it.meal(receipt.mealID!!) }!!
        db.applyCoachWrites(turn().id, listOf(CoachWrite.Manual(CoachManualEdit.Move(meal.id, "2026-10-23", meal.revision, meal.dayID))), at = at)
        val target = exchange(receipt).targets[receipt.operationKey] as CoachReceiptTarget.Meal
        assertEquals(meal.id, target.meal.id)
        assertEquals("2026-10-23", target.localDate)
        assertEquals(today, exchange(receipt).receipts.single().targetLocalDate)
    }

    @Test fun undoAvailableUntilManualEdit() {
        val receipt = logged()
        assertEquals(CoachUndoState.Available, exchange(receipt).undo[receipt.operationKey])
        val meal = db.read { it.meal(receipt.mealID!!) }!!
        db.scaleMeal(meal.id, 190.0, meal.revision)
        assertNull(exchange(receipt).undo[receipt.operationKey])
    }

    @Test fun undoneAfterUndo() {
        val receipt = logged()
        db.undoCoachChange(receipt.operationKey)
        val exchange = exchange(receipt)
        assertEquals(CoachUndoState.Undone, exchange.undo[receipt.operationKey])
        assertEquals(CoachReceiptTarget.Unavailable, exchange.targets[receipt.operationKey])
    }

    @Test fun chooseDayResolvesPreviousDay() {
        val t = turn()
        db.transaction(null) { it.failCoachTurn(t.id, CoachTurnState.needsClarification, needsDayChoice = true) }
        db.chooseCoachDay(t.id, usePrevious = true)
        val chosen = db.read { it.coachTurnWithoutPhotos(t.id) }!!
        assertEquals(t.activeDayID, chosen.resolvedDayID)
        assertNull(chosen.needsDayChoice)
        assertEquals(CoachTurnState.captured, chosen.state)
        db.transaction(null) { it.failCoachTurn(t.id, CoachTurnState.needsRetry) }
        db.retryCoachTurn(t.id)
        assertEquals(CoachTurnState.captured, db.read { it.coachTurnWithoutPhotos(t.id) }!!.state)
    }

    @Test fun coachPhotoBytesReadOnDemand() {
        val photo = MealPhoto(UUID.randomUUID(), byteArrayOf(1, 2, 3), at, PhotoRole.unspecified)
        val t = turn(photos = listOf(photo))
        val listed = db.coachPage(CoachPageRequest.Latest).exchanges.single().turn
        assertTrue(listed.photos.isEmpty())
        assertEquals(listOf(photo.id), listed.photoIDs)
        assertArrayEquals(photo.data, db.coachPhotoBytes(t.id, photo.id))
        assertNull(db.coachPhotoBytes(t.id, UUID.randomUUID()))
    }

    @Test fun receiptWithUnreadableDayIsUnavailable() {
        val receipt = logged()
        val day = db.read { it.meal(receipt.mealID!!) }!!.dayID.toString().uppercase()
        db.close()
        // Synthetic corruption: the meal payload names a day that does not exist (its parent row still does).
        SQLiteDatabase.openDatabase(File(context.filesDir, "profiles/${profile.id.toString().uppercase()}/diary.sqlite").path, null,
            SQLiteDatabase.OPEN_READWRITE).use {
            it.execSQL("UPDATE meal SET payload = CAST(replace(CAST(payload AS TEXT), ?, ?) AS BLOB)",
                arrayOf(day, UUID.randomUUID().toString().uppercase()))
        }
        db = DiaryDatabase.open(context, profile.id)
        assertEquals(CoachReceiptTarget.Unavailable, exchange(receipt).targets[receipt.operationKey])
    }

    /** A meal captured outside Coach with its Coach turn still pending on it (the turn ID is the meal's submission). */
    private fun pendingMeal(): Pair<DiaryMeal, CoachTurn> {
        val h = db.head()
        val meal = db.captureProjection("Synthetic plate", emptyList(), false, h.activeDayID!!, at, expectedRevision = h.revision)
        val turn = CoachTurn(meal.submissions.single().id, at, "Synthetic plate", emptyList(), CoachTurnState.needsRetry, null, emptyList(),
            "UTC", h.activeDayID, emptyList(), pendingMealID = meal.id, pendingMealRevision = 0)
        db.replaceAll(db.snapshot().let { it.copy(coachTurns = it.coachTurns + turn) })
        return meal to turn
    }

    @Test fun coachTurnForMealFindsPendingTurn() {
        val (meal, pending) = pendingMeal()
        turn("Synthetic later message")
        assertEquals(pending.id, db.coachTurnForMeal(meal.id))
        assertNull(db.coachTurnForMeal(UUID.randomUUID()))
    }

    @Test fun coachTurnForMealIgnoresReceiptOnlyTurns() {
        val receipt = logged()
        assertNull(db.coachTurnForMeal(receipt.mealID!!))
        // A turn naming the meal as pending without the meal holding its submission is not the meal's input either.
        val (meal, _) = pendingMeal()
        val stray = stored("Synthetic stray").copy(pendingMealID = meal.id, pendingMealRevision = 0)
        db.replaceAll(db.snapshot().let { it.copy(revision = it.revision + 1, coachTurns = it.coachTurns + stray) })
        assertEquals(meal.submissions.single().id, db.coachTurnForMeal(meal.id))
    }
}
