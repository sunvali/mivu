package com.yakov103.mivu.diary

import java.time.Instant
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class DiaryMathTest {
    private fun id(n: Int) = UUID.fromString("00000000-0000-0000-0000-%012d".format(n))
    private val at = Instant.parse("2026-01-01T12:00:00Z")

    private fun item(n: Int, kcal: Double?, carbs: Double?, protein: Double?, fat: Double?) = FoodItem(
        id(n), "item$n", 1.0, "g", NutritionValues(kcal, carbs, protein, fat),
        NutritionProvenance.user, "ref", false, emptyMap(),
    )

    private fun meal(n: Int, dayID: UUID, revision: Int, vararg items: FoodItem) =
        DiaryMeal(id(n), dayID, at, at, revision, items = items.toList(), photos = emptyList(), submissions = emptyList())

    private fun day(n: Int, date: String, completeness: DayCompleteness = DayCompleteness.unknown) =
        TrackingDay(id(n), date, "UTC", at, completeness)

    private fun goal(n: Int, date: String, kcal: Double?, credit: Boolean = false) = GoalRecord(
        id(n), date, "UTC", 1, NutritionValues(kcal, 200.0, 100.0, 70.0), null, credit,
    )

    private fun workout(n: Int, dayID: UUID, burn: Double?) = WorkoutSession(
        id(n), dayID, at, MealTimePrecision.exact, 1, WorkoutKind.cardio, 30, emptyList(), burn,
    )

    @Test fun allKnownSums() {
        val t = nutritionTotals(listOf(item(1, 100.0, 10.0, 5.0, 2.0), item(2, 250.0, 30.0, 15.0, 8.0)))
        assertEquals(NutritionTotals(350.0, 40.0, 20.0, 10.0, 0), t)
    }

    @Test fun unknownComponentsAddNothingAndAreCounted() {
        val a = item(1, 10.0, 1.0, null, 0.0)
        val t = nutritionTotals(listOf(a, item(2, 20.0, 2.0, 3.0, 4.0)))
        assertEquals(30.0, t.kcal!!, 0.0)
        assertEquals(3.0, t.protein!!, 0.0)
        assertEquals(1, t.unknownItemCount)
        assertNull(nutritionTotals(listOf(a)).protein)
        assertNull(nutritionTotals(emptyList()).kcal)
    }

    @Test fun dailyAddsKnownSubtotals() {
        val p = dailyProgress(
            listOf(NutritionTotals(100.0, 10.0, 5.0, 2.0, 1), NutritionTotals(50.0, 5.0, null, 1.0, 2)), null, null,
        )
        assertEquals(5.0, p.foodTotals!!.protein!!, 0.0)
        assertEquals(3, p.foodTotals!!.unknownItemCount)
    }

    @Test fun unsavedMealsExcluded() {
        val d = id(9)
        val meals = listOf(
            meal(1, d, 1, item(1, 100.0, 10.0, 5.0, 2.0)),
            meal(2, d, 0, item(2, 900.0, 90.0, 50.0, 20.0)),
        )
        assertEquals(NutritionTotals(100.0, 10.0, 5.0, 2.0, 0), dayNutritionTotals(meals, complete = false))
    }

    @Test fun emptyCompleteDayIsZero() {
        assertEquals(NutritionTotals(0.0, 0.0, 0.0, 0.0, 0), dayNutritionTotals(emptyList(), complete = true))
        assertNull(dayNutritionTotals(emptyList(), complete = false).kcal)
    }

    @Test fun remainingIsTargetMinusRecorded() {
        val d = day(9, "2026-01-02")
        val p = dailyProgress(
            listOf(d), listOf(meal(1, d.id, 1, item(1, 600.0, 50.0, 40.0, 20.0))),
            listOf(goal(1, "2026-01-01", 2000.0)), emptyList(), "2026-01-02",
        )
        assertEquals(NutritionValues(1400.0, 150.0, 60.0, 50.0), p.remainingFromRecorded)
        assertEquals(600.0, p.foodTotals!!.kcal!!, 0.0)
        assertNull(p.exerciseAdjustedKcalRemaining)
    }

    @Test fun aboveGoalIsNegativeRemaining() {
        val d = day(9, "2026-01-02")
        val p = dailyProgress(
            listOf(d), listOf(meal(1, d.id, 1, item(1, 2300.0, 50.0, 40.0, 20.0))),
            listOf(goal(1, "2026-01-01", 2000.0)), emptyList(), "2026-01-02",
        )
        assertEquals(-300.0, p.remainingFromRecorded.kcal!!, 0.0)
    }

    @Test fun exerciseCreditAddsWorkoutBurnOnlyWhenEnabled() {
        val d = day(9, "2026-01-02")
        val meals = listOf(meal(1, d.id, 1, item(1, 600.0, 50.0, 40.0, 20.0)))
        val w = listOf(workout(1, d.id, 200.0), workout(2, d.id, 100.0))
        val on = dailyProgress(listOf(d), meals, listOf(goal(1, "2026-01-01", 2000.0, true)), w, "2026-01-02")
        val off = dailyProgress(listOf(d), meals, listOf(goal(1, "2026-01-01", 2000.0, false)), w, "2026-01-02")
        assertEquals(1700.0, on.exerciseAdjustedKcalRemaining!!, 0.0)
        assertNull(off.exerciseAdjustedKcalRemaining)
        val unknownBurn = dailyProgress(
            listOf(d), meals, listOf(goal(1, "2026-01-01", 2000.0, true)), w + workout(3, d.id, null), "2026-01-02",
        )
        assertNull(unknownBurn.exerciseAdjustedKcalRemaining)
    }

    @Test fun goalOnPicksLatestEffectiveOnOrBefore() {
        val goals = listOf(goal(1, "2026-01-01", 1.0), goal(3, "2026-03-01", 3.0), goal(2, "2026-02-01", 2.0))
        assertEquals(id(2), goalOn("2026-02-15", goals)!!.id)
        assertEquals(id(2), goalOn("2026-02-01", goals)!!.id)
        assertNull(goalOn("2025-12-31", goals))
    }
}
