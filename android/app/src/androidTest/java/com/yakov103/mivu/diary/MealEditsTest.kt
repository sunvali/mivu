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

class MealEditsTest {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val profile = DiaryProfile(UUID.randomUUID(), "Synthetic", "en", "UTC", "")
    private val at = Instant.parse("2026-10-24T12:00:00Z")
    private val day = TrackingDay(UUID.randomUUID(), "2026-10-24", "UTC", at, DayCompleteness.unknown)
    private val nextDay = TrackingDay(UUID.randomUUID(), "2026-10-25", "UTC", at.plusSeconds(86_400), DayCompleteness.unknown)
    private lateinit var db: DiaryDatabase

    @Before fun open() {
        File(context.filesDir, "profiles").deleteRecursively()
        db = DiaryDatabase.create(context, profile)
        db.transaction(0) { it.putDay(day); it.putDay(nextDay) }
    }

    @After fun close() {
        db.close()
        File(context.filesDir, "profiles").deleteRecursively()
    }

    private inline fun <reified E : Throwable> throws(block: () -> Unit) {
        try { block(); fail("expected ${E::class.simpleName}") } catch (e: Throwable) { if (e !is E) throw e }
    }

    private fun item(name: String, quantity: Double, unit: String, kcal: Double?, protein: Double? = null) =
        FoodItem(UUID.randomUUID(), name, quantity, unit, NutritionValues(kcal = kcal, protein = protein),
            NutritionProvenance.estimate, "", false, emptyMap())

    /** A saved meal (revision 1) with [items], plus optional photos and extra submissions. */
    private fun seed(items: List<FoodItem>, photos: List<MealPhoto> = emptyList(),
                     extra: List<MealSubmission> = emptyList()): DiaryMeal {
        val meal = DiaryMeal(UUID.randomUUID(), day.id, at, at, 1, items = items, photos = photos, submissions = extra)
        db.transaction(db.head().revision) { it.putMeal(meal) }
        return meal
    }

    private fun meal(id: UUID) = db.read { it.meal(id) }

    @Test fun editItemRecomputesNutritionFromBasis() {
        val rice = item("synthetic rice", 100.0, "g", kcal = 200.0, protein = 10.0)
        val meal = seed(listOf(rice))
        db.editItem(meal.id, rice.copy(quantity = 150.0), emptySet(), expectedRevision = 1)
        val edited = meal(meal.id)!!
        val saved = edited.items.single()
        assertEquals(300.0, saved.nutrition.kcal!!, 1e-9)
        assertEquals(15.0, saved.nutrition.protein!!, 1e-9)
        assertEquals(2.0, saved.nutritionBasis!!.kcal!!, 1e-9)
        assertEquals(2, edited.revision)
        assertEquals("Direct item edit", edited.submissions.last().text)
        assertEquals(SubmissionState.saved, edited.submissions.last().state)

        throws<DiaryError.StaleRevision> { db.editItem(meal.id, saved.copy(quantity = 1.0), emptySet(), expectedRevision = 1) }
        // iOS edge case: an unrelated unit cannot carry known nutrients forward.
        throws<DiaryError.InvalidAmountUnitChange> { db.editItem(meal.id, saved.copy(unit = "serving"), emptySet(), expectedRevision = 2) }
        // An explicit value is the person's own.
        db.editItem(meal.id, saved.copy(unit = "serving", quantity = 1.0, nutrition = NutritionValues(kcal = 250.0)),
            setOf("kcal", "protein"), expectedRevision = 2)
        val explicit = meal(meal.id)!!.items.single()
        assertEquals(250.0, explicit.nutrition.kcal!!, 1e-9)
        assertNull(explicit.nutrition.protein)
        assertEquals(NutritionProvenance.user, explicit.provenance)
        assertEquals(NutritionProvenance.user, explicit.nutrientSources["kcal"])
    }

    @Test fun editItemInReviewChangesOnlyTheProposal() {
        val rice = item("synthetic rice", 100.0, "g", kcal = 200.0)
        val proposed = item("synthetic beans", 50.0, "g", kcal = 60.0)
        val subID = UUID.randomUUID()
        val review = MealSubmission(subID, 1, "synthetic", emptyList(), true, SubmissionState.awaitingReview,
            AnalysisOutput(1, profile.id, UUID.randomUUID(), subID, 1, listOf(proposed)))
        val meal = DiaryMeal(UUID.randomUUID(), day.id, at, at, 1, items = listOf(rice), photos = emptyList(), submissions = emptyList())
        val withReview = meal.copy(submissions = listOf(review.copy(proposal = review.proposal!!.copy(mealID = meal.id))))
        db.transaction(db.head().revision) { it.putMeal(withReview) }
        db.editItem(meal.id, proposed.copy(quantity = 100.0), emptySet(), reviewSubmissionID = subID, expectedRevision = 1)
        val after = meal(meal.id)!!
        assertEquals(1, after.revision)
        assertEquals(listOf(rice), after.items)
        assertEquals(120.0, after.submissions.single().proposal!!.items.single().nutrition.kcal!!, 1e-9)
        throws<DiaryError.NotFound> { db.editItem(meal.id, rice, emptySet(), reviewSubmissionID = subID) }
    }

    @Test fun deleteLastItemRejected() {
        val a = item("synthetic a", 1.0, "serving", 100.0)
        val b = item("synthetic b", 1.0, "serving", 50.0)
        val meal = seed(listOf(a, b))
        throws<DiaryError.StaleRevision> { db.deleteItem(meal.id, a.id, 0) }
        throws<DiaryError.NotFound> { db.deleteItem(meal.id, UUID.randomUUID(), 1) }
        db.deleteItem(meal.id, a.id, 1)
        val after = meal(meal.id)!!
        assertEquals(listOf(b), after.items)
        assertEquals(2, after.revision)
        assertEquals("Direct item delete", after.submissions.last().text)
        throws<DiaryError.InvalidData> { db.deleteItem(meal.id, b.id, 2) }
        assertEquals(listOf(b), meal(meal.id)!!.items)
    }

    @Test fun scaleMealHitsTargetKcal() {
        val rice = item("synthetic rice", 100.0, "g", kcal = 200.0)
        val bread = item("synthetic bread", 1.0, "slice", kcal = 100.0)
        val water = item("synthetic water", 250.0, "ml", kcal = null)
        val meal = seed(listOf(rice, bread, water))
        throws<DiaryError.StaleRevision> { db.scaleMeal(meal.id, 450.0, 0) }
        db.scaleMeal(meal.id, 450.0, 1)
        val after = meal(meal.id)!!
        assertEquals(listOf(150.0, 1.5, 375.0), after.items.map { it.quantity })
        assertEquals(450.0, after.items.mapNotNull { it.nutrition.kcal }.sum(), 1e-9)
        assertNull(after.items[2].nutrition.kcal)
        assertEquals("Direct meal scale", after.submissions.last().text)
        // iOS edge case: one ratio must stay within 0.1...3.
        throws<DiaryError.InvalidData> { db.scaleMeal(meal.id, 450.0 * 3.1, 2) }
    }

    @Test fun scaleMealUnknownKcalRejected() {
        val meal = seed(listOf(item("synthetic tea", 1.0, "cup", kcal = null)))
        throws<DiaryError.InvalidData> { db.scaleMeal(meal.id, 100.0, 1) }
        throws<DiaryError.InvalidData> { db.scaleMeal(meal.id, Double.NaN, 1) }
        val pending = seed(listOf(item("synthetic rice", 100.0, "g", kcal = 200.0)),
            extra = listOf(MealSubmission(UUID.randomUUID(), 1, "synthetic", emptyList(), false, SubmissionState.captured)))
        throws<DiaryError.InvalidData> { db.scaleMeal(pending.id, 300.0, 1) }
        assertEquals(1, meal(pending.id)!!.revision)
    }

    @Test fun deletePhotoKeepsMealAndRepairsTurns() {
        val photo = MealPhoto(UUID.randomUUID(), byteArrayOf(1, 2, 3), at, PhotoRole.unspecified)
        val kept = MealPhoto(UUID.randomUUID(), byteArrayOf(4, 5), at, PhotoRole.after)
        val pendingSub = MealSubmission(UUID.randomUUID(), 1, "synthetic", listOf(photo.id), false, SubmissionState.captured)
        val meal = seed(listOf(item("synthetic rice", 100.0, "g", 200.0)), photos = listOf(photo, kept), extra = listOf(pendingSub))
        val turn = CoachTurn(UUID.randomUUID(), at, "synthetic", emptyList(), CoachTurnState.analyzing, receipts = emptyList(),
            captureTimeZoneID = "UTC", photoIDs = listOf(photo.id, kept.id), pendingMealID = meal.id, pendingMealRevision = 1)
        db.transaction(db.head().revision) { it.putCoachTurn(turn) }

        db.deletePhoto(meal.id, photo.id)
        val after = meal(meal.id)!!
        assertEquals(listOf(kept), after.photos)
        assertEquals(meal.items, after.items)
        val sub = after.submissions.single()
        assertEquals(SubmissionState.cancelled, sub.state)
        assertTrue(sub.photoIDs.isEmpty())
        assertEquals(listOf(kept.id), db.read { it.coachTurn(turn.id) }!!.photoIDs)
        assertNull(db.photoBytes(meal.id, photo.id))

        val head = db.head()
        db.deletePhoto(meal.id, photo.id) // already gone: nothing to commit
        assertEquals(head, db.head())
        throws<DiaryError.NotFound> { db.deletePhoto(UUID.randomUUID(), kept.id) }
    }

    @Test fun deletePhotoKeepsOwnTurnCopyAndSavedSubmission() {
        val photo = MealPhoto(UUID.randomUUID(), byteArrayOf(1, 2, 3), at, PhotoRole.unspecified)
        val savedSub = MealSubmission(UUID.randomUUID(), 1, "synthetic", listOf(photo.id), false, SubmissionState.saved)
        val meal = seed(listOf(item("synthetic rice", 100.0, "g", 200.0)), photos = listOf(photo), extra = listOf(savedSub))
        // A turn holding its own copy of the photo still reaches it, so it keeps the ID.
        val turn = CoachTurn(UUID.randomUUID(), at, "synthetic", listOf(photo), CoachTurnState.analyzing, receipts = emptyList(),
            captureTimeZoneID = "UTC", photoIDs = listOf(photo.id), pendingMealID = meal.id, pendingMealRevision = 1)
        db.transaction(db.head().revision) { it.putCoachTurn(turn) }

        db.deletePhoto(meal.id, photo.id)
        val sub = meal(meal.id)!!.submissions.single()
        assertEquals(SubmissionState.saved, sub.state)
        assertTrue(sub.photoIDs.isEmpty())
        assertEquals(listOf(photo.id), db.read { it.coachTurn(turn.id) }!!.photoIDs)
    }

    @Test fun moveMealToAnotherDayUpdatesBothTotals() {
        val meal = seed(listOf(item("synthetic rice", 100.0, "g", 200.0)))
        throws<DiaryError.StaleRevision> { db.moveMeal(meal.id, nextDay.id, expectedDayID = nextDay.id) }
        // iOS edge case: the new time must fall on the destination day.
        throws<DiaryError.InvalidData> { db.moveMeal(meal.id, nextDay.id, eatenAt = at) }
        val eaten = at.plusSeconds(86_400 + 600)
        db.moveMeal(meal.id, nextDay.id, eatenAt = eaten, expectedRevision = 1, expectedDayID = day.id)
        assertTrue(db.dayDetail(day.id).meals.isEmpty())
        val moved = db.dayDetail(nextDay.id).meals.single()
        assertEquals(200.0, nutritionTotals(moved.items).kcal!!, 1e-9)
        assertEquals(eaten, moved.eatenAt)
        assertEquals(MealTimePrecision.exact, moved.timePrecision)
        assertEquals(1, moved.revision)
        val week = db.diaryWeek("2026-10-24", "2026-10-25")
        assertEquals(listOf(0, 1), week.map { it.mealCount })
        assertEquals(200.0, week[1].totals.kcal!!, 1e-9)
    }

    @Test fun moveToTombstonedOrMissingDayRejected() {
        val meal = seed(listOf(item("synthetic rice", 100.0, "g", 200.0)))
        throws<DiaryError.NotFound> { db.moveMeal(meal.id, UUID.randomUUID()) }
        db.deleteMeal(meal.id, db.head().revision)
        throws<DiaryError.NotFound> { db.moveMeal(meal.id, nextDay.id) }
        assertNull(meal(meal.id))
    }

    @Test fun staleRevisionNeverOverwrites() {
        val rice = item("synthetic rice", 100.0, "g", kcal = 200.0)
        val bread = item("synthetic bread", 1.0, "slice", kcal = 100.0)
        val meal = seed(listOf(rice, bread))
        db.editItem(meal.id, rice.copy(quantity = 200.0), emptySet(), expectedRevision = 1) // meal now at revision 2
        val head = db.head()
        val current = meal(meal.id)
        throws<DiaryError.StaleRevision> { db.editItem(meal.id, rice.copy(quantity = 50.0), emptySet(), expectedRevision = 1) }
        throws<DiaryError.StaleRevision> { db.deleteItem(meal.id, bread.id, 1) }
        throws<DiaryError.StaleRevision> { db.scaleMeal(meal.id, 300.0, 1) }
        throws<DiaryError.StaleRevision> { db.moveMeal(meal.id, nextDay.id, expectedRevision = 1) }
        assertEquals(head, db.head())
        assertEquals(current, meal(meal.id))
    }
}
