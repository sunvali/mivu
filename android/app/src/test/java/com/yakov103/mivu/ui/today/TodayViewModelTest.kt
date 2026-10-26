package com.yakov103.mivu.ui.today

import com.yakov103.mivu.diary.DayCompleteness
import com.yakov103.mivu.diary.DiaryMeal
import com.yakov103.mivu.diary.FoodItem
import com.yakov103.mivu.diary.GoalRecord
import com.yakov103.mivu.diary.MealSubmission
import com.yakov103.mivu.diary.NutritionProvenance
import com.yakov103.mivu.diary.NutritionValues
import com.yakov103.mivu.diary.SubmissionState
import com.yakov103.mivu.diary.TrackingDay
import com.yakov103.mivu.diary.WorkoutKind
import com.yakov103.mivu.diary.WorkoutSession
import com.yakov103.mivu.diary.MealTimePrecision
import java.time.Instant
import java.util.Locale
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class TodayViewModelTest {
    private fun id(n: Int) = UUID.fromString("00000000-0000-0000-0000-%012d".format(n))
    private val day = TrackingDay(id(100), "2026-10-24", "UTC", Instant.parse("2026-10-24T06:00:00Z"), DayCompleteness.unknown)

    private fun item(n: Int, kcal: Double?, protein: Double?, carbs: Double?, fat: Double?, provenance: NutritionProvenance = NutritionProvenance.user) =
        FoodItem(id(n), "item$n", 1.0, "serving", NutritionValues(kcal, carbs, protein, fat), provenance, "", false, emptyMap())

    private fun meal(n: Int, captured: String, vararg items: FoodItem, revision: Int = 1, submissions: List<MealSubmission> = emptyList()) =
        DiaryMeal(id(n), day.id, Instant.parse(captured), Instant.parse(captured), revision, items = items.toList(),
            photos = emptyList(), submissions = submissions)

    private fun goal(kcal: Double?, credit: Boolean = false) =
        GoalRecord(id(50), "2026-10-01", "UTC", 1, NutritionValues(kcal, null, null, null), null, credit)

    private fun state(
        day: TrackingDay? = this.day,
        meals: List<DiaryMeal> = emptyList(),
        goals: List<GoalRecord> = emptyList(),
        workouts: List<WorkoutSession> = emptyList(),
    ) = todayUiState(day, meals, goals, workouts, sampleMode = false, savedReceipt = null, Locale.US, "EEEE, MMMM d")

    @Test fun knownAndUnknownMacros() {
        val s = state(meals = listOf(
            meal(1, "2026-10-24T08:00:00Z", item(1, 1250.4, 30.6, 140.0, 20.0)),
            meal(2, "2026-10-24T12:00:00Z", item(2, 300.0, null, 40.0, 10.0)),
        ))
        assertEquals("Saturday, October 24", s.displayDate)
        assertTrue(s.hasDay)
        assertEquals("1,550", s.kcal)
        assertEquals("31 g", s.protein) // known protein adds up; the unknown one is disclosed by the note (iOS #64)
        assertEquals("180 g", s.carbs)
        assertEquals("30 g", s.fat)
        assertTrue(s.unknownNote)
        assertEquals(listOf(id(2), id(1)), s.meals.map { it.id }) // newest first
        assertNull(s.goal)
    }

    @Test fun goalBelowTarget() {
        val s = state(meals = listOf(meal(1, "2026-10-24T08:00:00Z", item(1, 1500.0, 10.0, 10.0, 10.0))), goals = listOf(goal(2000.0)))
        val g = s.goal!!
        assertEquals("2,000 kcal goal", g.target)
        assertEquals("500 to goal", g.remaining)
        assertEquals(0.75f, g.progress!!, 0.0001f)
        assertEquals("1,500 of 2,000 kilocalories", g.progressValue)
        assertNull(g.exerciseAdjusted)
        assertFalse(s.unknownNote)
    }

    @Test fun goalAboveTargetWithExerciseCredit() {
        val workout = WorkoutSession(id(60), day.id, day.startAt, MealTimePrecision.exact, 1, WorkoutKind.cardio, 30, emptyList(), 300.0)
        val s = state(meals = listOf(meal(1, "2026-10-24T08:00:00Z", item(1, 2200.0, 10.0, 10.0, 10.0))),
            goals = listOf(goal(2000.0, credit = true)), workouts = listOf(workout))
        val g = s.goal!!
        assertEquals("200 above goal", g.remaining)
        assertEquals(1f, g.progress!!, 0f)
        assertEquals("Exercise-adjusted remaining: 100 kcal", g.exerciseAdjusted)
    }

    @Test fun goalWithUnknownIntakeIsNotEstimated() {
        val s = state(meals = listOf(meal(1, "2026-10-24T08:00:00Z", item(1, null, 10.0, 10.0, 10.0))), goals = listOf(goal(2000.0)))
        assertNull(s.goal!!.remaining)
        assertNull(s.goal!!.progress)
    }

    @Test fun emptyDay() {
        val s = state(goals = listOf(goal(null)))
        assertTrue(s.hasDay)
        assertNull(s.kcal)
        assertNull(s.protein)
        assertFalse(s.unknownNote)
        assertTrue(s.meals.isEmpty())
        assertNull(s.goal) // no kcal target: nothing to measure against
    }

    @Test fun noActiveDay() {
        val s = state(day = null, goals = listOf(goal(2000.0)))
        assertEquals("Your waking day", s.displayDate)
        assertFalse(s.hasDay)
        assertNull(s.kcal)
        assertNull(s.goal)
    }

    @Test fun mealRowTitleAndStatus() {
        val pending = meal(3, "2026-10-24T08:00:00Z", revision = 0,
            submissions = listOf(MealSubmission(id(4), 0, "  synthetic toast  ", emptyList(), true, SubmissionState.awaitingReview)))
        assertEquals("synthetic toast", mealTitle(pending))
        assertEquals(SubmissionState.awaitingReview, pending.state)
        assertEquals("Apple (sample)", mealTitle(meal(5, "2026-10-24T08:00:00Z", item(6, 95.0, 0.5, 25.0, 0.3, NutritionProvenance.sample))))
        assertEquals("Meal", mealTitle(meal(7, "2026-10-24T08:00:00Z")))
    }
}
