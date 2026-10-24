package com.yakov103.mivu.diary

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import java.io.File
import java.time.Instant
import java.util.UUID
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test

class ManualNutritionStoreTest {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val profile = DiaryProfile(UUID.randomUUID(), "Synthetic", "en", "UTC", "")
    private val at = Instant.parse("2026-10-24T12:00:00.123456789Z") // sub-second, as a device clock gives
    private lateinit var db: DiaryDatabase

    @Before fun open() {
        File(context.filesDir, "profiles").deleteRecursively()
        db = DiaryDatabase.create(context, profile)
        db.startDay(at, db.head().revision)
    }

    @After fun close() {
        db.close()
        File(context.filesDir, "profiles").deleteRecursively()
    }

    private inline fun <reified E : Throwable> throws(block: () -> Unit) {
        try { block(); fail("expected ${E::class.simpleName}") } catch (e: Throwable) { if (e !is E) throw e }
    }

    private fun item(name: String, kcal: Double = 250.0) = FoodItem(UUID.randomUUID(), name, 1.0, "serving",
        NutritionValues(kcal, 30.0, 10.0, 8.0), NutritionProvenance.user, "", false,
        mapOf("kcal" to NutritionProvenance.user))

    private fun create(items: List<FoodItem> = listOf(item("synthetic oats")), mealID: UUID = UUID.randomUUID(),
                       submissionID: UUID = UUID.randomUUID()) = ManualNutritionPayload(profile.id, mealID, submissionID,
        ManualNutritionOperation.create, db.prepareManualNutritionTarget(ManualNutritionDayChoice.Current, at), at, at,
        MealTimePrecision.exact, null, items)

    @Test fun manualCreateSavesUserProvenanceItem() {
        val payload = create()
        assertTrue(payload.target is ManualNutritionTarget.Active)
        val result = db.saveManualNutrition(payload, db.head().revision)
        assertFalse(result.replayed)
        assertEquals(payload.submissionID, result.submissionID)
        val meal = db.read { it.meal(payload.mealID) }!!
        assertEquals(result.meal, meal)
        assertEquals(1, meal.revision)
        assertEquals(MealTimePrecision.exact, meal.timePrecision)
        assertEquals(db.head().activeDayID, meal.dayID)
        assertEquals(payload.items, meal.items)
        assertEquals(NutritionProvenance.user, meal.items.single().provenance)
        val sub = meal.submissions.single()
        assertEquals("Entered manually", sub.text)
        assertEquals(SubmissionState.saved, sub.state)
        assertEquals(payload.items, sub.proposal!!.items)
        assertEquals(result.acceptance, sub.manualAcceptance)
        assertTrue(Regex("[0-9a-f]{64}").matches(result.acceptance.payloadFingerprint))
    }

    @Test fun manualRetryWithSamePayloadReturnsSameMeal() {
        val payload = create()
        val first = db.saveManualNutrition(payload, db.head().revision)
        val head = db.head()
        assertTrue(db.manualNutritionResult(payload)!!.replayed)
        val retry = db.saveManualNutrition(payload, head.revision)
        assertTrue(retry.replayed)
        assertEquals(first.meal, retry.meal)
        assertEquals(head, db.head())
        assertEquals(1, db.snapshot().meals.size)
    }

    @Test fun manualRetryWithChangedPayloadRejected() {
        val payload = create()
        db.saveManualNutrition(payload, db.head().revision)
        val head = db.head()
        val changed = payload.copy(items = listOf(payload.items.single().copy(nutrition = NutritionValues(kcal = 900.0))))
        throws<DiaryError.InvalidData> { db.saveManualNutrition(changed, head.revision) }
        throws<DiaryError.InvalidData> { db.manualNutritionResult(changed) }
        assertEquals(head, db.head())
    }

    @Test fun manualAppendToSavedMealBumpsRevision() {
        val first = db.saveManualNutrition(create(), db.head().revision).meal
        val target = db.prepareManualNutritionTarget(ManualNutritionDayChoice.Recorded(first.dayID), at)
        val added = listOf(item("synthetic banana", 105.0))
        val append = ManualNutritionPayload(profile.id, first.id, UUID.randomUUID(), ManualNutritionOperation.append,
            target, at, first.eatenAt, MealTimePrecision.exact, first.revision, added)
        throws<DiaryError.StaleRevision> { db.saveManualNutrition(append.copy(expectedMealRevision = 2), db.head().revision) }
        val result = db.saveManualNutrition(append, db.head().revision)
        assertEquals(2, result.meal.revision)
        assertEquals(first.items + added, result.meal.items)
        assertEquals(listOf(first.submissions.single().id, append.submissionID), result.meal.submissions.map { it.id })
        assertEquals(1, result.meal.submissions.last().baseRevision)
        assertEquals(result.meal, db.read { it.meal(first.id) })
    }
}
