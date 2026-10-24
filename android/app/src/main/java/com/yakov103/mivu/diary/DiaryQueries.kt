package com.yakov103.mivu.diary

import java.time.LocalDate
import java.time.temporal.ChronoUnit
import java.util.UUID

// Ports of iOS diaryWeek (DiaryDatabaseScreenQueries.swift:43), daySummary (DiaryDatabaseMealMutations.swift:238),
// dayProjection (:224), setCompleteness (:133) and ProgressAnalytics.status (ProgressAnalytics.swift:70).
// Meals are read without photo bytes.

enum class DayStatus { Open, Closed, Skipped }

/** One date of a week; [day] is null when nothing was recorded. Several days sharing a date (zones) are combined. */
data class DiaryDaySummary(
    val day: TrackingDay?,
    val localDate: String,
    val mealCount: Int,
    val savedMealCount: Int,
    val pendingMealCount: Int,
    val totals: NutritionTotals,
)

data class DayDetail(
    val day: TrackingDay,
    val meals: List<DiaryMeal>,
    val workouts: List<WorkoutSession>,
    val weight: WeightEntry?,
    val goal: GoalRecord?,
)

/** Null when there are no days (iOS returns nil), so callers can tell "nothing recorded" from "skipped". */
fun dayStatus(days: List<TrackingDay>, activeDayID: UUID?, hasSavedFood: Boolean): DayStatus? = when {
    days.isEmpty() -> null
    days.all { it.completeness == DayCompleteness.untracked } -> DayStatus.Skipped // other stored values read as closed
    days.any { it.id == activeDayID } -> DayStatus.Open
    hasSavedFood -> DayStatus.Closed
    else -> DayStatus.Skipped
}

/** Every date from [from] through [through] (at most seven), as iOS rejects longer spans. */
fun DiaryDatabase.diaryWeek(from: String, through: String): List<DiaryDaySummary> {
    val dates = try {
        val span = ChronoUnit.DAYS.between(LocalDate.parse(from), LocalDate.parse(through))
        if (span !in 0..6) throw DiaryError.InvalidData("week")
        (0..span).map { LocalDate.parse(from).plusDays(it).toString() }
    } catch (_: java.time.DateTimeException) { throw DiaryError.InvalidData("week") }
    return read { tx ->
        val all = tx.days()
        dates.map { date ->
            val days = all.filter { it.localDate == date }
            val meals = days.flatMap { tx.dayMeals(it.id) }
            val totals = dailyProgress(days, meals, emptyList(), emptyList(), date).foodTotals ?: nutritionTotals(emptyList())
            DiaryDaySummary(days.firstOrNull(), date, meals.size, meals.count { it.revision > 0 },
                meals.count { it.hasUnresolvedInput }, totals)
        }
    }
}

fun DiaryDatabase.dayDetail(dayID: UUID): DayDetail = read { tx ->
    val day = tx.trackingDay(dayID)
    DayDetail(day, tx.dayMeals(dayID).sortedBy { it.eatenAt }, tx.dayWorkouts(dayID), tx.dayWeight(dayID), goalOn(day.localDate, tx.goals()))
}

fun DiaryDatabase.earliestRecordDate(): String? = read { tx -> tx.days().minOfOrNull { it.localDate } }

fun DiaryDatabase.setCompleteness(dayID: UUID, completeness: DayCompleteness, expectedRevision: Long) {
    transaction(expectedRevision) { tx -> tx.putDay(tx.trackingDay(dayID).copy(completeness = completeness)) }
}
