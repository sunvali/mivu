package com.yakov103.mivu.diary

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import java.io.File
import java.time.Instant
import java.util.UUID
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
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
}
