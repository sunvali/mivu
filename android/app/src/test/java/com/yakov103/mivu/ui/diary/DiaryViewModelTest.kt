package com.yakov103.mivu.ui.diary

import com.yakov103.mivu.diary.DayCompleteness
import com.yakov103.mivu.diary.DiaryDaySummary
import com.yakov103.mivu.diary.NutritionTotals
import com.yakov103.mivu.diary.TrackingDay
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Test

class DiaryViewModelTest {
    private fun date(s: String) = LocalDate.parse(s)
    private val day = TrackingDay(UUID.randomUUID(), "2026-10-12", "UTC", Instant.parse("2026-10-12T06:00:00Z"), DayCompleteness.unknown)
    private fun summary(meals: Int, saved: Int, d: TrackingDay? = day) =
        DiaryDaySummary(d, "2026-10-12", meals, saved, 0, NutritionTotals(null, null, null, null, 0))

    @Test fun weekStartsOnTheLocaleFirstDay() {
        // 2026-10-14 is a Wednesday.
        assertEquals(date("2026-10-12"), weekDates(date("2026-10-14"), DayOfWeek.MONDAY).first())
        assertEquals(date("2026-10-11"), weekDates(date("2026-10-14"), DayOfWeek.SUNDAY).first())
        assertEquals(7, weekDates(date("2026-10-14"), DayOfWeek.SUNDAY).size)
    }

    @Test fun pagesRunFromTheEarliestRecordThroughTodaysWeek() {
        val weeks = weekStarts(date("2026-09-30"), selected = date("2026-10-20"), today = date("2026-10-24"), DayOfWeek.MONDAY)
        assertEquals(listOf("2026-09-28", "2026-10-05", "2026-10-12", "2026-10-19").map(::date), weeks)
        // No records: only today's week.
        assertEquals(listOf(date("2026-10-19")), weekStarts(null, date("2026-10-24"), date("2026-10-24"), DayOfWeek.MONDAY))
    }

    @Test fun swipingKeepsTheWeekdayAndClampsToToday() {
        val today = date("2026-10-21") // Wednesday
        // Friday of the previous week moves to this week's Friday, which is after today: clamp.
        assertEquals(today, shiftedSelection(date("2026-10-16"), from = date("2026-10-12"), to = date("2026-10-19"), today))
        // Back one week keeps the weekday.
        assertEquals(date("2026-10-14"), shiftedSelection(today, from = date("2026-10-19"), to = date("2026-10-12"), today))
    }

    @Test fun pillLabelsFollowIos() {
        assertEquals("Monday 12 October, Open, 2 meals", pillLabel(date("2026-10-12"), summary(2, 1), activeDayID = day.id))
        assertEquals("Monday 12 October, Closed, 1 meal", pillLabel(date("2026-10-12"), summary(1, 1), activeDayID = null))
        assertEquals("Monday 12 October, Skipped, 0 meals", pillLabel(date("2026-10-12"), summary(0, 0), activeDayID = null))
        assertEquals("Monday 12 October, nothing logged", pillLabel(date("2026-10-12"), summary(0, 0, d = null), activeDayID = null))
        assertEquals("Monday 12 October, nothing logged", pillLabel(date("2026-10-12"), null, activeDayID = null))
    }
}
