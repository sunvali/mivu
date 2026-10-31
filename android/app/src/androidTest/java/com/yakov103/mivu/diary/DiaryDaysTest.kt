package com.yakov103.mivu.diary

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import java.io.File
import java.time.Instant
import java.util.UUID
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test

class DiaryDaysTest {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val profile = DiaryProfile(UUID.randomUUID(), "Synthetic", "en", "America/New_York", "")
    private lateinit var db: DiaryDatabase

    @Before fun open() {
        File(context.filesDir, "profiles").deleteRecursively()
        db = DiaryDatabase.create(context, profile)
    }

    @After fun close() {
        DayCutoff.hour = 4
        db.close()
        File(context.filesDir, "profiles").deleteRecursively()
    }

    @Test fun startDayCreatesActiveDayInZone() {
        val at = Instant.parse("2026-10-24T07:00:00Z") // 03:00 in New York: before the 4 am cutoff
        assertEquals(DayAssignment.NewDay, db.dayAssignment(at))
        val day = db.startDay(at, db.head().revision)
        assertEquals(TrackingDay(day.id, "2026-10-23", "America/New_York", at, DayCompleteness.unknown), day)
        val head = db.head()
        assertEquals(1L, head.revision)
        assertEquals(day.id, head.activeDayID)
        assertNotNull(head.activeConversationSegmentID)
        assertEquals(day, db.read { it.day(day.id) })
        assertEquals(DayAssignment.Existing(day.id), db.dayAssignment(at))
        assertEquals(DayAssignment.NewDay, db.dayAssignment(Instant.parse("2026-10-25T08:30:00Z")))
        // An explicit start while the active day covers the waking date opens the calendar date.
        val next = db.startDay(at, head.revision)
        assertEquals("2026-10-24", next.localDate)
        assertEquals(next.id, db.head().activeDayID)
    }

    @Test fun wakingDateUsesTheCutoffAtTheBoundaries() {
        val zone = profile.timeZoneID // New York is UTC-4 in October
        assertEquals("2026-10-23", wakingDateLabel(Instant.parse("2026-10-24T05:30:00Z"), zone)) // 01:30
        assertEquals("2026-10-24", wakingDateLabel(Instant.parse("2026-10-24T08:00:00Z"), zone)) // 04:00 exactly
        assertEquals("2026-10-24", wakingDateLabel(Instant.parse("2026-10-24T08:30:00Z"), zone)) // 04:30
        DayCutoff.hour = 6
        assertEquals("2026-10-23", wakingDateLabel(Instant.parse("2026-10-24T09:30:00Z"), zone)) // 05:30
    }

    @Test fun rollOverStartsOneDayAfterTheCutoff() {
        val yesterday = db.startDay(Instant.parse("2026-10-23T16:00:00Z"), db.head().revision)
        assertNull(db.rollOverDay(Instant.parse("2026-10-24T07:59:00Z"))) // 03:59
        val today = db.rollOverDay(Instant.parse("2026-10-24T08:10:00Z")) // 04:10
        assertEquals("2026-10-24", today?.localDate)
        assertEquals(today?.id, db.head().activeDayID)
        assertNull(db.rollOverDay(Instant.parse("2026-10-24T08:20:00Z")))
        assertEquals(listOf(yesterday.id, today!!.id).sorted(), db.read { it.days() }.map { it.id }.sorted())
    }

    @Test fun rollOverHonoursAChangedCutoff() {
        db.startDay(Instant.parse("2026-10-23T16:00:00Z"), db.head().revision)
        DayCutoff.hour = 6
        assertNull(db.rollOverDay(Instant.parse("2026-10-24T09:00:00Z"))) // 05:00
        assertEquals("2026-10-24", db.rollOverDay(Instant.parse("2026-10-24T10:05:00Z"))?.localDate) // 06:05
    }

    @Test fun rollOverWithoutAnActiveDayDoesNothing() {
        assertNull(db.rollOverDay(Instant.parse("2026-10-24T14:00:00Z")))
        assertNull(db.head().activeDayID)
        assertEquals(0L, db.head().revision)
    }

    @Test fun rollOverAfterThreeDaysAwayStartsTodayOnly() {
        db.startDay(Instant.parse("2026-10-20T16:00:00Z"), db.head().revision)
        assertEquals("2026-10-24", db.rollOverDay(Instant.parse("2026-10-24T14:00:00Z"))?.localDate)
        assertEquals(listOf("2026-10-20", "2026-10-24"), db.read { it.days() }.map { it.localDate }.sorted())
    }
}
