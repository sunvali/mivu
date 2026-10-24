package com.yakov103.mivu.progress

import com.yakov103.mivu.coach.CoachDailyProgress
import com.yakov103.mivu.coach.CoachProgress
import com.yakov103.mivu.coach.CoachWeightReference
import com.yakov103.mivu.coach.PlateauReadiness
import com.yakov103.mivu.coach.WeightProgress
import com.yakov103.mivu.diary.DayStatus
import com.yakov103.mivu.diary.GoalRecord
import com.yakov103.mivu.diary.NutritionTotals
import com.yakov103.mivu.diary.NutritionValues
import com.yakov103.mivu.diary.WeightEntry
import com.yakov103.mivu.progress.ProgressCalendarDot.Logged
import com.yakov103.mivu.progress.ProgressCalendarDot.NoLog
import com.yakov103.mivu.progress.ProgressCalendarDot.Outside
import java.time.LocalDate
import java.time.ZoneOffset
import java.util.UUID
import kotlin.math.pow
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Port of ios/MivuTests/ProgressInsightsTests.swift: the same synthetic numbers and expected values. */
class ProgressInsightsTest {
    @Test fun bandsByDistanceFromTarget() {
        assertEquals(ProgressBand.Near, ProgressBand.of(2310.0, 2100.0))
        assertEquals(ProgressBand.BitOff, ProgressBand.of(1680.0, 2100.0))
        assertEquals(ProgressBand.Off, ProgressBand.of(2835.0, 2100.0))
        assertEquals(ProgressBand.FarOff, ProgressBand.of(2836.0, 2100.0))
    }

    @Test fun unknownKcalHasNoBand() {
        assertNull(ProgressBand.of(null, 2100.0))
        assertNull(ProgressBand.of(1800.0, null))
        assertNull(ProgressBand.of(1800.0, 0.0))
    }

    @Test fun bandUsesEachDaysOwnGoal() {
        assertEquals(ProgressBand.Near, ProgressBand.of(2000.0, 2000.0))
        assertEquals(ProgressBand.Off, ProgressBand.of(2000.0, 1500.0))
    }

    // Weight trend and headline

    private fun weight(label: String, value: Double, unit: String = "kg") = CoachWeightReference(label,
        WeightEntry(UUID.randomUUID(), measuredAt = LocalDate.parse(label).atTime(12, 0).toInstant(ZoneOffset.UTC), value = value, unit = unit))
    private fun point(label: String, trend: Double) = TrendPoint(label, trend, trend)
    private fun day(label: String, kcal: Double?, target: Double? = 2100.0, protein: Double? = null, proteinTarget: Double? = null): CoachDailyProgress {
        val goal = GoalRecord(UUID.randomUUID(), "2026-01-01", "UTC", 1, NutritionValues(kcal = target, protein = proteinTarget), null, false)
        return CoachDailyProgress(label, if (kcal == null) null else DayStatus.Closed, kcal?.let { NutritionTotals(it, null, protein, null, 0) },
            goal, NutritionValues(), 0, null, null)
    }
    private val weekTrend = listOf("2026-10-16", "2026-10-19", "2026-10-23")

    @Test fun trendWeightsByElapsedDays() {
        val last = WeightTrend.points(listOf(weight("2026-09-01", 80.0), weight("2026-09-22", 78.0))).last()
        assertEquals(80 + (78 - 80) * (1 - 0.9.pow(21)), last.trend, 0.01)
        assertEquals(78.22, last.trend, 0.01)
    }

    @Test fun trendConvertsPounds() {
        assertEquals(80.0, WeightTrend.points(listOf(weight("2026-09-01", 176.37, unit = "lb"))).first().raw, 0.01)
    }

    @Test fun headlineOnTrackWhenTrendMovesTowardGoal() {
        val trend = listOf(point(weekTrend[0], 79.6), point(weekTrend[1], 79.3), point(weekTrend[2], 79.0))
        assertEquals(ProgressHeadline.OnTrack, ProgressInsights.headline(trend, 75.0, 80.0, emptyList()))
    }

    @Test fun headlineHoldingWhenMoveUnderTenthKgPerWeek() {
        val trend = listOf(point(weekTrend[0], 79.60), point(weekTrend[1], 79.58), point(weekTrend[2], 79.55))
        assertEquals(ProgressHeadline.HoldingSteady, ProgressInsights.headline(trend, 75.0, 80.0, emptyList()))
    }

    @Test fun headlineDriftingWhenMovingAway() {
        val trend = listOf(point(weekTrend[0], 79.0), point(weekTrend[1], 79.1), point(weekTrend[2], 79.3))
        assertEquals(ProgressHeadline.Drifting, ProgressInsights.headline(trend, 75.0, 80.0, emptyList()))
    }

    @Test fun headlineAtGoalWithinOneKg() {
        val trend = listOf(point(weekTrend[0], 76.2), point(weekTrend[1], 76.0), point(weekTrend[2], 75.8))
        assertEquals(ProgressHeadline.AtGoal, ProgressInsights.headline(trend, 75.0, 80.0, emptyList()))
    }

    @Test fun headlineFallsBackToCaloriesWithoutGoalWeight() {
        val trend = listOf(point(weekTrend[0], 79.6), point(weekTrend[1], 79.3), point(weekTrend[2], 79.0))
        val days = listOf(day("2026-10-17", 2050.0), day("2026-10-18", 2180.0), day("2026-10-19", 1890.0),
            day("2026-10-20", 2420.0), day("2026-10-21", null), day("2026-10-22", 1550.0), day("2026-10-23", 1980.0))
        assertEquals(ProgressHeadline.CaloriesOnTrack(4, 6), ProgressInsights.headline(trend, null, null, days))
    }

    @Test fun headlineFallsBackWhenTooFewWeighIns() {
        val trend = listOf(point("2026-10-16", 79.6), point("2026-10-23", 79.0))
        val days = listOf(day("2026-10-22", 3000.0), day("2026-10-23", 2100.0))
        assertEquals(ProgressHeadline.CaloriesOff(1, 2), ProgressInsights.headline(trend, 75.0, 80.0, days))
    }

    // Burn and wins

    private fun label(offset: Int) = LocalDate.parse("2026-09-01").plusDays(offset.toLong()).toString()
    private fun loggedDays(count: Int, kcal: Double = 2100.0) = (0 until count).map { day(label(it), kcal) }

    @Test fun burnNeedsFourteenCompleteDaysAndFourWeighIns() {
        val trend = listOf(point(label(0), 80.0), point(label(10), 79.8), point(label(20), 79.6))
        assertEquals(BurnProgress.Needs(4, 1), ProgressInsights.burn(loggedDays(10), trend))
    }

    @Test fun burnFromIntakeAndTrend() {
        val trend = listOf(point(label(0), 80.0), point(label(7), 79.75), point(label(14), 79.5), point(label(28), 79.0))
        val estimate = (ProgressInsights.burn(loggedDays(28), trend) as BurnProgress.Estimate).estimate
        assertEquals(2100 + 7700.0 / 28, estimate.kcalPerDay, 1.0)
    }

    @Test fun burnBandNarrowsWithMoreDays() {
        val trend = listOf(point(label(0), 80.0), point(label(10), 79.7), point(label(20), 79.3), point(label(30), 79.0))
        val early = (ProgressInsights.burn(loggedDays(14), trend) as BurnProgress.Estimate).estimate
        val late = (ProgressInsights.burn(loggedDays(30), trend) as BurnProgress.Estimate).estimate
        assertTrue(early.band > late.band)
        assertEquals(100.0, late.band, 0.0)
    }

    @Test fun winsPreferProteinRunThenLoggingThenWeighIns() {
        val days = (0 until 6).map { day(label(it), 2000.0, protein = if (it >= 2) 150.0 else 80.0, proteinTarget = 140.0) }
        assertEquals(listOf("protein-run", "logged-days", "weigh-ins"), ProgressInsights.wins(days, 5).map { it.id })
        assertEquals("Protein goal 4 days running", ProgressInsights.wins(days, 5).first().title)
    }

    @Test fun noWinsWhenNothingQualifies() {
        assertTrue(ProgressInsights.wins(listOf(day(label(0), 2000.0)), 0).isEmpty())
    }

    // Buckets

    private fun range(endingOn: String, days: Int, kcal: (Int) -> Double? = { 2000.0 }): List<CoachDailyProgress> {
        val last = LocalDate.parse(endingOn)
        return (days - 1 downTo 0).map { back -> day(last.minusDays(back.toLong()).toString(), kcal(back)) }
    }

    @Test fun weekAndMonthBucketPerDay() {
        assertEquals(7, ProgressInsights.buckets(range("2026-10-22", 7), ProgressRange.Week).size)
        assertEquals(30, ProgressInsights.buckets(range("2026-10-22", 30), ProgressRange.Month).size)
    }

    @Test fun quarterBucketsByMondayWeek() {
        val buckets = ProgressInsights.buckets(range("2026-10-22", 91), ProgressRange.Quarter)
        assertEquals(14, buckets.size)
        assertEquals("2026-07-20", buckets.first().start.toString())
        assertEquals(3, buckets.first().loggedDays) // Fri 24 – Sun 26 July
    }

    @Test fun yearBucketsByMonth() {
        val buckets = ProgressInsights.buckets(range("2026-10-22", 365), ProgressRange.Year)
        assertEquals(13, buckets.size)
        assertEquals("2025-10-01", buckets.first().start.toString())
    }

    @Test fun bucketsSkipMissingDaysNotZero() {
        val days = range("2026-10-22", 14) { if (it >= 7) null else 2100.0 }
        val buckets = ProgressInsights.buckets(days, ProgressRange.Quarter)
        val empty = buckets.filter { it.loggedDays == 0 }
        assertTrue(empty.isNotEmpty() && empty.all { it.averageKcal == null && it.band == null })
        assertTrue(buckets.last().averageKcal == 2100.0 && buckets.last().band == ProgressBand.Near)
    }

    // Review fixes

    @Test fun partialAndPendingDaysGetNoBandAndStayOutOfTheHeadline() {
        val complete = day("2026-10-21", 2100.0)
        val partial = day("2026-10-22", 400.0).copy(status = DayStatus.Open)
        val pending = day("2026-10-23", 300.0).copy(status = DayStatus.Skipped)
        assertEquals(ProgressBand.Near, ProgressInsights.band(complete))
        assertTrue(ProgressInsights.band(partial) == null && ProgressInsights.band(pending) == null)
        assertEquals(ProgressHeadline.CaloriesOnTrack(1, 1), ProgressInsights.headline(emptyList(), null, null, listOf(complete, partial, pending)))
        val bucket = ProgressInsights.buckets(listOf(partial), ProgressRange.Week).first()
        assertTrue(bucket.averageKcal == 400.0 && bucket.band == null && !bucket.complete)
    }

    @Test fun steadyLossReadsOnTrackDespiteTheSmoothedLag() {
        // 0.25 kg a week, weighed daily: the lagging EMA alone would read "holding steady".
        val weights = (0..7).map { weight(label(it), 80 - 0.25 / 7 * it) }
        assertEquals(ProgressHeadline.OnTrack, ProgressInsights.headline(WeightTrend.points(weights), 75.0, 80.0, emptyList()))
    }

    @Test fun burnUsesTheWeighInSlopeNotTheLaggingTrend() {
        // 0.5 kg a week over 14 complete days at 2,100 kcal → ~2,650 kcal burn.
        val weights = (0..14).map { weight(label(it), 80 - 0.5 / 7 * it) }
        val estimate = (ProgressInsights.burn(loggedDays(14), WeightTrend.points(weights)) as BurnProgress.Estimate).estimate
        assertEquals(2100 + 0.5 / 7 * 7700, estimate.kcalPerDay, 5.0)
    }

    @Test fun proteinStreakIgnoresTodayWhileItIsUnfinished() {
        val days = (0 until 5).map { day(label(it), 2000.0, protein = 150.0, proteinTarget = 140.0) } +
            day(label(5), 600.0, protein = 30.0, proteinTarget = 140.0)
        assertEquals("Protein goal 5 days running", ProgressInsights.wins(days, 0, today = label(5)).first().title)
    }

    private val weekly = WeightProgress(label(29), null, 0, null, null, PlateauReadiness.InsufficientData)
    private fun progress(days: List<CoachDailyProgress>, weights: List<CoachWeightReference>, weight: WeightProgress = weekly) =
        CoachProgress(days.first().localDate, days.last().localDate, days.last(), null, weight, emptyList(), emptyList(), 0, 0, false,
            dailyReports = days, displayWeights = weights)

    @Test fun weekShowsSevenDaysButJudgesBurnAndWeightOnTheLoadedMonth() {
        val days = loggedDays(30)
        val weights = (0 until 30).filter { it % 2 == 0 }.map { weight(label(it), 80 - 0.5 / 7 * it) }
        val snapshot = ProgressSnapshot(progress(days, weights), ProgressRange.Week, "UTC", label(29))
        assertTrue(snapshot.days.size == 7 && snapshot.days.first().localDate == label(23))
        assertTrue("A week view with a logged month shows a burn", snapshot.burn is BurnProgress.Estimate)
    }

    @Test fun weekEvidenceQuotesTheSameWindowAsTheVerdict() {
        val goal = GoalRecord(UUID.randomUUID(), label(0), "UTC", 1, NutritionValues(kcal = 2100.0), 75.0, false)
        val days = loggedDays(30).map { it.copy(status = DayStatus.Closed, goal = goal) }
        // Down over the month, up a little in the last week.
        val weights = (0 until 30).filter { it % 2 == 0 }.map { weight(label(it), if (it < 24) 80 - 0.06 * it else 78.9) }
        val snapshot = ProgressSnapshot(progress(days, weights), ProgressRange.Week, "UTC", label(29))
        assertEquals(ProgressHeadline.OnTrack, snapshot.headline)
        assertTrue(snapshot.shortEvidence, snapshot.shortEvidence.startsWith("Down") && snapshot.shortEvidence.endsWith("kg in 30 days"))
    }

    // Plain language

    @Test fun dayResultsReadInPlainWords() {
        assertEquals("2,100 kcal · on target", ProgressInsights.plainResult(day("2026-10-20", 2100.0)))
        assertEquals("2,420 kcal · 320 over", ProgressInsights.plainResult(day("2026-10-20", 2420.0)))
        assertEquals("1,550 kcal · 550 under", ProgressInsights.plainResult(day("2026-10-20", 1550.0)))
        assertEquals("No log", ProgressInsights.plainResult(day("2026-10-20", null)))
        assertEquals("1,800 kcal", ProgressInsights.plainResult(day("2026-10-20", 1800.0, target = null)))
    }

    @Test fun goalGapReadsInPlainWords() {
        assertEquals("on target", ProgressInsights.plainGap(2296.0, 2100.0))
        assertEquals("400 over", ProgressInsights.plainGap(2500.0, 2100.0))
        assertEquals("400 under", ProgressInsights.plainGap(1700.0, 2100.0))
    }

    @Test fun shortEvidenceIsOneShortLine() {
        val days = listOf(day("2026-10-21", 2100.0), day("2026-10-22", 2150.0), day("2026-10-23", 3000.0))
        val progress = progress(days, emptyList(), weekly.copy(endLocalDate = "2026-10-23"))
        assertEquals("2 of 3 days near your target", ProgressSnapshot(progress, ProgressRange.Week, "UTC", "2026-10-23").shortEvidence)
    }

    @Test fun macroLinesReadInPlainWords() {
        assertEquals("215 g a day · 75 g over goal", ProgressInsights.plainMacro(215.0, 140.0))
        assertEquals("100 g a day · 40 g under goal", ProgressInsights.plainMacro(100.0, 140.0))
        assertEquals("145 g a day · on goal", ProgressInsights.plainMacro(145.0, 140.0))
        assertEquals("No complete days", ProgressInsights.plainMacro(null, 140.0))
        assertEquals("80 g a day", ProgressInsights.plainMacro(80.0, null))
    }

    @Test fun calendarRowsAreWeeksOfDotsThenMonthsOfCounts() {
        // Thu 2026-10-15 … Wed 2026-10-21: one partial week and the start of the next, newest first.
        val days = range("2026-10-21", 7) { if (it == 2) null else 2100.0 }
        val weeks = ProgressInsights.calendarRows(days, ProgressRange.Week)
        assertEquals(listOf("Oct 19 – 25", "Oct 12 – 18"), weeks.map { it.title })
        val near = Logged(ProgressBand.Near)
        assertEquals(listOf(Outside, Outside, Outside, near, near, near, near), weeks[1].dots)
        assertTrue(weeks[0].dots?.take(3) == listOf(NoLog, near, near) && weeks[0].logged == 2 && weeks[0].total == 3)
        val months = ProgressInsights.calendarRows(range("2026-10-21", 91), ProgressRange.Quarter)
        assertTrue(months.first().title == "October 2026" && months.first().dots == null && months.first().total == 21)
    }

    @Test fun headlineNotEnoughDataWithNothingLogged() {
        assertEquals(ProgressHeadline.NotEnoughData, ProgressInsights.headline(emptyList(), 75.0, null, listOf(day("2026-10-23", null))))
    }
}
