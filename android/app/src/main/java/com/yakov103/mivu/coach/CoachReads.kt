@file:UseSerializers(SwiftUUID::class)

package com.yakov103.mivu.coach

import com.yakov103.mivu.diary.COACH_TURN_NAMES_MEAL
import com.yakov103.mivu.diary.CoachMealCandidate
import com.yakov103.mivu.diary.DayCompleteness
import com.yakov103.mivu.diary.DayStatus
import com.yakov103.mivu.diary.DiaryDatabase
import com.yakov103.mivu.diary.DiaryError
import com.yakov103.mivu.diary.DiaryProfile
import com.yakov103.mivu.diary.FoodItem
import com.yakov103.mivu.diary.GoalRecord
import com.yakov103.mivu.diary.NutritionTotals
import com.yakov103.mivu.diary.NutritionValues
import com.yakov103.mivu.diary.SwiftJson
import com.yakov103.mivu.diary.SwiftUUID
import com.yakov103.mivu.diary.TrackingDay
import com.yakov103.mivu.diary.WeightEntry
import com.yakov103.mivu.diary.WorkoutSession
import com.yakov103.mivu.diary.dayNutritionTotals
import com.yakov103.mivu.diary.dayStatus
import com.yakov103.mivu.diary.diaryDateLabel
import com.yakov103.mivu.diary.effectiveGoal
import com.yakov103.mivu.diary.exactGoal
import com.yakov103.mivu.diary.swift
import com.yakov103.mivu.diary.trackingDay
import com.yakov103.mivu.diary.validLocalDate
import com.yakov103.mivu.diary.validateItems
import com.yakov103.mivu.diary.workout
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID
import kotlin.math.abs
import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.UseSerializers
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.JsonElement

// Ports of the Coach read handlers (ios/Mivu/Coach/CoachEngine.swift:136-165) and what they call: DiaryStore coachGoals,
// coachPreferences, coachWorkout (DiaryStore.swift:505-549), coachMeals/coachFindMeals/coachCandidate
// (DiaryDatabaseCoachContext.swift:70-125), progressRange (DiaryDatabaseProgressQueries.swift:35, Coach spans only) and
// ProgressAnalytics daily/period/weight/window (ProgressAnalytics.swift). Every read is bounded.

/** The tool output for a read [command] of [turnID], shaped like iOS. */
fun DiaryDatabase.executeCoachRead(turnID: UUID, command: CoachCommand): JsonElement =
    SwiftJson.parseToJsonElement(read { it.coachRead(turnID, command) })

/** iOS keeps a lookup failure as data so the model falls back to marked estimates; Android has no lookup service yet. */
const val COACH_LOOKUP_UNAVAILABLE = "{\"available\":false,\"reason\":\"Nutrition lookup unavailable. Use clearly uncertain estimates.\"}"

@Serializable data class CoachMealCandidatePage(val localDate: String, val meals: List<CoachMealCandidate>, val hasMore: Boolean, val nextAfterMealID: UUID? = null)
@Serializable data class CoachWeightReference(val localDate: String, val record: WeightEntry)
@Serializable data class CoachDailyProgress(
    val localDate: String,
    val status: DayStatus? = null,
    val foodTotals: NutritionTotals? = null,
    val goal: GoalRecord? = null,
    val remainingFromRecorded: NutritionValues,
    val workoutCount: Int,
    val estimatedBurnKcal: Double? = null,
    val exerciseAdjustedKcalRemaining: Double? = null,
)
@Serializable data class NutrientSampleCounts(val kcal: Int, val carbs: Int, val protein: Int, val fat: Int)
@Serializable data class PeriodProgress(
    val startLocalDate: String, val endLocalDate: String, val dayCount: Int, val closedDayCount: Int, val skippedDayCount: Int,
    val missingDayCount: Int, val knownIntakeSamples: NutrientSampleCounts, val averageIntake: NutritionValues,
    val adherenceNumerator: Int, val adherenceDenominator: Int, val workoutCount: Int,
)
@Serializable enum class PlateauReadiness { @SerialName("insufficientData") InsufficientData, @SerialName("stable") Stable, @SerialName("changing") Changing }
@Serializable data class WeightProgress(
    val endLocalDate: String, val currentSevenDayAverageKg: Double? = null, val currentSevenDayObservedCount: Int,
    val changeFromSevenDaysAgoKg: Double? = null, val changeFromThirtyDaysAgoKg: Double? = null, val plateau: PlateauReadiness,
)
@Serializable data class CoachProgress(
    val startLocalDate: String, val endLocalDate: String, val daily: CoachDailyProgress, val period: PeriodProgress? = null,
    val weight: WeightProgress, val weights: List<CoachWeightReference>, val workouts: List<WorkoutReference>,
    val omittedWeightCount: Int, val omittedWorkoutCount: Int, val truncated: Boolean,
)
@Serializable private data class Goals(val exact: GoalRecord? = null, val effective: GoalRecord? = null, val diaryRevision: Int)
@Serializable private data class Preferences(val profile: DiaryProfile, val diaryRevision: Int)

private fun DiaryDatabase.Tx.coachRead(turnID: UUID, command: CoachCommand): String = when (command) {
    is CoachCommand.Context -> coachJSON(CoachContext.serializer(), coachInferenceContext(turnID))
    is CoachCommand.Meal -> coachJSON(CoachContext.Meal.serializer(), coachMealDetail(command.id))
    is CoachCommand.Meals -> coachJSON(CoachMealCandidatePage.serializer(), coachMeals(command.date, command.afterMealID))
    is CoachCommand.FindMeals -> coachJSON(ListSerializer(CoachMealCandidate.serializer()), coachFindMeals(command.query, command.from, command.to))
    is CoachCommand.Progress -> coachJSON(CoachProgress.serializer(), coachProgress(command.endingOn, command.days))
    is CoachCommand.Workout -> workout(command.id).let {
        if (size(WorkoutSession.serializer(), it) > 48_000) throw CoachError.LimitExceeded
        coachJSON(WorkoutSession.serializer(), it)
    }
    is CoachCommand.Goals -> coachJSON(Goals.serializer(), Goals(exactGoal(command.date), effectiveGoal(command.date), head.revision.toInt()))
    is CoachCommand.Preferences -> coachJSON(Preferences.serializer(), Preferences(head.profile, head.revision.toInt()))
    is CoachCommand.Lookup -> COACH_LOOKUP_UNAVAILABLE
    is CoachCommand.Clarification, is CoachCommand.Write -> throw CoachError.InvalidArguments
}

private const val DAY_DATE = "json_extract(CAST(d.payload AS TEXT), '$.localDate')"

internal fun DiaryDatabase.Tx.coachMeals(date: String, afterMealID: UUID?): CoachMealCandidatePage {
    if (!validLocalDate(date)) throw DiaryError.InvalidData("date")
    afterMealID?.let { if (trackingDay(mealRow(it).dayID).localDate != date) throw DiaryError.InvalidData("cursor") }
    val ids = ids("SELECT m.id FROM day d JOIN meal m ON m.parent = d.id WHERE $DAY_DATE = ? AND m.id > ? ORDER BY m.id LIMIT 21",
        listOf(date, afterMealID?.swift ?: ""))
    val meals = ids.take(20).map { coachCandidate(it) }
    return CoachMealCandidatePage(date, meals, ids.size > 20, if (ids.size > 20) meals.last().id else null)
}

internal fun DiaryDatabase.Tx.coachFindMeals(query: String, from: String?, to: String?): List<CoachMealCandidate> {
    if (query.isEmpty() || query.codePointCount(0, query.length) > 100 || listOfNotNull(from, to).any { !validLocalDate(it) }) {
        throw DiaryError.InvalidData("find meals")
    }
    val pattern = "%" + query.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%"
    return ids("SELECT m.id FROM meal m JOIN day d ON m.parent = d.id WHERE EXISTS (SELECT 1 FROM item i WHERE i.parent = m.id AND " +
        "json_extract(CAST(i.payload AS TEXT), '$.name') LIKE ? ESCAPE '\\') AND $DAY_DATE >= ? AND $DAY_DATE <= ? " +
        "ORDER BY json_extract(CAST(m.payload AS TEXT), '$.eatenAt') DESC, m.ordinal DESC, m.id LIMIT 10",
        listOf(pattern, from ?: "0000-00-00", to ?: "9999-99-99")).map { coachCandidate(it) }
}

private fun DiaryDatabase.Tx.coachCandidate(id: UUID): CoachMealCandidate {
    val meal = mealRow(id)
    val day = trackingDay(meal.dayID)
    val itemCount = count("SELECT COUNT(*) FROM item WHERE parent = ?", listOf(id.swift))
    val preview = boundedRecords("item", FoodItem.serializer(), "parent = ?", listOf(id.swift), "ordinal", 4).also(::validateItems)
    val items = mutableListOf<CoachMealCandidate.Item>()
    for (item in preview) {
        val value = CoachMealCandidate.Item(item.id, coachBoundedText(item.name, 256), item.quantity, item.unit)
        if (size(ListSerializer(CoachMealCandidate.Item.serializer()), items + value) > 1200) break
        items += value
    }
    fun text(sql: String) = query(sql, listOf(id.swift)) { if (it.moveToFirst()) it.getString(0) ?: "" else "" }
    // shortcut: iOS falls back to the origin turn via record_source; Android finds the earliest turn naming the meal.
    val description = text("SELECT substr(json_extract(CAST(payload AS TEXT), '$.text'),1,513) FROM submission WHERE parent = ? ORDER BY ordinal, id LIMIT 1")
        .ifEmpty {
            text("SELECT substr(json_extract(CAST(t.payload AS TEXT), '$.text'),1,513) FROM coach_turn t WHERE $COACH_TURN_NAMES_MEAL ORDER BY t.ordinal LIMIT 1")
        }
    return CoachMealCandidate(id, day.id, day.localDate, day.timeZoneID, meal.revision, meal.eatenAt, meal.timePrecision, items,
        itemCount - items.size, coachBoundedText(description, 512), description.toByteArray().size > 512)
}

/** iOS `progressRange` for the Coach spans (1, 7 or 30 days): reports over a 37-day horizon for the weight trend. */
internal fun DiaryDatabase.Tx.coachProgress(endingOn: String, days: Int): CoachProgress {
    if (!validLocalDate(endingOn) || days !in setOf(1, 7, 30)) throw CoachError.InvalidArguments
    val zone = head.profile.timeZoneID
    val horizon = window(endingOn, maxOf(37, days), 0)
    val reports = mutableMapOf<String, CoachDailyProgress>()
    val savedFoodDates = mutableSetOf<String>()
    val weights = mutableListOf<Pair<Long, CoachWeightReference>>()
    var workouts = listOf<Pair<Long, WorkoutReference>>()
    var workoutCount = 0
    val first = horizon[horizon.size - days]
    for (label in horizon) {
        val tracked = boundedRecords("day", TrackingDay.serializer(), "json_extract(CAST(payload AS TEXT), '$.localDate') = ?", listOf(label), "ordinal", 10_000)
        val totals = mutableListOf<NutritionTotals>()
        var dailyWorkouts = 0
        var burn: Double? = 0.0
        for (day in tracked) {
            val meals = dayMeals(day.id)
            if (meals.any { it.revision > 0 }) savedFoodDates += label
            totals += dayNutritionTotals(meals, day.completeness == DayCompleteness.complete)
            weights += ordered("weight", day.id, WeightEntry.serializer()).map { (ordinal, w) -> ordinal to CoachWeightReference(label, w) }
            val sessions = ordered("workout", day.id, WorkoutSession.serializer())
            dailyWorkouts += sessions.size
            burn = if (sessions.any { it.second.estimatedBurnKcal == null }) null else burn?.plus(sessions.sumOf { it.second.estimatedBurnKcal!! })
            if (label >= first) {
                workoutCount += sessions.size
                workouts = (workouts + sessions.takeLast(100).map { (ordinal, w) ->
                    ordinal to WorkoutReference(w.id, day.id, label, w.revision, w.kind, w.durationMinutes)
                }).sortedBy { it.first }.takeLast(100)
            }
        }
        reports[label] = daily(label, tracked, totals, label in savedFoodDates, effectiveGoal(label), dailyWorkouts, burn)
    }
    // Legacy weights without a day count on their measured date in the profile zone.
    val start = LocalDate.parse(horizon[0]).atStartOfDay(ZoneId.of(zone, ZoneId.SHORT_IDS)).toInstant()
    val end = LocalDate.parse(endingOn).plusDays(1).atStartOfDay(ZoneId.of(zone, ZoneId.SHORT_IDS)).toInstant()
    val measured = "json_extract(CAST(payload AS TEXT), '$.measuredAt')"
    weights += query("SELECT ordinal, payload FROM weight WHERE parent IS NULL AND $measured >= CAST(? AS REAL) AND $measured < CAST(? AS REAL) LIMIT 10000",
        listOf(reference(start).toString(), reference(end).toString())) { c ->
        buildList { while (c.moveToNext()) add(c.getLong(0) to SwiftJson.decodeFromString(WeightEntry.serializer(), c.getBlob(1).decodeToString())) }
    }.map { (ordinal, w) -> ordinal to CoachWeightReference(diaryDateLabel(w.measuredAt, zone), w) }
    weights.sortBy { it.first }
    val latest = mutableMapOf<String, WeightEntry>()
    for ((_, ref) in weights) {
        val prior = latest[ref.localDate]
        if (prior != null && (prior.measuredAt > ref.record.measuredAt || (prior.measuredAt == ref.record.measuredAt && prior.revision >= ref.record.revision))) continue
        latest[ref.localDate] = ref.record
    }
    val labels = horizon.takeLast(days)
    val references = weights.map { it.second }.filter { it.localDate >= labels[0] }
    val complete = horizon.takeLast(28).mapNotNull { reports[it] }.count { it.status == DayStatus.Closed && it.foodTotals?.kcal != null }
    return CoachProgress(labels[0], endingOn, reports.getValue(endingOn),
        if (days == 1) null else period(endingOn, days, labels.mapNotNull { reports[it] }),
        weightProgress(endingOn, latest, complete), references.takeLast(40), workouts.map { it.second },
        maxOf(0, references.size - 40), maxOf(0, workoutCount - 100), references.size > 40 || workoutCount > 100)
}

private fun <T> DiaryDatabase.Tx.ordered(table: String, dayID: UUID, serializer: KSerializer<T>): List<Pair<Long, T>> =
    query("SELECT ordinal, payload FROM $table WHERE parent = ? ORDER BY ordinal LIMIT 10000", listOf(dayID.swift)) { c ->
        buildList { while (c.moveToNext()) add(c.getLong(0) to SwiftJson.decodeFromString(serializer, c.getBlob(1).decodeToString())) }
    }

/** Seconds since 2001-01-01, as Swift stores dates. */
private fun reference(at: Instant) = (at.epochSecond - 978_307_200L) + at.nano / 1e9

/** iOS `ProgressAnalytics.window`: [days] dates ending [offset] days before [endingOn]. */
private fun window(endingOn: String, days: Int, offset: Int): List<String> {
    val end = LocalDate.parse(endingOn).minusDays(offset.toLong())
    return (days - 1 downTo 0).map { end.minusDays(it.toLong()).toString() }
}

private fun sum(values: List<Double?>): Double? = if (values.isEmpty() || values.any { it == null }) null else values.sumOf { it!! }
private fun remaining(target: Double?, recorded: Double?) = if (target == null || recorded == null) null else target - recorded

private fun DiaryDatabase.Tx.daily(
    date: String, days: List<TrackingDay>, subtotals: List<NutritionTotals>, hasFood: Boolean, goal: GoalRecord?, workouts: Int, burn: Double?,
): CoachDailyProgress {
    val totals = if (subtotals.isEmpty()) null else NutritionTotals(sum(subtotals.map { it.kcal }), sum(subtotals.map { it.carbs }),
        sum(subtotals.map { it.protein }), sum(subtotals.map { it.fat }), subtotals.sumOf { it.unknownItemCount })
    val left = NutritionValues(remaining(goal?.targets?.kcal, totals?.kcal), remaining(goal?.targets?.carbs, totals?.carbs),
        remaining(goal?.targets?.protein, totals?.protein), remaining(goal?.targets?.fat, totals?.fat))
    val adjusted = if (goal?.exerciseCreditEnabled == true) left.kcal?.let { k -> burn?.let { k + it } } else null
    return CoachDailyProgress(date, dayStatus(days, head.activeDayID, hasFood), totals, goal, left, workouts, burn, adjusted)
}

private fun period(endingOn: String, days: Int, reports: List<CoachDailyProgress>): PeriodProgress {
    val eligible = reports.filter { it.status == DayStatus.Closed }
    fun average(field: (NutritionTotals) -> Double?): Pair<Double?, Int> {
        val values = eligible.mapNotNull { r -> r.foodTotals?.let(field) }
        return (if (values.isEmpty()) null else values.sum() / values.size) to values.size
    }
    val kcal = average { it.kcal }; val carbs = average { it.carbs }; val protein = average { it.protein }; val fat = average { it.fat }
    // A target is a range for reporting: a very low intake is not called adherence.
    val adherence = eligible.mapNotNull { r ->
        val intake = r.foodTotals?.kcal; val target = r.goal?.targets?.kcal
        if (intake == null || target == null) null else intake >= target * 0.9 && intake <= target * 1.1
    }
    return PeriodProgress(reports.firstOrNull()?.localDate ?: endingOn, endingOn, days, eligible.size,
        reports.count { it.status == DayStatus.Skipped }, reports.count { it.status == null },
        NutrientSampleCounts(kcal.second, carbs.second, protein.second, fat.second),
        NutritionValues(kcal.first, carbs.first, protein.first, fat.first), adherence.count { it }, adherence.size, reports.sumOf { it.workoutCount })
}

private fun weightProgress(endingOn: String, latest: Map<String, WeightEntry>, completeKcalDays: Int): WeightProgress {
    fun summary(offset: Int): Pair<Double?, Int> {
        val kilograms = window(endingOn, 7, offset).mapNotNull { latest[it] }.map { if (it.unit == "lb") it.value * 0.45359237 else it.value }
        return (if (kilograms.isEmpty()) null else kilograms.sum() / kilograms.size) to kilograms.size
    }
    val current = summary(0); val priorWeek = summary(7); val priorMonth = summary(30); val plateauWeek = summary(21)
    val plateau = if (current.second < 3 || plateauWeek.second < 3 || completeKcalDays < 14) PlateauReadiness.InsufficientData
    else if (abs(current.first!! - plateauWeek.first!!) <= 0.25) PlateauReadiness.Stable else PlateauReadiness.Changing
    fun change(prior: Pair<Double?, Int>) = if (current.second >= 3 && prior.second >= 3) current.first!! - prior.first!! else null
    return WeightProgress(endingOn, current.first, current.second, change(priorWeek), change(priorMonth), plateau)
}
