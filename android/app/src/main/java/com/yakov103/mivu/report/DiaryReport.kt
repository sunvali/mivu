package com.yakov103.mivu.report

import com.yakov103.mivu.diary.DayCompleteness
import com.yakov103.mivu.diary.DayCutoff
import com.yakov103.mivu.diary.DiarySnapshot
import com.yakov103.mivu.diary.MealTimePrecision
import com.yakov103.mivu.diary.NutritionTotals
import com.yakov103.mivu.diary.NutritionValues
import com.yakov103.mivu.diary.WeightEntry
import com.yakov103.mivu.diary.dayNutritionTotals
import com.yakov103.mivu.diary.diaryDateLabel
import com.yakov103.mivu.diary.goalOn
import com.yakov103.mivu.diary.nutritionTotals
import com.yakov103.mivu.diary.wakingDateLabel
import java.io.File
import java.math.BigDecimal
import java.math.RoundingMode
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit

// Port of ios/Mivu/Diary/DiaryReport.swift.

/** A shareable view of saved diary data over a range of local dates, kept apart from the UI so a later sender can reuse it. */
class DiaryReport(snapshot: DiarySnapshot, from: String?, through: String?) {
    enum class Format { PDF, CSV }
    data class Meal(val time: String, val name: String, val totals: NutritionTotals)
    data class Day(val localDate: String, val totals: NutritionTotals, val target: NutritionValues?, val weight: WeightEntry?, val meals: List<Meal>)
    data class Weight(val localDate: String, val time: String, val entry: WeightEntry)

    val profileName: String = snapshot.profile.name
    val weights: List<Weight>
    val days: List<Day>
    /** The requested local dates; for all time, the first and last diary days. */
    val from: String?
    val through: String?

    init {
        fun inRange(date: String) = (from == null || date >= from) && (through == null || date <= through)
        fun clock(at: Instant, zone: String) = DateTimeFormatter.ofPattern("HH:mm").format(at.atZone(ZoneId.of(zone, ZoneId.SHORT_IDS)))
        val dayByID = snapshot.days.associateBy { it.id }
        weights = snapshot.weights.mapNotNull { entry ->
            val day = entry.dayID?.let(dayByID::get)
            val zone = day?.timeZoneID ?: snapshot.profile.timeZoneID
            val localDate = day?.localDate ?: diaryDateLabel(entry.measuredAt, zone)
            if (!inRange(localDate)) null
            else Weight(localDate, if (entry.timePrecision == MealTimePrecision.dateOnly) "" else clock(entry.measuredAt, zone), entry)
        }.sortedBy { it.entry.measuredAt }
        days = snapshot.days.filter { inRange(it.localDate) }.sortedBy { it.localDate }.map { day ->
            val dayMeals = snapshot.meals.filter { it.dayID == day.id }
            val meals = dayMeals.filter { it.revision > 0 }.sortedBy { it.eatenAt }.map { meal ->
                val name = meal.items.joinToString(", ") { it.name }
                val text = meal.submissions.firstOrNull()?.text?.trim().orEmpty()
                Meal(if (meal.timePrecision == MealTimePrecision.dateOnly) "" else clock(meal.eatenAt, day.timeZoneID),
                    name.ifEmpty { text.ifEmpty { "Meal" } }, nutritionTotals(meal.items))
            }
            Day(day.localDate, dayNutritionTotals(dayMeals, day.completeness == DayCompleteness.complete),
                goalOn(day.localDate, snapshot.goals)?.targets, weights.lastOrNull { it.localDate == day.localDate }?.entry, meals)
        }
        this.from = from ?: days.firstOrNull()?.localDate
        this.through = through ?: days.lastOrNull()?.localDate
    }

    val calendarDayCount: Int
        get() {
            val start = from?.let(::date) ?: return days.size
            val end = through?.let(::date) ?: return days.size
            return ChronoUnit.DAYS.between(start, end).toInt() + 1
        }
    internal val label get() = if (from != null && through != null) "$from to $through" else "empty"

    val mealsCSV: String
        get() = csv(listOf("Date", "Time", "Meal", "Calories (kcal)", "Protein (g)", "Carbs (g)", "Fat (g)"), days.flatMap { day ->
            day.meals.map { listOf(day.localDate, it.time, it.name, number(it.totals.kcal), number(it.totals.protein), number(it.totals.carbs), number(it.totals.fat)) }
        })
    val daysCSV: String
        get() = csv(listOf("Date", "Calories (kcal)", "Calorie target (kcal)", "Protein (g)", "Protein target (g)", "Carbs (g)", "Fat (g)", "Weight"), days.map {
            listOf(it.localDate, number(it.totals.kcal), number(it.target?.kcal), number(it.totals.protein), number(it.target?.protein),
                number(it.totals.carbs), number(it.totals.fat), it.weight?.let { w -> "${number(w.value)} ${w.unit}" }.orEmpty())
        })
    val weightsCSV: String
        get() = csv(listOf("Date", "Time", "Weight", "Unit"), weights.map { listOf(it.localDate, it.time, number(it.entry.value), it.entry.unit) })

    private fun csv(header: List<String>, rows: List<List<String>>) =
        (listOf(header) + rows).joinToString("") { row -> row.joinToString(",", transform = ::field) + "\r\n" }

    fun number(value: Double?): String =
        value?.let { BigDecimal(it.toString()).setScale(1, RoundingMode.HALF_EVEN).stripTrailingZeros().toPlainString() }.orEmpty()

    companion object {
        /** The last [count] waking days ending today, so an export at 01:30 still ends on the day being lived. */
        fun lastDays(count: Int, now: Instant, zone: String, cutoffHour: Int = DayCutoff.hour): Pair<String, String> {
            val through = wakingDateLabel(now, zone, cutoffHour)
            return shift(through, 1 - count) to through
        }

        /** Local dates are calendar labels, so arithmetic is on dates, never instants. */
        fun shift(localDate: String, days: Int): String = date(localDate)?.plusDays(days.toLong())?.toString() ?: localDate

        internal fun date(localDate: String): LocalDate? = runCatching { LocalDate.parse(localDate) }.getOrNull()

        /** RFC 4180 quoting, and a leading apostrophe so spreadsheets never run user text as a formula. */
        private fun field(raw: String): String {
            val value = if (raw.isNotEmpty() && raw[0] in "=+-@\t\r" && raw.toDoubleOrNull() == null) "'$raw" else raw
            return if (value.any { it in ",\"\r\n" }) "\"" + value.replace("\"", "\"\"") + "\"" else value
        }
    }
}

/** Writes the report into [directory] with the iOS file names. */
fun DiaryReport.write(format: DiaryReport.Format, directory: File): List<File> {
    directory.mkdirs()
    val files = when (format) {
        DiaryReport.Format.PDF -> listOf("Mivu report $label.pdf" to pdf())
        DiaryReport.Format.CSV -> listOf("Mivu meals $label.csv" to mealsCSV.toByteArray(), "Mivu days $label.csv" to daysCSV.toByteArray(),
            "Mivu weights $label.csv" to weightsCSV.toByteArray())
    }
    return files.map { (name, bytes) -> File(directory, name).apply { writeBytes(bytes) } }
}
