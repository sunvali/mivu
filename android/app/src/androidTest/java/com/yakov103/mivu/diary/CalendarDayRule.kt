package com.yakov103.mivu.diary

import org.junit.rules.ExternalResource

/**
 * Pins the day cutoff to midnight, so the waking day is the calendar date at any hour (a run between 00:00 and the
 * real cutoff would otherwise log to the day before). Restores the cutoff afterwards.
 */
class CalendarDayRule : ExternalResource() {
    private var saved = DayCutoff.hour

    override fun before() {
        saved = DayCutoff.hour
        DayCutoff.hour = 0
    }

    override fun after() {
        DayCutoff.hour = saved
    }
}
