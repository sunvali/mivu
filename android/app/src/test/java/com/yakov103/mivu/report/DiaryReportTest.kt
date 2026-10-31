package com.yakov103.mivu.report

import com.yakov103.mivu.diary.DayCompleteness
import com.yakov103.mivu.diary.DiaryMeal
import com.yakov103.mivu.diary.DiaryProfile
import com.yakov103.mivu.diary.DiarySnapshot
import com.yakov103.mivu.diary.FoodItem
import com.yakov103.mivu.diary.NutritionProvenance
import com.yakov103.mivu.diary.NutritionValues
import com.yakov103.mivu.diary.TrackingDay
import com.yakov103.mivu.diary.WeightEntry
import java.time.Instant
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Test

/** Synthetic diaries only. */
class DiaryReportTest {
    private val profile = DiaryProfile(UUID.randomUUID(), "Sample", "en", "UTC", "")

    private fun day(date: String) = TrackingDay(UUID.randomUUID(), date, "UTC", Instant.parse("${date}T06:00:00Z"), DayCompleteness.unknown)

    private fun meal(day: TrackingDay, name: String, kcal: Double) = DiaryMeal(
        UUID.randomUUID(), day.id, day.startAt, day.startAt.plusSeconds(3600), 1, items = listOf(
            FoodItem(UUID.randomUUID(), name, 1.0, "serving", NutritionValues(kcal, 10.0, 5.0, 2.0), NutritionProvenance.user, "", false, emptyMap()),
        ), photos = emptyList(), submissions = emptyList(),
    )

    private fun snapshot(days: List<TrackingDay>, meals: List<DiaryMeal> = emptyList(), weights: List<WeightEntry> = emptyList()) =
        DiarySnapshot(1, 1, profile, days, meals, weights, deletedMealIDs = emptyList())

    @Test fun csvNeutralisesFormulasAndQuotes() {
        val d = day("2026-10-20")
        val csv = DiaryReport(snapshot(listOf(d), listOf(meal(d, "=SUM(A1)", 1.0), meal(d, "-5", 2.0), meal(d, "a \"b\", c", 3.0))), null, null)
            .mealsCSV.split("\r\n")
        assertEquals("2026-10-20,07:00,'=SUM(A1),1,5,10,2", csv[1])
        assertEquals("2026-10-20,07:00,-5,2,5,10,2", csv[2])
        assertEquals("2026-10-20,07:00,\"a \"\"b\"\", c\",3,5,10,2", csv[3])
    }

    @Test fun numbersUseAtMostOneDecimalAndNoGrouping() {
        val report = DiaryReport(snapshot(emptyList()), null, null)
        assertEquals("12345.7", report.number(12345.67))
        assertEquals("2100", report.number(2100.0))
        assertEquals("0.5", report.number(0.5))
        assertEquals("", report.number(null))
    }

    @Test fun lastDaysEndsOnTheWakingDay() {
        assertEquals("2026-10-18" to "2026-10-24", DiaryReport.lastDays(7, Instant.parse("2026-10-25T01:30:00Z"), "UTC", cutoffHour = 4))
    }

    @Test fun allTimeUsesTheFirstAndLastDiaryDays() {
        val report = DiaryReport(snapshot(listOf(day("2026-10-22"), day("2026-10-01"), day("2026-10-09"))), null, null)
        assertEquals("2026-10-01", report.from)
        assertEquals("2026-10-22", report.through)
        assertEquals(22, report.calendarDayCount)
    }

    @Test fun legacyWeightWithoutADayUsesItsMeasuredDate() {
        val weight = WeightEntry(UUID.randomUUID(), null, Instant.parse("2026-10-21T23:30:00Z"), 72.4, "kg")
        val report = DiaryReport(snapshot(emptyList(), weights = listOf(weight)), "2026-10-21", "2026-10-21")
        assertEquals("Date,Time,Weight,Unit\r\n2026-10-21,23:30,72.4,kg\r\n", report.weightsCSV)
    }
}
