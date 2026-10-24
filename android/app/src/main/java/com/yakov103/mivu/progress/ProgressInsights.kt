package com.yakov103.mivu.progress

import com.yakov103.mivu.coach.CoachDailyProgress
import com.yakov103.mivu.coach.CoachProgress
import com.yakov103.mivu.coach.CoachWeightReference
import com.yakov103.mivu.diary.DayStatus
import com.yakov103.mivu.diary.GoalRecord
import com.yakov103.mivu.diary.NutritionTotals
import com.yakov103.mivu.diary.NutritionValues
import java.text.NumberFormat
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.time.temporal.TemporalAdjusters
import java.util.Locale
import kotlin.math.abs
import kotlin.math.pow

// Port of ios/Mivu/Progress/ProgressInsights.swift and ProgressSnapshot (ProgressCards.swift:5). Pure Kotlin: colors and
// symbols stay with the UI. Dates are local-date labels, so buckets and rows need no zone; weeks start on Monday.

/** How far a day's energy landed from that day's own target; over and under share a band. */
enum class ProgressBand(val title: String) {
    Near("Near"), BitOff("A bit off"), Off("Off"), FarOff("Far off");

    companion object {
        fun of(kcal: Double?, target: Double?): ProgressBand? {
            if (kcal == null || target == null || target <= 0) return null
            // Multiply before dividing so the 10/20/35% edges stay exact.
            val percent = abs(kcal - target) * 100 / target
            return if (percent <= 10) Near else if (percent <= 20) BitOff else if (percent <= 35) Off else FarOff
        }
    }
}

enum class ProgressRange(val days: Int, val title: String) { Week(7, "Week"), Month(30, "Month"), Quarter(91, "3M"), Year(365, "Year") }

/** One bar of a range chart: a day for Week and Month, a Monday week for 3M, a month for Year. */
data class ProgressBucket(
    val start: LocalDate,
    val averageKcal: Double?,
    val averageTarget: Double?,
    val band: ProgressBand?,
    val loggedDays: Int,
    /** False when the value comes only from partial or pending days: drawn lighter, never banded. */
    val complete: Boolean = true,
)

sealed interface ProgressCalendarDot {
    object Outside : ProgressCalendarDot
    object NoLog : ProgressCalendarDot
    data class Logged(val band: ProgressBand?) : ProgressCalendarDot
}

/** A calendar line: a Monday week of seven dots (Week, Month) or a month's logged share (3M, Year). */
data class ProgressCalendarRow(val title: String, val dots: List<ProgressCalendarDot>?, val logged: Int, val total: Int)

/** One weigh-in in kilograms with its smoothed trend. */
data class TrendPoint(val localDate: String, val raw: Double, val trend: Double)

object WeightTrend {
    /** Exponential moving average weighted by elapsed days, so a gap of weeks moves the trend further than one day does. */
    fun points(weights: List<CoachWeightReference>): List<TrendPoint> {
        val result = mutableListOf<TrendPoint>()
        for (reference in weights.sortedBy { it.localDate }) {
            val kg = if (reference.record.unit == "lb") reference.record.value * 0.45359237 else reference.record.value
            val previous = result.lastOrNull()
            if (previous == null) { result += TrendPoint(reference.localDate, kg, kg); continue }
            val alpha = 1 - 0.9.pow(ProgressInsights.days(previous.localDate, reference.localDate))
            result += TrendPoint(reference.localDate, kg, previous.trend + (kg - previous.trend) * alpha)
        }
        return result
    }
}

sealed class ProgressHeadline(val title: String, val celebrates: Boolean = false) {
    object OnTrack : ProgressHeadline("You're on track", true)
    object HoldingSteady : ProgressHeadline("Holding steady")
    object Drifting : ProgressHeadline("A new chance this week")
    object AtGoal : ProgressHeadline("You're at your goal", true)
    data class CaloriesOnTrack(val near: Int, val logged: Int) : ProgressHeadline("You're on track", true)
    data class CaloriesOff(val near: Int, val logged: Int) : ProgressHeadline("Fresh start ahead")
    object NotEnoughData : ProgressHeadline("Let's get started")
}

/** [band] is the half-width of the uncertainty band in kcal. */
data class BurnEstimate(val kcalPerDay: Double, val band: Double)

sealed interface BurnProgress {
    data class Estimate(val estimate: BurnEstimate) : BurnProgress
    data class Needs(val days: Int, val weighIns: Int) : BurnProgress
}

/** [symbol] is the iOS SF Symbol name; the UI maps it and [id] to its own icon and color. */
data class ProgressWin(val id: String, val title: String, val detail: String, val symbol: String)

object ProgressInsights {
    /** Only a complete day with nothing still being analyzed is judged against its target. */
    fun band(day: CoachDailyProgress): ProgressBand? =
        if (day.status != DayStatus.Closed) null else ProgressBand.of(day.foodTotals?.kcal, day.goal?.targets?.kcal)

    /** Energy balance: average intake on complete days minus the energy the trend change stored or released (~7,700 kcal per kg). */
    fun burn(days: List<CoachDailyProgress>, trend: List<TrendPoint>): BurnProgress {
        val intake = days.filter { it.status == DayStatus.Closed }.mapNotNull { it.foodTotals?.kcal }
        val span = if (trend.size >= 2) days(trend.first().localDate, trend.last().localDate) else 0
        val daysNeeded = maxOf(0, 14 - intake.size, 14 - span)
        val weighInsNeeded = maxOf(0, 4 - trend.size)
        val slope = slopePerDay(trend)
        if (daysNeeded != 0 || weighInsNeeded != 0 || slope == null) return BurnProgress.Needs(daysNeeded, weighInsNeeded)
        val kcalPerDay = intake.average() - slope * 7_700
        return BurnProgress.Estimate(BurnEstimate(kcalPerDay, 100 + 300 * maxOf(0, 30 - intake.size).toDouble() / 16))
    }

    /** At most three, most notable first; never a lost streak. */
    fun wins(days: List<CoachDailyProgress>, weighIns: Int, today: String? = null): List<ProgressWin> {
        var run = 0
        for (day in days.sortedByDescending { it.localDate }) {
            // Today is still in progress: it can extend a streak but never break one.
            if (day.localDate == today && (day.foodTotals?.protein ?: 0.0) < (day.goal?.targets?.protein ?: Double.POSITIVE_INFINITY)) continue
            val protein = day.foodTotals?.protein; val target = day.goal?.targets?.protein
            if (protein == null || target == null || protein < target) break
            run += 1
        }
        val logged = days.count { it.status != null && it.foodTotals?.kcal != null }
        return buildList {
            if (run >= 3) add(ProgressWin("protein-run", "Protein goal $run days running", "Keep it going", "bolt.fill"))
            if (logged >= 5) add(ProgressWin("logged-days", "$logged days logged", "Every one counts", "checkmark"))
            if (weighIns >= 3) add(ProgressWin("weigh-ins", "$weighIns weigh-ins", "Your trend keeps sharpening", "scalemass.fill"))
        }
    }

    private fun weekStart(date: LocalDate) = date.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))

    /** Days grouped, in date order, by the start each one maps to; unparseable labels are skipped. */
    private fun group(days: List<CoachDailyProgress>, start: (LocalDate) -> LocalDate): Map<LocalDate, List<Pair<LocalDate, CoachDailyProgress>>> =
        days.sortedBy { it.localDate }.mapNotNull { d -> runCatching { LocalDate.parse(d.localDate) }.getOrNull()?.let { it to d } }
            .groupBy { start(it.first) }

    /** Missing days stay out of every average; a bucket with no logged day has no value at all. */
    fun buckets(days: List<CoachDailyProgress>, range: ProgressRange): List<ProgressBucket> {
        val start: (LocalDate) -> LocalDate = when (range) {
            ProgressRange.Week, ProgressRange.Month -> { d -> d }
            ProgressRange.Quarter -> ::weekStart
            ProgressRange.Year -> { d -> d.withDayOfMonth(1) }
        }
        return group(days, start).map { (start, members) ->
            val logged = members.map { it.second }.filter { it.foodTotals?.kcal != null && it.status != null }
            val judged = logged.filter { it.status == DayStatus.Closed }
            val source = judged.ifEmpty { logged }
            val kcal = source.mapNotNull { it.foodTotals?.kcal }
            val targets = source.mapNotNull { it.goal?.targets?.kcal }
            val average = if (kcal.isEmpty()) null else kcal.average()
            val target = if (targets.isEmpty()) null else targets.average()
            ProgressBucket(start, average, target, if (judged.isEmpty()) null else ProgressBand.of(average, target), logged.size, judged.isNotEmpty())
        }
    }

    private fun whole(value: Double): String = NumberFormat.getNumberInstance(Locale.US).apply { maximumFractionDigits = 0 }.format(value)

    /** "2,420 kcal · 320 over": the day's energy against its own target, in words. */
    fun plainResult(day: CoachDailyProgress): String {
        val kcal = day.foodTotals?.kcal
        if (day.status == null || kcal == null) return "No log"
        val energy = whole(kcal) + " kcal"
        val target = day.goal?.targets?.kcal
        val band = band(day)
        if (target == null || band == null) return energy
        if (band == ProgressBand.Near) return "$energy · on target"
        return "$energy · ${whole(abs(kcal - target))} ${if (kcal > target) "over" else "under"}"
    }

    /** "400 over", or "on target" within 10%. */
    fun plainGap(value: Double, goal: Double): String {
        if (abs(value - goal) <= goal * 0.1) return "on target"
        return "${whole(abs(value - goal))} ${if (value > goal) "over" else "under"}"
    }

    fun plainMacro(grams: Double?, goal: Double?): String {
        if (grams == null) return "No complete days"
        val amount = "${whole(grams)} g a day"
        if (goal == null || goal <= 0) return amount
        if (abs(grams - goal) <= goal * 0.1) return "$amount · on goal"
        return "$amount · ${whole(abs(grams - goal))} g ${if (grams > goal) "over" else "under"} goal"
    }

    private fun format(date: LocalDate, pattern: String) = date.format(DateTimeFormatter.ofPattern(pattern, Locale.US))

    /** Newest first. Week and Month show Monday weeks as dots; 3M and Year show months as counts. */
    fun calendarRows(days: List<CoachDailyProgress>, range: ProgressRange): List<ProgressCalendarRow> {
        val byWeek = range == ProgressRange.Week || range == ProgressRange.Month
        fun dot(day: CoachDailyProgress) =
            if (day.status == null || day.foodTotals?.kcal == null) ProgressCalendarDot.NoLog else ProgressCalendarDot.Logged(band(day))
        return group(days, if (byWeek) ::weekStart else { d -> d.withDayOfMonth(1) }).entries.reversed().map { (start, members) ->
            val logged = members.count { dot(it.second) is ProgressCalendarDot.Logged }
            if (!byWeek) return@map ProgressCalendarRow(format(start, "MMMM yyyy"), null, logged, members.size)
            val dots = (0L until 7L).map { offset ->
                members.firstOrNull { it.first == start.plusDays(offset) }?.let { dot(it.second) } ?: ProgressCalendarDot.Outside
            }
            val end = start.plusDays(6)
            val title = format(start, "MMM d") + " – " + format(end, if (start.month == end.month && start.year == end.year) "d" else "MMM d")
            ProgressCalendarRow(title, dots, logged, members.size)
        }
    }

    /** Least-squares kg per day through the raw weigh-ins; the smoothed trend lags about nine days, so it only draws the line. */
    fun slopePerDay(points: List<TrendPoint>): Double? {
        val first = points.firstOrNull() ?: return null
        if (points.size < 2) return null
        val xs = points.map { days(first.localDate, it.localDate).toDouble() }
        val ys = points.map { it.raw }
        val meanX = xs.average(); val meanY = ys.average()
        val spread = xs.sumOf { (it - meanX) * (it - meanX) }
        if (spread <= 0) return null
        return xs.indices.sumOf { (xs[it] - meanX) * (ys[it] - meanY) } / spread
    }

    fun days(from: String, to: String): Int = runCatching { ChronoUnit.DAYS.between(LocalDate.parse(from), LocalDate.parse(to)).toInt() }.getOrDefault(0)

    /** Weight trend first (needs a goal weight and 3 weigh-ins over 7 days); otherwise most logged days near the calorie target. */
    fun headline(trend: List<TrendPoint>, goalWeightKg: Double?, startKg: Double?, days: List<CoachDailyProgress>): ProgressHeadline {
        if (goalWeightKg != null && trend.size >= 3 && days(trend.first().localDate, trend.last().localDate) >= 7) {
            val first = trend.first(); val last = trend.last()
            if (abs(last.trend - goalWeightKg) <= 1) return ProgressHeadline.AtGoal
            val direction = if (goalWeightKg < (startKg ?: first.trend)) -1.0 else 1.0
            val towardPerWeek = (slopePerDay(trend) ?: 0.0) * direction * 7
            return if (towardPerWeek >= 0.1) ProgressHeadline.OnTrack else if (towardPerWeek <= -0.1) ProgressHeadline.Drifting else ProgressHeadline.HoldingSteady
        }
        val bands = days.mapNotNull(::band)
        if (bands.isEmpty()) return ProgressHeadline.NotEnoughData
        val near = bands.count { it == ProgressBand.Near }
        return if (near * 2 > bands.size) ProgressHeadline.CaloriesOnTrack(near, bands.size) else ProgressHeadline.CaloriesOff(near, bands.size)
    }
}

fun kcal(value: Double): String = NumberFormat.getNumberInstance(Locale.US).apply { maximumFractionDigits = 0 }.format(value) + " kcal"

/** Everything the Progress cards draw, derived once per load from [CoachProgress]. */
class ProgressSnapshot(progress: CoachProgress, val range: ProgressRange, val zone: String, today: String) {
    /** The whole load (at least 30 days) behind burn and the weight verdict. */
    val loadedDays: List<CoachDailyProgress> = progress.dailyReports.orEmpty()
    val days: List<CoachDailyProgress> = loadedDays.takeLast(range.days)
    val buckets: List<ProgressBucket> = ProgressInsights.buckets(days, range)
    val loadedTrend: List<TrendPoint> = WeightTrend.points(progress.displayWeights.orEmpty())
    val trend: List<TrendPoint> = (days.firstOrNull()?.localDate ?: "").let { start -> loadedTrend.filter { it.localDate >= start } }
    val goal: GoalRecord? = loadedDays.lastOrNull { it.goal != null }?.goal
    // shortcut: the start is the first trend point in the loaded window on or after the goal date, not the first ever weigh-in.
    val startKg: Double? = (loadedTrend.firstOrNull { it.localDate >= (goal?.effectiveLocalDate ?: "") } ?: loadedTrend.firstOrNull())?.trend
    val headline: ProgressHeadline = ProgressInsights.headline(loadedTrend, goal?.goalWeightKg, startKg, days)
    val burn: BurnProgress = ProgressInsights.burn(loadedDays, loadedTrend)
    val wins: List<ProgressWin> = ProgressInsights.wins(days, trend.size, today)
    // Averages use complete days with nothing pending, the same days the bands judge.
    private val judged: List<NutritionTotals> = days.filter { it.status == DayStatus.Closed }.mapNotNull { it.foodTotals }
    val averages: NutritionValues = NutritionValues(mean { it.kcal }, mean { it.carbs }, mean { it.protein }, mean { it.fat })
    /** Complete days with nothing pending: the ones averages and bands use. */
    val judgedDays: Int = judged.count { it.kcal != null }

    private fun mean(field: (NutritionTotals) -> Double?): Double? = judged.mapNotNull(field).let { if (it.isEmpty()) null else it.average() }

    val bands: List<ProgressBand> get() = days.mapNotNull(ProgressInsights::band)
    val burnSummary: String get() = (burn as? BurnProgress.Estimate)?.let { "~" + kcal(it.estimate.kcalPerDay) + " a day" } ?: "Needs more data"
    val loggedDays: Int get() = days.count { it.status != null && it.foodTotals?.kcal != null }
    val averageKcal: Double? get() = averages.kcal
    val target: Double? get() = goal?.targets?.kcal

    /** The hero's one line under the verdict, as short as Today's "Complete day". */
    val shortEvidence: String get() = when (val h = headline) {
        ProgressHeadline.OnTrack, ProgressHeadline.HoldingSteady, ProgressHeadline.Drifting, ProgressHeadline.AtGoal -> {
            val span = if (loadedTrend.size >= 2) ProgressInsights.days(loadedTrend.first().localDate, loadedTrend.last().localDate) else 0
            val change = (ProgressInsights.slopePerDay(loadedTrend) ?: 0.0) * span
            val amount = NumberFormat.getNumberInstance(Locale.US).apply { minimumFractionDigits = 1; maximumFractionDigits = 1 }.format(abs(change))
            "${if (change <= 0) "Down" else "Up"} $amount kg in ${loadedDays.size} days"
        }
        is ProgressHeadline.CaloriesOnTrack -> "${h.near} of ${h.logged} days near your target"
        is ProgressHeadline.CaloriesOff -> "${h.near} of ${h.logged} days near your target"
        ProgressHeadline.NotEnoughData -> if (loggedDays > 0) "Set a calorie goal to see how close you land" else "Log a meal or weigh in to begin"
    }

    companion object {
        /** Loads hold at least 30 days so burn and the weight verdict have data on Week; the cards show only the range. */
        fun loadDays(range: ProgressRange) = maxOf(30, range.days)
        fun rangeStart(progress: CoachProgress, range: ProgressRange): String =
            progress.dailyReports.orEmpty().takeLast(range.days).firstOrNull()?.localDate ?: progress.startLocalDate
    }
}
