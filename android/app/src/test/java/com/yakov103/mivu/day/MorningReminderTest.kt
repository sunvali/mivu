package com.yakov103.mivu.day

import java.time.Duration
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZonedDateTime
import org.junit.Assert.assertEquals
import org.junit.Test

class MorningReminderTest {
    private val zone = ZoneId.of("Europe/Berlin")

    @Test fun nextTriggerIsLaterTodayOrTomorrow() {
        val morning = ZonedDateTime.of(2026, 6, 10, 7, 30, 0, 0, zone)
        assertEquals(ZonedDateTime.of(2026, 6, 10, 8, 0, 0, 0, zone), MorningReminder.nextTrigger(morning, 8 * 60))
        // At the minute itself or after, the next one is tomorrow.
        assertEquals(ZonedDateTime.of(2026, 6, 11, 8, 0, 0, 0, zone), MorningReminder.nextTrigger(morning.withHour(8).withMinute(0), 8 * 60))
        assertEquals(ZonedDateTime.of(2026, 6, 11, 6, 45, 0, 0, zone), MorningReminder.nextTrigger(morning, 6 * 60 + 45))
    }

    @Test fun nextTriggerSurvivesADstChange() {
        // Summer time ends in the UK at 02:00 on Sunday 25 October 2026: the reminder stays at 08:00 on the wall clock.
        val london = ZoneId.of("Europe/London")
        val evening = ZonedDateTime.of(2026, 10, 24, 22, 0, 0, 0, london)
        val next = MorningReminder.nextTrigger(evening, 8 * 60)
        assertEquals(LocalTime.of(8, 0), next.toLocalTime())
        assertEquals("2026-10-25", next.toLocalDate().toString())
        assertEquals(Duration.ofHours(11), Duration.between(evening, next))
    }

    @Test fun greetingFollowsTheHour() {
        assertEquals("Good evening", greeting(4))
        assertEquals("Good morning", greeting(5))
        assertEquals("Good morning", greeting(11))
        assertEquals("Good afternoon", greeting(12))
        assertEquals("Good afternoon", greeting(17))
        assertEquals("Good evening", greeting(18))
        assertEquals("Good evening", greeting(0))
    }
}
