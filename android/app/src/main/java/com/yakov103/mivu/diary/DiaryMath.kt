package com.yakov103.mivu.diary

import kotlinx.serialization.Serializable

// Ports of iOS nutritionTotals (DiaryModels.swift:360), dayNutritionTotals (DiaryReadModels.swift:167),
// ProgressAnalytics.daily(snapshot:) (ProgressAnalytics.swift:53,80) and DiarySnapshot.goal(on:) (DiaryModels.swift:272).

@Serializable
data class NutritionTotals(
    val kcal: Double?,
    val carbs: Double?,
    val protein: Double?,
    val fat: Double?,
    val unknownItemCount: Int,
)

data class DailyProgress(
    val foodTotals: NutritionTotals?,
    val goal: GoalRecord?,
    val remainingFromRecorded: NutritionValues,
    val exerciseAdjustedKcalRemaining: Double?,
)

/** Each nutrient adds the items that know it and is nil only when none do; unknownItemCount discloses the gap. */
private fun sumOrNull(values: List<Double?>): Double? = values.filterNotNull().takeIf { it.isNotEmpty() }?.sum()

fun nutritionTotals(items: List<FoodItem>) = NutritionTotals(
    sumOrNull(items.map { it.nutrition.kcal }),
    sumOrNull(items.map { it.nutrition.carbs }),
    sumOrNull(items.map { it.nutrition.protein }),
    sumOrNull(items.map { it.nutrition.fat }),
    items.count { with(it.nutrition) { kcal == null || carbs == null || protein == null || fat == null } },
)

private val DiaryMeal.isSaved get() = revision > 0
internal val DiaryMeal.hasUnresolvedInput
    get() = (!isSaved && submissions.isEmpty()) ||
        submissions.any { it.state != SubmissionState.saved && it.state != SubmissionState.cancelled }

fun dayNutritionTotals(meals: List<DiaryMeal>, complete: Boolean): NutritionTotals {
    val items = meals.filter { it.isSaved }.flatMap { it.items }
    if (items.isEmpty() && complete && meals.none { it.hasUnresolvedInput }) return NutritionTotals(0.0, 0.0, 0.0, 0.0, 0)
    return nutritionTotals(items)
}

fun goalOn(date: String, goals: List<GoalRecord>): GoalRecord? =
    goals.filter { it.effectiveLocalDate <= date }.maxByOrNull { it.effectiveLocalDate }

private fun remaining(target: Double?, recorded: Double?) = if (target == null || recorded == null) null else target - recorded

fun dailyProgress(
    snapshotDays: List<TrackingDay>,
    meals: List<DiaryMeal>,
    goals: List<GoalRecord>,
    workouts: List<WorkoutSession>,
    localDate: String,
): DailyProgress {
    val days = snapshotDays.filter { it.localDate == localDate }
    val dayIDs = days.map { it.id }.toSet()
    val subtotals = days.map { d ->
        dayNutritionTotals(meals.filter { it.dayID == d.id }, d.completeness == DayCompleteness.complete)
    }
    val dayWorkouts = workouts.filter { it.dayID in dayIDs }
    val burn = if (dayWorkouts.all { it.estimatedBurnKcal != null }) dayWorkouts.sumOf { it.estimatedBurnKcal!! } else null
    return dailyProgress(subtotals, goalOn(localDate, goals), burn)
}

/** The one sum behind Today, the Coach and Progress: a date's tracking-day [subtotals] against its [goal]. */
fun dailyProgress(subtotals: List<NutritionTotals>, goal: GoalRecord?, burn: Double?): DailyProgress {
    val totals = if (subtotals.isEmpty()) null else NutritionTotals(
        sumOrNull(subtotals.map { it.kcal }), sumOrNull(subtotals.map { it.carbs }),
        sumOrNull(subtotals.map { it.protein }), sumOrNull(subtotals.map { it.fat }),
        subtotals.sumOf { it.unknownItemCount },
    )
    val left = NutritionValues(
        remaining(goal?.targets?.kcal, totals?.kcal), remaining(goal?.targets?.carbs, totals?.carbs),
        remaining(goal?.targets?.protein, totals?.protein), remaining(goal?.targets?.fat, totals?.fat),
    )
    val adjusted = if (goal?.exerciseCreditEnabled == true) left.kcal?.let { k -> burn?.let { k + it } } else null
    return DailyProgress(totals, goal, left, adjusted)
}
