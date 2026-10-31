package com.yakov103.mivu.diary

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import java.io.File
import java.time.Instant
import java.util.UUID
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test

class MealCaptureTest {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val profile = DiaryProfile(UUID.randomUUID(), "Synthetic", "en", "UTC", "")
    private val at = Instant.parse("2026-10-24T12:00:00Z")
    private lateinit var db: DiaryDatabase
    private lateinit var day: TrackingDay

    @Before fun open() {
        File(context.filesDir, "profiles").deleteRecursively()
        db = DiaryDatabase.create(context, profile)
        day = db.startDay(Instant.parse("2026-10-24T06:00:00Z"), db.head().revision)
    }

    @After fun close() {
        db.close()
        File(context.filesDir, "profiles").deleteRecursively()
    }

    private inline fun <reified E : Throwable> throws(block: () -> Unit) {
        try { block(); fail("expected ${E::class.simpleName}") } catch (e: Throwable) { if (e !is E) throw e }
    }

    private fun photo() = MealPhoto(UUID.randomUUID(), byteArrayOf(1, 2, 3), at, PhotoRole.unspecified)

    @Test fun captureSavesSubmissionCapturedBeforeAnalysis() {
        val photo = photo()
        val meal = db.captureProjection("synthetic soup", listOf(photo), false, day.id, at, expectedRevision = db.head().revision)
        assertEquals(meal, db.read { it.meal(meal.id) })
        assertEquals(0, meal.revision)
        assertEquals(at, meal.eatenAt)
        assertEquals(null, meal.timePrecision)
        assertEquals(listOf(photo), meal.photos)
        val sub = meal.submissions.single()
        assertEquals(MealSubmission(sub.id, 0, "synthetic soup", listOf(photo.id), false, SubmissionState.captured), sub)
        assertEquals(meal.id to sub.id, db.nextPendingMealSubmission())

        val dated = db.captureProjection("synthetic tea", emptyList(), true, day.id, at, dateOnly = true,
            expectedRevision = db.head().revision)
        assertEquals(day.startAt, dated.eatenAt)
        assertEquals(MealTimePrecision.dateOnly, dated.timePrecision)
        throws<DiaryError.EmptyCapture> { db.captureProjection(" \n", emptyList(), false, day.id, at, expectedRevision = db.head().revision) }
        throws<DiaryError.NotFound> { db.captureProjection("x", emptyList(), false, UUID.randomUUID(), at, expectedRevision = db.head().revision) }
    }

    @Test fun captureRetrySameSubmissionIdIdempotent() {
        val id = UUID.randomUUID()
        val photos = listOf(photo())
        val meal = db.captureProjection("synthetic soup", photos, false, day.id, at, submissionID = id, expectedRevision = db.head().revision)
        val head = db.head()
        val retry = db.captureProjection("synthetic soup", photos, false, day.id, at.plusSeconds(5), submissionID = id,
            expectedRevision = head.revision)
        assertEquals(meal, retry)
        assertEquals(head, db.head())
        assertEquals(1, db.snapshot().meals.size)
    }
}
