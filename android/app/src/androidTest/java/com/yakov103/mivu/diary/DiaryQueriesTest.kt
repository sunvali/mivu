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
import org.junit.Before
import org.junit.Test

class DiaryQueriesTest {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val profile = DiaryProfile(UUID.randomUUID(), "Synthetic", "en", "America/New_York", "")
    private val at = Instant.parse("2026-10-21T16:00:00Z")
    private lateinit var db: DiaryDatabase

    @Before fun open() {
        File(context.filesDir, "profiles").deleteRecursively()
        db = DiaryDatabase.create(context, profile)
    }

    @After fun close() {
        db.close()
        File(context.filesDir, "profiles").deleteRecursively()
    }

    private fun addDay(date: String) = TrackingDay(UUID.randomUUID(), date, profile.timeZoneID, at, DayCompleteness.unknown)
        .also { d -> db.transaction(db.head().revision) { it.putDay(d) } }

    private fun item(kcal: Double) = FoodItem(UUID.randomUUID(), "synthetic", 1.0, "serving",
        NutritionValues(kcal, 1.0, 1.0, 1.0), NutritionProvenance.user, "", false, emptyMap())

    private fun addMeal(day: TrackingDay, revision: Int, eatenAt: Instant = at, items: List<FoodItem> = emptyList(),
                        photos: List<MealPhoto> = emptyList(), state: SubmissionState? = null): DiaryMeal {
        val id = UUID.randomUUID()
        val submissions = state?.let { listOf(MealSubmission(UUID.randomUUID(), 0, "synthetic", photos.map { p -> p.id }, false, it)) }.orEmpty()
        val meal = DiaryMeal(id, day.id, at, eatenAt, revision, items = items, photos = photos, submissions = submissions)
        db.transaction(db.head().revision) { it.putMeal(meal) }
        return meal
    }

    @Test fun weekSummariesCountMealsAndPending() {
        val d1 = addDay("2026-10-21")
        addDay("2026-10-23")
        addMeal(d1, 1, items = listOf(item(300.0), item(200.0)), state = SubmissionState.saved)
        addMeal(d1, 0, state = SubmissionState.analyzing)
        val week = db.diaryWeek("2026-10-19", "2026-10-25")
        assertEquals((19..25).map { "2026-10-$it" }, week.map { it.localDate })
        val s = week.first { it.localDate == "2026-10-21" }
        assertEquals(d1, s.day)
        assertEquals(2, s.mealCount); assertEquals(1, s.savedMealCount); assertEquals(1, s.pendingMealCount)
        assertEquals(500.0, s.totals.kcal!!, 0.0)
        assertEquals(0, week.first { it.localDate == "2026-10-23" }.mealCount)
        assertNull(week.first { it.localDate == "2026-10-20" }.day)
        assertEquals("2026-10-21", db.earliestRecordDate())
    }

    @Test fun weekReadsNoPhotoBytes() {
        val d = addDay("2026-10-21")
        val photo = MealPhoto(UUID.randomUUID(), ByteArray(3_000_000), at, PhotoRole.unspecified)
        addMeal(d, 1, items = listOf(item(100.0)), photos = listOf(photo), state = SubmissionState.saved)
        assertEquals(1, db.diaryWeek("2026-10-21", "2026-10-21").single().savedMealCount)
        assertTrue(db.dayDetail(d.id).meals.single().photos.single().data.isEmpty())
    }

    @Test fun dayDetailSortsByEatenAt() {
        val d = addDay("2026-10-21")
        val late = addMeal(d, 1, at.plusSeconds(3600), listOf(item(1.0)))
        val early = addMeal(d, 1, at, listOf(item(1.0)))
        assertEquals(listOf(early.id, late.id), db.dayDetail(d.id).meals.map { it.id })
    }

    @Test fun setCompletenessBumpsRevisionAndChangesStatus() {
        val d = addDay("2026-10-21")
        val before = db.head().revision
        db.setCompleteness(d.id, DayCompleteness.untracked, before)
        assertEquals(before + 1, db.head().revision)
        val day = db.dayDetail(d.id).day
        assertEquals(DayCompleteness.untracked, day.completeness)
        assertEquals(DayStatus.Skipped, dayStatus(listOf(day), db.head().activeDayID, hasSavedFood = false))
    }
}
