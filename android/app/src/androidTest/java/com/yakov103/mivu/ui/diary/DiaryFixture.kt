package com.yakov103.mivu.ui.diary

import android.content.Context
import com.yakov103.mivu.diary.DayCompleteness
import com.yakov103.mivu.diary.DiaryDatabase
import com.yakov103.mivu.diary.DiaryMeal
import com.yakov103.mivu.diary.DiaryRepository
import com.yakov103.mivu.diary.FoodItem
import com.yakov103.mivu.diary.GoalRecord
import com.yakov103.mivu.diary.MealPhoto
import com.yakov103.mivu.diary.MealSubmission
import com.yakov103.mivu.diary.MealTimePrecision
import com.yakov103.mivu.diary.NutritionProvenance
import com.yakov103.mivu.diary.NutritionValues
import com.yakov103.mivu.diary.PhotoRole
import com.yakov103.mivu.diary.SubmissionState
import com.yakov103.mivu.diary.TrackingDay
import com.yakov103.mivu.diary.WeightEntry
import com.yakov103.mivu.diary.WorkoutKind
import com.yakov103.mivu.diary.WorkoutSession
import com.yakov103.mivu.diary.startDay
import com.yakov103.mivu.ui.today.TodayFixture
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import java.util.UUID

/**
 * A synthetic diary week: today (active, two meals, weight, goal), yesterday (closed, a meal and a workout), two days ago
 * (skipped), three days ago (closed) and an earliest day sixteen days ago. Leaves no database open.
 */
object DiaryFixture {
    class Seeded(val profileID: UUID, val today: LocalDate, val todayMealID: UUID)

    fun seed(context: Context): Seeded {
        val id = TodayFixture.diary(context)
        val db = DiaryRepository(context).database(id)
        val zone = ZoneId.systemDefault()
        val active = db.startDay(Instant.now().truncatedTo(ChronoUnit.SECONDS), db.head().revision)
        val today = LocalDate.parse(active.localDate)
        fun at(date: LocalDate, h: Int, m: Int) = date.atTime(h, m).atZone(zone).toInstant()
        var todayMeal: UUID? = null
        db.transaction(db.head().revision) { tx ->
            fun day(date: LocalDate, completeness: DayCompleteness = DayCompleteness.unknown) =
                TrackingDay(UUID.randomUUID(), date.toString(), zone.id, at(date, 7, 0), completeness).also(tx::putDay)
            fun meal(day: TrackingDay, h: Int, m: Int, name: String, kcal: Double, p: Double, c: Double, f: Double, photo: Boolean = false): UUID {
                val date = LocalDate.parse(day.localDate)
                val photos = if (photo) listOf(MealPhoto(UUID.randomUUID(), TodayFixture.plateJpeg(), at(date, h, m), PhotoRole.unspecified)) else emptyList()
                val item = FoodItem(UUID.randomUUID(), name, 1.0, "serving", NutritionValues(kcal, c, p, f),
                    NutritionProvenance.user, "Entered manually", false, emptyMap())
                val meal = DiaryMeal(UUID.randomUUID(), day.id, at(date, h, m), at(date, h, m), 1, timePrecision = MealTimePrecision.exact,
                    items = listOf(item), photos = photos,
                    submissions = listOf(MealSubmission(UUID.randomUUID(), 0, name, photos.map { it.id }, false, SubmissionState.saved)))
                tx.putMeal(meal)
                return meal.id
            }
            tx.putGoal(GoalRecord(UUID.randomUUID(), "2026-01-01", zone.id, 1, NutritionValues(2100.0, 230.0, 120.0, 70.0), null, false))
            todayMeal = meal(active, 8, 5, "Greek yogurt with berries", 310.0, 18.0, 32.5, 9.1, photo = true)
            meal(active, 13, 20, "Chicken salad", 520.0, 41.0, 18.0, 30.0)
            tx.putWeight(WeightEntry(UUID.randomUUID(), active.id, at(today, 7, 0), 72.4, "kg"))
            val yesterday = day(today.minusDays(1))
            meal(yesterday, 9, 0, "Oat porridge", 380.0, 14.0, 58.0, 9.0)
            tx.putWorkout(WorkoutSession(UUID.randomUUID(), yesterday.id, at(today.minusDays(1), 18, 0), MealTimePrecision.exact, 1,
                WorkoutKind.strength, 45, emptyList()))
            day(today.minusDays(2), DayCompleteness.untracked)
            meal(day(today.minusDays(3)), 12, 30, "Lentil soup", 450.0, 24.0, 60.0, 8.0)
            meal(day(today.minusDays(16)), 12, 0, "Rice bowl", 600.0, 30.0, 80.0, 15.0)
        }
        db.close()
        return Seeded(id, today, todayMeal!!)
    }
}
