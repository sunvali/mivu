package com.yakov103.mivu.widget

import java.time.Instant
import java.time.OffsetDateTime
import java.util.TimeZone
import org.junit.Assert.assertEquals
import org.junit.Test

class WidgetSnapshotTest {
    private val sample = WidgetSnapshot("2026-10-20", 1359.6, 2000.0, true, rolloverAt = 1_000_000, writtenAt = 0)

    private fun millis(iso: String) = OffsetDateTime.parse(iso).toInstant().toEpochMilli()

    @Test fun nextRolloverUsesTheDaysZone() {
        val jvmZone = TimeZone.getDefault()
        try {
            TimeZone.setDefault(TimeZone.getTimeZone("Asia/Tokyo"))
            val next = WidgetSnapshot.nextRollover(millis("2026-10-24T22:00-04:00"), "America/New_York", 4)
            assertEquals(millis("2026-10-25T04:00-04:00"), next)
        } finally {
            TimeZone.setDefault(jvmZone)
        }
    }

    @Test fun nextRolloverCrossesDst() {
        // New York falls back at 02:00 on 1 November 2026: the cutoff stays 04:00 on the wall clock, 25 hours later.
        assertEquals(millis("2026-11-01T04:00-05:00"), WidgetSnapshot.nextRollover(millis("2026-10-31T04:00-04:00"), "America/New_York", 4))
        // Spring forward skips 02:00 on 8 March 2026: as iOS `.nextTime`, the next existing time, 03:00.
        assertEquals(millis("2026-03-08T03:00-04:00"), WidgetSnapshot.nextRollover(millis("2026-03-07T22:00-05:00"), "America/New_York", 2))
        // The cutoff itself is not "after": the next one is a day later.
        assertEquals(Instant.parse("2026-10-22T04:00:00Z").toEpochMilli(),
            WidgetSnapshot.nextRollover(Instant.parse("2026-10-21T04:00:00Z").toEpochMilli(), "UTC", 4))
    }

    @Test fun afterRolloverZeroesEatenAndKeepsTarget() {
        assertEquals(sample.copy(eaten = 0.0), sample.afterRollover())
    }

    @Test fun ringFractionCapsAtOne() {
        assertEquals(1.0, sample.copy(eaten = 2300.0).ringFraction, 0.0)
        assertEquals(0.5, sample.copy(eaten = 1000.0).ringFraction, 0.0)
    }

    @Test fun noTargetHasNoFraction() {
        assertEquals(0.0, sample.copy(target = null).ringFraction, 0.0)
        assertEquals(0.0, sample.copy(target = 0.0).ringFraction, 0.0)
    }
}
