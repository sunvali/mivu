package com.yakov103.mivu.diary

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import java.io.File
import java.time.Instant
import java.util.UUID
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test

class MealAnalysisTest {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val profile = DiaryProfile(UUID.randomUUID(), "Synthetic", "en", "UTC", "")
    private val at = Instant.parse("2026-10-24T12:00:00Z")
    private val day = TrackingDay(UUID.randomUUID(), "2026-10-24", "UTC", at, DayCompleteness.unknown)
    private lateinit var db: DiaryDatabase

    @Before fun open() {
        File(context.filesDir, "profiles").deleteRecursively()
        db = DiaryDatabase.create(context, profile)
    }

    @After fun close() {
        db.close()
        File(context.filesDir, "profiles").deleteRecursively()
    }

    private inline fun <reified E : Throwable> throws(block: () -> Unit) {
        try { block(); fail("expected ${E::class.simpleName}") } catch (e: Throwable) { if (e !is E) throw e }
    }

    private fun item(name: String) = FoodItem(UUID.randomUUID(), name, 1.0, "serving", NutritionValues(kcal = 100.0),
        NutritionProvenance.estimate, "", true, emptyMap())

    private fun photo() = MealPhoto(UUID.randomUUID(), byteArrayOf(1, 2, 3), at, PhotoRole.unspecified)

    /** A day with one unsaved meal (revision 0) and one submission awaiting analysis. */
    private fun seed(reviewFirst: Boolean = false, state: SubmissionState = SubmissionState.captured,
                     photos: List<MealPhoto> = emptyList()): Pair<DiaryMeal, MealSubmission> {
        val sub = MealSubmission(UUID.randomUUID(), 0, "synthetic soup", emptyList(), reviewFirst, state)
        val meal = DiaryMeal(UUID.randomUUID(), day.id, at, at, 0, items = emptyList(), photos = photos, submissions = listOf(sub))
        db.transaction(db.head().revision) { it.putDay(day); it.putMeal(meal) }
        return meal to sub
    }

    private fun output(meal: DiaryMeal, sub: MealSubmission, base: Int = 0) =
        AnalysisOutput(1, profile.id, meal.id, sub.id, base, listOf(item("synthetic soup")))

    private fun meal(id: UUID) = db.read { it.meal(id) }

    @Test fun applyIsIdempotentWhenAlreadySaved() {
        val (meal, sub) = seed()
        val out = output(meal, sub)
        db.applyAnalysis(out)
        val saved = meal(meal.id)!!
        assertEquals(1, saved.revision)
        assertEquals(out.items, saved.items)
        assertEquals(SubmissionState.saved, saved.submissions.single().state)
        val head = db.head()
        db.applyAnalysis(out)
        assertEquals(head, db.head())
        assertEquals(saved, meal(meal.id))
    }

    @Test fun cancelledSubmissionIsNotFound() {
        val (meal, sub) = seed(state = SubmissionState.cancelled)
        throws<DiaryError.NotFound> { db.applyAnalysis(output(meal, sub)) }
        assertEquals(0, meal(meal.id)!!.revision)
    }

    @Test fun staleBaseRevisionAfterEditIsRejectedAndEditKept() {
        val (meal, sub) = seed()
        val edit = listOf(item("synthetic edited soup"))
        db.editMealItems(meal.id, edit, 0)
        val edited = meal(meal.id)!!
        assertEquals(1, edited.revision)
        assertEquals(edit, edited.items)
        throws<DiaryError.StaleRevision> { db.applyAnalysis(output(meal, sub)) }
        assertEquals(edited, meal(meal.id))
        throws<DiaryError.StaleRevision> { db.editMealItems(meal.id, listOf(item("late")), 0) }
    }

    @Test fun deletedMealStaysDeletedWhenLateResultArrives() {
        val (meal, sub) = seed()
        db.deleteMeal(meal.id, db.head().revision)
        throws<DiaryError.NotFound> { db.applyAnalysis(output(meal, sub)) }
        val snapshot = db.snapshot()
        assertTrue(snapshot.meals.isEmpty())
        assertEquals(listOf(meal.id), snapshot.deletedMealIDs)
    }

    @Test fun reviewFirstStoresProposal() {
        val (meal, sub) = seed(reviewFirst = true)
        val out = output(meal, sub)
        db.applyAnalysis(out)
        val stored = meal(meal.id)!!
        assertEquals(0, stored.revision)
        assertTrue(stored.items.isEmpty())
        assertEquals(SubmissionState.awaitingReview, stored.submissions.single().state)
        assertEquals(out, stored.submissions.single().proposal)
    }

    @Test fun acceptReviewIdempotent() {
        val (meal, sub) = seed(reviewFirst = true)
        val out = output(meal, sub)
        db.applyAnalysis(out)
        db.acceptReview(meal.id, sub.id, 0)
        val saved = meal(meal.id)!!
        assertEquals(1, saved.revision)
        assertEquals(out.items, saved.items)
        assertEquals(SubmissionState.saved, saved.submissions.single().state)
        val head = db.head()
        db.acceptReview(meal.id, sub.id, 0)
        assertEquals(head, db.head())
    }

    @Test fun tombstonedIdCannotBeInsertedAgain() {
        val (meal, _) = seed()
        db.deleteMeal(meal.id, db.head().revision)
        throws<DiaryError.InvalidData> { db.transaction(db.head().revision) { it.putMeal(meal) } }
        throws<DiaryError.NotFound> { db.deleteMeal(meal.id, db.head().revision) }
    }

    @Test fun nextPendingSubmissionIsPreparedAgainstTheCurrentRevision() {
        val (meal, sub) = seed()
        assertEquals(meal.id to sub.id, db.nextPendingMealSubmission())
        db.editMealItems(meal.id, listOf(item("synthetic edit")), 0)
        db.prepareAnalysis(meal.id, sub.id)
        assertEquals(1, meal(meal.id)!!.submissions.first { it.id == sub.id }.baseRevision)
        db.applyAnalysis(output(meal, sub, base = 1))
        assertNull(db.nextPendingMealSubmission())
        throws<DiaryError.InvalidData> { db.prepareAnalysis(meal.id, sub.id) }
    }

    @Test fun deleteMealMovesPhotosBackToTurnsWithProgressAndKeepsTheDiaryValid() {
        val pendingPhoto = photo()
        val receiptPhoto = photo()
        val (meal, _) = seed(photos = listOf(pendingPhoto, receiptPhoto))
        val weight = WeightEntry(UUID.randomUUID(), day.id, at, 70.0, "kg")
        fun turn(photoID: UUID) = CoachTurn(UUID.randomUUID(), at, "synthetic", emptyList(), CoachTurnState.captured,
            receipts = emptyList(), captureTimeZoneID = "UTC", photoIDs = listOf(photoID))
        val pending = turn(pendingPhoto.id).copy(pendingMealID = meal.id, pendingMealRevision = 0)
        val receiptTurn = turn(receiptPhoto.id).let {
            it.copy(state = CoachTurnState.completed, receipts = listOf(
                CoachReceipt("${it.id}/log_meal", it.id, dayID = day.id, mealID = meal.id, committedRevision = 2, resultJSON = "{}"),
                CoachReceipt("${it.id}/log_weight", it.id, dayID = day.id, weightID = weight.id, committedRevision = 2, resultJSON = "{}"),
            ))
        }
        db.transaction(db.head().revision) { it.putWeight(weight); it.putCoachTurn(pending); it.putCoachTurn(receiptTurn) }

        db.deleteMeal(meal.id, db.head().revision)

        val snapshot = db.snapshot()
        snapshot.validate()
        val after = snapshot.coachTurns.associateBy { it.id }
        // No surviving progress: the photo leaves the turn and the pending turn asks again.
        assertEquals(emptyList<UUID>(), after.getValue(pending.id).photoIDs)
        assertEquals(CoachTurnState.needsClarification, after.getValue(pending.id).state)
        // A logged weight survives: the photo moves back to the turn.
        assertEquals(listOf(receiptPhoto), after.getValue(receiptTurn.id).photos)
        assertEquals(listOf(receiptPhoto.id), after.getValue(receiptTurn.id).photoIDs)
        assertEquals(CoachTurnState.completed, after.getValue(receiptTurn.id).state)
    }

    @Test fun putMealDroppingATurnPhotoIsRejected() {
        val shared = photo()
        val (meal, _) = seed(photos = listOf(shared))
        val turn = CoachTurn(UUID.randomUUID(), at, "synthetic", emptyList(), CoachTurnState.captured, receipts = emptyList(),
            captureTimeZoneID = "UTC", photoIDs = listOf(shared.id), pendingMealID = meal.id, pendingMealRevision = 0)
        db.transaction(db.head().revision) { it.putCoachTurn(turn) }
        val stored = meal(meal.id)!!
        throws<DiaryError.InvalidData> { db.transaction(db.head().revision) { it.putMeal(stored.copy(photos = emptyList())) } }
        db.snapshot().validate()
    }
}
