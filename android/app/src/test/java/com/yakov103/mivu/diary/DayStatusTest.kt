package com.yakov103.mivu.diary

import java.time.Instant
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class DayStatusTest {
    private val at = Instant.parse("2026-01-01T12:00:00Z")
    private fun day(completeness: DayCompleteness = DayCompleteness.unknown) =
        TrackingDay(UUID.randomUUID(), "2026-01-01", "UTC", at, completeness)

    @Test fun untrackedIsSkipped() {
        val d = day(DayCompleteness.untracked)
        assertEquals(DayStatus.Skipped, dayStatus(listOf(d), d.id, hasSavedFood = true))
    }

    @Test fun activeIsOpen() {
        val d = day()
        assertEquals(DayStatus.Open, dayStatus(listOf(d), d.id, hasSavedFood = false))
    }

    @Test fun savedFoodClosed() {
        assertEquals(DayStatus.Closed, dayStatus(listOf(day(DayCompleteness.complete)), null, hasSavedFood = true))
    }

    @Test fun noFoodSkipped() {
        assertEquals(DayStatus.Skipped, dayStatus(listOf(day()), null, hasSavedFood = false))
        assertNull(dayStatus(emptyList(), null, hasSavedFood = false))
    }
}
