package com.yakov103.mivu.diary

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import androidx.test.core.app.ApplicationProvider
import java.io.ByteArrayOutputStream
import java.io.File
import java.time.Instant
import java.util.UUID
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
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

    @Test fun newTurnPastTheTenThousandCapIsRejected() {
        // Bulk insert through import, then capture one more (iOS appendCapture: ordinal < 10_000).
        val turns = List(10_000) {
            CoachTurn(UUID.randomUUID(), at, "synthetic", emptyList(), CoachTurnState.completed, receipts = emptyList(), captureTimeZoneID = "UTC",
                photoIDs = emptyList())
        }
        db.replaceAll(db.snapshot().copy(coachTurns = turns))
        val before = db.head()
        throws<DiaryError.InvalidData> { db.captureCoachSubmission(payload(), before.revision) }
        assertEquals(before, db.head())
        assertEquals(10_000, rows("coach_turn"))
        db.transaction(before.revision) { it.putCoachTurn(turns[0].copy(state = CoachTurnState.needsRetry)) } // updates still allowed
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

    @Test fun subSecondRetryReturnsSameTurn() {
        val fine = Instant.parse("2026-10-24T12:00:00.123456789Z")
        val p = payload(photos = listOf(photo().copy(createdAt = fine.plusNanos(7))), capturedAt = fine)
        val turn = db.captureCoachSubmission(p, db.head().revision)
        db.close()
        db = DiaryDatabase.open(context, profile.id)
        val head = db.head()
        assertEquals(turn, db.captureCoachSubmission(p, head.revision))
        assertEquals(head, db.head())
        assertEquals(Reconciliation.Accepted(turn), db.reconcileCoachCapture(p))
    }

    @Test fun updateCoachTurnSetsStateAndText() {
        val turn = db.captureCoachSubmission(payload(), db.head().revision)
        db.transaction(db.head().revision) {
            it.updateCoachTurn(turn.id, CoachTurnState.needsClarification, "Which day?", incomplete = true, needsDayChoice = true)
        }
        var stored = db.coachTurn(turn.id)!!
        assertEquals(CoachTurnState.needsClarification, stored.state)
        assertEquals("Which day?", stored.assistantText)
        assertEquals(true, stored.incomplete)
        assertEquals(true, stored.needsDayChoice)
        // A day choice only belongs to a clarification; any other state clears it and the text.
        db.transaction(db.head().revision) { it.failCoachTurn(turn.id, CoachTurnState.needsRetry, needsDayChoice = true) }
        stored = db.coachTurn(turn.id)!!
        assertEquals(CoachTurnState.needsRetry, stored.state)
        assertNull(stored.assistantText)
        assertNull(stored.incomplete)
        assertNull(stored.needsDayChoice)
        val head = db.head()
        throws<DiaryError.NotFound> { db.transaction(head.revision) { it.failCoachTurn(UUID.randomUUID(), CoachTurnState.needsRetry) } }
        assertEquals(head, db.head())
    }

    @Test fun finishIncompleteKeepsReceipts() {
        val turn = db.captureCoachSubmission(payload(), db.head().revision)
        val receipt = CoachReceipt("${turn.id.toString().uppercase()}/open_settings", turn.id, destination = CoachDestination.settings,
            committedRevision = db.head().revision.toInt(), resultJSON = "{}")
        db.transaction(db.head().revision) { it.putCoachTurn(it.coachTurn(turn.id)!!.copy(state = CoachTurnState.analyzing, receipts = listOf(receipt))) }
        db.transaction(db.head().revision) { it.finishCoachTurn(turn.id, "Opened Settings; the rest needs another try.", incomplete = true) }
        val stored = db.coachTurn(turn.id)!!
        assertEquals(CoachTurnState.completed, stored.state)
        assertEquals("Opened Settings; the rest needs another try.", stored.assistantText)
        assertEquals(true, stored.incomplete)
        assertEquals(listOf(receipt), stored.receipts)
        // Completing again without new text keeps the finished reply, as iOS setCoachTurnState.
        db.transaction(db.head().revision) { it.failCoachTurn(turn.id, CoachTurnState.completed) }
        assertEquals(stored, db.coachTurn(turn.id))
    }

    @Test fun undoRowIsNotArchived() {
        val day = db.startDay(at, db.head().revision)
        val item = FoodItem(UUID.randomUUID(), "synthetic rice", 100.0, "g", NutritionValues(kcal = 130.0),
            NutritionProvenance.estimate, "", false, emptyMap())
        val meal = DiaryMeal(UUID.randomUUID(), day.id, at, at, 1, items = listOf(item), photos = emptyList(), submissions = emptyList())
        db.transaction(db.head().revision) { it.putMeal(meal) }
        val h = db.head()
        val turn = db.captureCoachSubmission(CoachSubmissionPayload(UUID.randomUUID(), "synthetic lunch", emptyList(),
            CoachCaptureContext(at, "UTC", h.activeDayID, h.previousDayConfirmedAt, h.activeConversationSegmentID)), h.revision)
        val key = "${turn.id.toString().uppercase()}/synthetic-undo-key"
        val head = db.head()
        db.transaction(head.revision) { it.saveUndo(key, turn.id, meal.id, listOf(item)) }
        assertEquals(head, db.head()) // derived state: no revision
        val undo = db.read { it.coachUndo(key) }!!
        assertEquals(meal.id, undo.mealID)
        assertEquals(1, undo.afterRevision)
        assertEquals(listOf(item), undo.before)
        assertFalse(undo.undone)
        assertEquals(1, rows("coach_undo"))
        val out = ByteArrayOutputStream().also { DiaryArchive.encode(db.snapshot(), it) }.toString()
        assertTrue(turn.id.toString().uppercase() in out)
        assertFalse("synthetic-undo-key" in out)
        // Survives reopening: the table is created outside the version gate.
        db.close()
        db = DiaryDatabase.open(context, profile.id)
        assertEquals(undo, db.read { it.coachUndo(key) })
    }

    @Test fun acceptedTurnIdentityIsImmutable() {
        val turn = db.captureCoachSubmission(payload(), db.head().revision)
        val stored = db.coachTurn(turn.id)!!
        val changes = listOf<(CoachTurn) -> CoachTurn>(
            { it.copy(submissionManifest = it.submissionManifest!!.copy(textFingerprint = fingerprint("other"))) },
            { it.copy(capturedAt = it.capturedAt.plusSeconds(1)) },
            { it.copy(captureTimeZoneID = "Asia/Jerusalem") },
            { it.copy(activeDayID = UUID.randomUUID()) },
            { it.copy(text = "synthetic edit") },
            { it.copy(captureSegmentID = UUID.randomUUID()) },
        )
        for (change in changes) {
            val head = db.head()
            throws<DiaryError.StaleRevision> { db.transaction(head.revision) { it.putCoachTurn(change(stored)) } }
            assertEquals(head, db.head())
            assertEquals(stored, db.coachTurn(turn.id))
        }
        val receipt = CoachReceipt("${turn.id.toString().uppercase()}/open_settings", turn.id, destination = CoachDestination.settings,
            committedRevision = db.head().revision.toInt(), resultJSON = "{}")
        val progressed = stored.copy(state = CoachTurnState.completed, assistantText = "Done.", receipts = listOf(receipt))
        db.transaction(db.head().revision) { it.putCoachTurn(progressed) }
        assertEquals(progressed, db.coachTurn(turn.id))
    }

    @Test fun progressUpdateKeepsPhotoRows() {
        val turn = db.captureCoachSubmission(payload(photos = listOf(photo(), photo())), db.head().revision)
        // Any rewrite of the photo rows deletes them first; this trigger makes that fail the update.
        SQLiteDatabase.openDatabase(db.file, SQLiteDatabase.OpenParams.Builder().setJournalMode("DELETE").build()).use {
            it.execSQL("CREATE TRIGGER keep_photos BEFORE DELETE ON coach_photo BEGIN SELECT RAISE(ABORT, 'photo rewritten'); END")
        }
        db.transaction(db.head().revision) { it.updateCoachTurn(turn.id, CoachTurnState.analyzing, null) }
        db.transaction(db.head().revision) { it.failCoachTurn(turn.id, CoachTurnState.needsRetry) }
        db.transaction(db.head().revision) { it.finishCoachTurn(turn.id, "Logged.") }
        val stored = db.coachTurn(turn.id)!!
        assertEquals(turn.photos, stored.photos)
        assertEquals(CoachTurnState.completed, stored.state)
    }

    @Test fun finishRoundTripsQuestionAndDayChoice() {
        val turn = db.captureCoachSubmission(payload(), db.head().revision)
        val question = CoachQuestion(CoachClarification.meal, listOf(CoachReply.Target.Message(turn.id, false)), "synthetic lunch")
        db.transaction(db.head().revision) {
            it.updateCoachTurn(turn.id, CoachTurnState.needsClarification, "Which meal?", question, needsDayChoice = true)
        }
        db.close()
        db = DiaryDatabase.open(context, profile.id)
        var stored = db.coachTurn(turn.id)!!
        assertEquals(question, stored.question)
        assertEquals(true, stored.needsDayChoice)
        db.transaction(db.head().revision) { it.finishCoachTurn(turn.id, "Which one did you mean?", question, incomplete = true) }
        stored = db.coachTurn(turn.id)!!
        assertEquals(CoachTurnState.completed, stored.state)
        assertEquals(question, stored.question)
        assertNull(stored.needsDayChoice) // a day choice only belongs to a clarification
        db.transaction(db.head().revision) { it.finishCoachTurn(turn.id, "Logged.") }
        stored = db.coachTurn(turn.id)!!
        assertNull(stored.question)
        assertNull(stored.incomplete)
    }

    @Test fun emptyCaptureRejected() {
        throws<DiaryError.EmptyCapture> { payload(" \n\t", emptyList()) }
    }

    @Test fun nineAttachmentsRejected() {
        throws<DiaryError.InvalidData> { payload(photos = List(9) { photo() }) }
    }
}
