package com.yakov103.mivu.coach

import java.time.LocalDate
import java.time.ZoneId
import java.util.Locale
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test

class CoachReplyLinesTest {
    private val previous = Locale.getDefault()
    @Before fun us() = Locale.setDefault(Locale.US)
    @After fun restore() = Locale.setDefault(previous)

    /** UTC+14: the profile's today can be the device's tomorrow. */
    @Test fun dayTitleIsRelativeToTheProfileZone() {
        val zone = "Pacific/Kiritimati"
        val today = LocalDate.now(ZoneId.of(zone))
        assertEquals("Today", CoachReplyLines.dayTitle(today.toString(), zone))
        assertEquals("Yesterday", CoachReplyLines.dayTitle(today.minusDays(1).toString(), zone))
        assertEquals("Oct 17, 2025", CoachReplyLines.dayTitle("2025-10-17", zone))
        assertEquals("2026-13-40", CoachReplyLines.dayTitle("2026-13-40", zone))
    }
}
