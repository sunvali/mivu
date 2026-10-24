package com.yakov103.mivu.diary

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import androidx.test.core.app.ApplicationProvider
import java.io.File
import java.time.Instant
import java.util.UUID
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test

class DiaryCaptureTest {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val profile = DiaryProfile(UUID.randomUUID(), "Synthetic", "en", "UTC", "")
    private lateinit var db: DiaryDatabase

    @Before fun open() {
        File(context.filesDir, "profiles").deleteRecursively()
        db = DiaryDatabase.create(context, profile)
    }

    @After fun close() {
        db.close()
        File(context.filesDir, "profiles").deleteRecursively()
    }

    private inline fun <reified E : Throwable> throws(block: () -> Unit) {
        try { block(); fail("expected ${E::class.simpleName}") } catch (e: Throwable) { if (e !is E) throw e }
    }

    private val at = Instant.parse("2026-10-24T12:00:00Z")
    private fun photo() = MealPhoto(UUID.randomUUID(), byteArrayOf(1, 2, 3), at, PhotoRole.unspecified)
    private fun payload(text: String = "synthetic lunch", photos: List<MealPhoto> = listOf(photo()),
                        id: UUID = UUID.randomUUID(), capturedAt: Instant = at, zone: String = "UTC") =
        CoachSubmissionPayload(id, text, photos, CoachCaptureContext(capturedAt, zone))

    private fun rows(table: String) =
        SQLiteDatabase.openDatabase(db.file, SQLiteDatabase.OpenParams.Builder().setJournalMode("DELETE").build()).use { other ->
            other.rawQuery("SELECT COUNT(*) FROM $table", null).use { it.moveToFirst(); it.getInt(0) }
        }

    @Test fun captureIsAcknowledgedOnlyAfterCommit() {
        val before = db.head()
        db.beforeCommit = { throw IllegalStateException("injected") }
        throws<IllegalStateException> { db.captureCoachSubmission(payload(), before.revision) }
        db.beforeCommit = null
        assertEquals(before, db.head())
        assertEquals(0, rows("coach_turn"))
        assertEquals(0, rows("coach_photo"))
    }

    @Test fun retryWithSameManifestReturnsSameTurn() {
        val p = payload()
        val turn = db.captureCoachSubmission(p, db.head().revision)
        assertEquals(CoachTurnState.captured, turn.state)
        assertEquals(p.manifest, turn.submissionManifest)
        val head = db.head()
        assertEquals(turn, db.captureCoachSubmission(p, head.revision))
        assertEquals(head, db.head())
        assertEquals(listOf(turn), db.snapshot().coachTurns)
    }

    @Test fun retryWithDifferentTextIsRejected() {
        val p = payload()
        db.captureCoachSubmission(p, db.head().revision)
        throws<DiaryError.StaleRevision> {
            db.captureCoachSubmission(payload("different", p.attachments, p.submissionID), db.head().revision)
        }
    }

    @Test fun captureContextMustMatchHead() {
        throws<DiaryError.StaleRevision> { db.captureCoachSubmission(payload(zone = "Asia/Jerusalem"), db.head().revision) }
        assertEquals(0, rows("coach_turn"))
    }

    @Test fun reconcileAfterUncertainFailure() {
        val p = payload()
        assertEquals(Reconciliation.Absent, db.reconcileCoachCapture(p))
        val turn = db.captureCoachSubmission(p, db.head().revision)
        assertEquals(Reconciliation.Accepted(turn), db.reconcileCoachCapture(p))
        assertEquals(Reconciliation.ConflictingPayload, db.reconcileCoachCapture(payload("other", p.attachments, p.submissionID)))
    }

    @Test fun pendingScanFindsCapturedTurnsAfterReopen() {
        val later = db.captureCoachSubmission(payload(capturedAt = at.plusSeconds(60)), db.head().revision)
        val earlier = db.captureCoachSubmission(payload(capturedAt = at), db.head().revision)
        val done = db.captureCoachSubmission(payload(), db.head().revision)
        db.transaction(db.head().revision) { it.putCoachTurn(done.copy(state = CoachTurnState.completed)) }
        db.close()
        db = DiaryDatabase.open(context, profile.id)
        assertEquals(listOf(earlier.id, later.id), db.pendingCoachTurns())
    }

    @Test fun emptyCaptureRejected() {
        throws<DiaryError.EmptyCapture> { payload(" \n\t", emptyList()) }
    }

    @Test fun nineAttachmentsRejected() {
        throws<DiaryError.InvalidData> { payload(photos = List(9) { photo() }) }
    }
}
