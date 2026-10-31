package com.yakov103.mivu.diary

import java.time.LocalDate
import java.time.temporal.ChronoUnit
import java.util.UUID
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

// Ports of iOS diaryWeek (DiaryDatabaseScreenQueries.swift:43), daySummary (DiaryDatabaseMealMutations.swift:238),
// dayProjection (:224), setCompleteness (:133) and ProgressAnalytics.status (ProgressAnalytics.swift:70).
// Meals are read without photo bytes.

@Serializable enum class DayStatus { @SerialName("open") Open, @SerialName("closed") Closed, @SerialName("skipped") Skipped }

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
fun DiaryDatabase.diaryWeek(from: String, through: String): List<DiaryDaySummary> = read { it.diaryWeek(from, through) }

fun DiaryDatabase.Tx.diaryWeek(from: String, through: String): List<DiaryDaySummary> {
    val dates = try {
        val span = ChronoUnit.DAYS.between(LocalDate.parse(from), LocalDate.parse(through))
        if (span !in 0..6) throw DiaryError.InvalidData("week")
        (0..span).map { LocalDate.parse(from).plusDays(it).toString() }
    } catch (_: java.time.DateTimeException) { throw DiaryError.InvalidData("week") }
    val all = days()
    return dates.map { date -> daySummary(date, all.filter { it.localDate == date }) }
}

private fun DiaryDatabase.Tx.daySummary(date: String, days: List<TrackingDay>): DiaryDaySummary {
    val meals = days.flatMap { dayMeals(it.id) }
    val totals = dailyProgress(days, meals, emptyList(), emptyList(), date).foodTotals ?: nutritionTotals(emptyList())
    return DiaryDaySummary(days.firstOrNull(), date, meals.size, meals.count { it.revision > 0 }, meals.count { it.hasUnresolvedInput }, totals)
}

/** iOS `DiaryViewModel.MorningRecap`: the last recorded day before the active one and that day's kcal goal. */
data class MorningRecap(val previous: DiaryDaySummary, val targetKcal: Double?)

/** The morning check-in's recap for [activeDayID]; null on a diary's first day. */
fun DiaryDatabase.morningRecap(activeDayID: UUID): MorningRecap? = read { it.morningRecap(activeDayID) }

fun DiaryDatabase.Tx.morningRecap(activeDayID: UUID): MorningRecap? {
    val active = day(activeDayID) ?: return null
    val localDate = "json_extract(CAST(payload AS TEXT), '$.localDate')"
    val date = boundedRecords("day", TrackingDay.serializer(), "$localDate < ?", listOf(active.localDate), "$localDate DESC", 1)
        .firstOrNull()?.localDate ?: return null
    // Several days can share a date (zone changes); a date has at most a handful.
    val days = boundedRecords("day", TrackingDay.serializer(), "$localDate = ?", listOf(date), "ordinal", 16)
    return MorningRecap(daySummary(date, days), effectiveGoal(date)?.targets?.kcal)
}

fun DiaryDatabase.dayDetail(dayID: UUID): DayDetail = read { it.dayDetail(dayID) }

fun DiaryDatabase.Tx.dayDetail(dayID: UUID): DayDetail {
    val day = trackingDay(dayID)
    return DayDetail(day, dayMeals(dayID).sortedBy { it.eatenAt }, dayWorkouts(dayID), dayWeight(dayID), goalOn(day.localDate, goals()))
}

fun DiaryDatabase.earliestRecordDate(): String? = read { it.earliestRecordDate() }

fun DiaryDatabase.Tx.earliestRecordDate(): String? = days().minOfOrNull { it.localDate }

fun DiaryDatabase.setCompleteness(dayID: UUID, completeness: DayCompleteness, expectedRevision: Long) {
    transaction(expectedRevision) { tx -> tx.putDay(tx.trackingDay(dayID).copy(completeness = completeness)) }
}
