package com.yakov103.mivu.coach

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.test.core.app.ApplicationProvider
import com.yakov103.mivu.diary.CoachCaptureContext
import com.yakov103.mivu.diary.CoachSubmissionPayload
import com.yakov103.mivu.diary.CoachTurn
import com.yakov103.mivu.diary.CoachTurnState
import com.yakov103.mivu.diary.DiaryDatabase
import com.yakov103.mivu.diary.DiaryProfile
import com.yakov103.mivu.diary.DiaryRepository
import com.yakov103.mivu.diary.captureCoachSubmission
import com.yakov103.mivu.diary.failCoachTurn
import com.yakov103.mivu.diary.finishCoachTurn
import com.yakov103.mivu.analysis.ResponsesClient
import com.yakov103.mivu.diary.retryCoachTurn
import com.yakov103.mivu.diary.settleCoachTurn
import com.yakov103.mivu.diary.startDay
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException
import java.net.SocketTimeoutException
import java.time.Instant
import java.util.UUID
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/** Synthetic diaries and scripted inference only. */
class CoachWorkerTest {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val profile = DiaryProfile(UUID.randomUUID(), "Synthetic", "en", "UTC", "")
    private val at = Instant.parse("2026-10-24T12:00:00Z")
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private lateinit var repository: DiaryRepository
    private lateinit var db: DiaryDatabase
    private val sleeps = mutableListOf<Long>()

    @Before fun open() {
        File(context.filesDir, "profiles").deleteRecursively()
        DiaryDatabase.create(context, profile).close()
        repository = DiaryRepository(context)
        db = repository.database(profile.id)
        db.startDay(at, db.head().revision)
    }

    @After fun close() {
        db.close()
        File(context.filesDir, "profiles").deleteRecursively()
    }

    private fun turn(text: String): CoachTurn {
        val h = db.head()
        return db.captureCoachSubmission(CoachSubmissionPayload(UUID.randomUUID(), text, emptyList(),
            CoachCaptureContext(at, "UTC", h.activeDayID, h.previousDayConfirmedAt, h.activeConversationSegmentID)), h.revision)
    }
    private fun state(id: UUID) = db.read { it.coachTurnWithoutPhotos(id) }!!.state
    private fun answer() = CoachInferenceResult("fixture-model", "Synthetic answer.", emptyList(), emptyList())
    private fun worker(infer: suspend (List<CoachInferenceInput>, JsonObject) -> CoachInferenceResult) =
        bound { infer }

    private fun bound(bind: () -> suspend (List<CoachInferenceInput>, JsonObject) -> CoachInferenceResult) =
        CoachWorker(repository, bind, sleep = { sleeps += it }, scope = scope)

    @Test fun resumesPendingAfterRestart() = runBlocking {
        val interrupted = turn("Synthetic first")
        db.transaction(null) { it.failCoachTurn(interrupted.id, CoachTurnState.analyzing) }
        val later = turn("Synthetic second")
        val failed = turn("Synthetic third")
        db.transaction(null) { it.failCoachTurn(failed.id, CoachTurnState.needsRetry) }
        db.close()
        repository = DiaryRepository(context)
        db = repository.database(profile.id)
        val texts = mutableListOf<String>()
        worker { input, _ -> texts += (input.last() as CoachInferenceInput.Message).text; answer() }.drain(profile.id, true)!!.join()
        assertEquals(listOf("Synthetic first", "Synthetic second"), texts)
        assertEquals(CoachTurnState.completed, state(interrupted.id))
        assertEquals(CoachTurnState.completed, state(later.id))
        // A turn that needs a retry waits for the person; the worker does not loop on it.
        assertEquals(CoachTurnState.needsRetry, state(failed.id))
    }

    @Test fun transientBacksOff() = runBlocking {
        val recovers = turn("Synthetic first")
        val offline = turn("Synthetic second")
        val calls = AtomicInteger()
        // The first turn fails twice then answers; the second fails on every attempt.
        worker { _, _ -> if (calls.incrementAndGet() in setOf(1, 2) || calls.get() > 3) throw SocketTimeoutException() else answer() }
            .drain(profile.id, true)!!.join()
        assertEquals(CoachTurnState.completed, state(recovers.id))
        assertEquals(CoachTurnState.waitingForNetwork, state(offline.id))
        assertEquals(listOf(1_000L, 2_000L, 1_000L, 2_000L, 4_000L), sleeps)
        assertEquals(7, calls.get())
    }

    // iOS binds the connection once per turn; its retries reuse that binding instead of rebinding to a new model or account.
    @Test fun bindsOncePerTurnAcrossRetries() = runBlocking {
        val first = turn("Synthetic first")
        val second = turn("Synthetic second")
        val binds = AtomicInteger()
        val calls = AtomicInteger()
        bound {
            binds.incrementAndGet()
            ({ _, _ -> if (calls.incrementAndGet() == 1) throw SocketTimeoutException() else answer() })
        }.drain(profile.id, true)!!.join()
        assertEquals(CoachTurnState.completed, state(first.id))
        assertEquals(CoachTurnState.completed, state(second.id))
        assertEquals(2, binds.get())
        assertEquals(3, calls.get())
    }

    @Test fun duplicateDrainRequestsCoalesce() = runBlocking {
        val first = turn("Synthetic first")
        val started = CompletableDeferred<Unit>()
        val release = CompletableDeferred<Unit>()
        val calls = AtomicInteger()
        val worker = worker { _, _ -> calls.incrementAndGet(); started.complete(Unit); release.await(); answer() }
        val job = worker.drain(profile.id, true)!!
        started.await()
        // A turn saved during the running pass is picked up by the requested follow-up pass, not a second worker.
        val second = turn("Synthetic second")
        assertNull(worker.drain(profile.id, true))
        assertNull(worker.drain(profile.id, true))
        assertEquals(1, calls.get())
        release.complete(Unit)
        job.join()
        assertEquals(2, calls.get())
        assertEquals(CoachTurnState.completed, state(first.id))
        assertEquals(CoachTurnState.completed, state(second.id))
    }

    // A background job that finds a worker already running must hold the process open until that worker is done.
    @Test fun awaitIdleWaitsForTheRunningWorker() = runBlocking {
        val t = turn("Synthetic first")
        val started = CompletableDeferred<Unit>()
        val release = CompletableDeferred<Unit>()
        val worker = worker { _, _ -> started.complete(Unit); release.await(); answer() }
        worker.drain(profile.id, true)!!
        started.await()
        assertNull(worker.drain(profile.id, true))
        val idle = scope.launch { worker.awaitIdle() }
        delay(200)
        assertTrue(idle.isActive)
        release.complete(Unit)
        idle.join()
        assertEquals(CoachTurnState.completed, state(t.id))
    }

    // Retry on a turn the worker is running (or has finished) must not reset it to captured under the worker.
    @Test fun retryLeavesARunningOrFinishedTurnAlone() {
        val running = turn("Synthetic first")
        db.transaction(null) { it.failCoachTurn(running.id, CoachTurnState.analyzing) }
        val finished = turn("Synthetic second")
        db.transaction(null) { it.failCoachTurn(finished.id, CoachTurnState.completed) }
        db.retryCoachTurn(running.id)
        db.retryCoachTurn(finished.id)
        assertEquals(CoachTurnState.analyzing, state(running.id))
        assertEquals(CoachTurnState.completed, state(finished.id))
    }

    @Test fun diaryErrorEndsThePassAndLaterDrainsRun() = runBlocking {
        val worker = worker { _, _ -> answer() }
        // A profile with no diary: reading its head throws inside the pass.
        val broken = worker.drain(UUID.randomUUID(), true)!!
        broken.join()
        assertTrue(!broken.isCancelled)
        val t = turn("Synthetic first")
        worker.drain(profile.id, true)!!.join()
        assertEquals(CoachTurnState.completed, state(t.id))
    }

    @Test fun visionCopiesFitTheRequestBudget() = runBlocking {
        // Synthetic noise so JPEG cannot compress it far: about 5 MB at quality 100.
        val random = java.util.Random(7)
        val bitmap = Bitmap.createBitmap(3000, 2000, Bitmap.Config.ARGB_8888)
        bitmap.setPixels(IntArray(3000 * 2000) { random.nextInt() or (0xFF shl 24) }, 0, 3000, 0, 0, 3000, 2000)
        val large = ByteArrayOutputStream().also { bitmap.compress(Bitmap.CompressFormat.JPEG, 100, it) }.toByteArray()
        assertTrue(large.size > 4_194_304)
        val copies = visionCopies(listOf(large, large))
        assertEquals(2, copies.size)
        copies.forEach { copy ->
            assertTrue(copy.size <= 524_288)
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeByteArray(copy, 0, copy.size, bounds)
            assertTrue(maxOf(bounds.outWidth, bounds.outHeight) <= 1280)
            assertEquals("image/jpeg", CoachInferenceInput.imageMIME(copy))
        }
    }

    @Test fun stuckOldestTurnDoesNotHoldBackNewerCapture() = runBlocking {
        val stuck = turn("Synthetic offline")
        var newer: CoachTurn? = null
        val offlineCalls = AtomicInteger()
        lateinit var w: CoachWorker
        w = worker { input, _ ->
            if ((input.last() as CoachInferenceInput.Message).text != "Synthetic offline") return@worker answer()
            // A message saved while the oldest turn is failing asks the running worker for another pass.
            if (offlineCalls.incrementAndGet() == 1) { newer = turn("Synthetic newer"); assertNull(w.drain(profile.id, true)) }
            throw SocketTimeoutException()
        }
        w.drain(profile.id, true)!!.join()
        assertEquals(CoachTurnState.waitingForNetwork, state(stuck.id))
        assertEquals(CoachTurnState.completed, state(newer!!.id))
        assertEquals(4, offlineCalls.get()) // one resilient run; the follow-up pass skips the stuck turn
    }

    @Test fun activityReportsPhases() = runBlocking {
        val t = turn("Synthetic first")
        val seen = mutableListOf<Pair<UUID, CoachActivity>?>()
        lateinit var w: CoachWorker
        w = worker { _, _ -> seen += w.activity.value; answer() }
        w.drain(profile.id, true)!!.join()
        assertEquals(listOf(t.id to CoachActivity.thinking), seen)
        assertNull(w.activity.value)
    }

    @Test fun stuckTurnDoesNotHoldBackLaterWorker() = runBlocking {
        val stuck = turn("Synthetic offline")
        val offlineCalls = AtomicInteger()
        val w = worker { input, _ ->
            if ((input.last() as CoachInferenceInput.Message).text != "Synthetic offline") return@worker answer()
            offlineCalls.incrementAndGet(); throw SocketTimeoutException()
        }
        w.drain(profile.id, true)!!.join()
        assertEquals(CoachTurnState.waitingForNetwork, state(stuck.id))
        // The worker has exited; a new message starts a new worker, which must not retry the stuck turn first.
        val newer = turn("Synthetic newer")
        w.drain(profile.id, true)!!.join()
        assertEquals(CoachTurnState.completed, state(newer.id))
        assertEquals(4, offlineCalls.get())
        // A network change lets the stuck turn run again.
        w.drain(profile.id, true, retryWaiting = true)!!.join()
        assertEquals(8, offlineCalls.get())
    }

    private fun turnRow(id: UUID) = db.read { it.coachTurnWithoutPhotos(id) }!!

    @Test fun unrecordedFailureAfterSavedFoodEndsWithItsSummary() = runBlocking {
        val t = turn("Synthetic toast")
        val log = CoachToolCall("fc_log", "call_log", "log_food", "mivu",
            """{"target_local_date":"2026-10-24","items":[{"name":"Synthetic toast","quantity":1,"unit":"piece","kcal":530,"carbs":null,"protein":null,"fat":null}]}""")
        val rounds = mutableListOf(CoachInferenceResult("fixture-model", "", listOf(log), emptyList()), answer())
        CoachEngine(db, { _, _ -> rounds.removeAt(0) }).run(t.id)
        // The engine's failure write was lost: the turn still reads as running.
        db.transaction(null) { it.failCoachTurn(t.id, CoachTurnState.analyzing) }
        db.settleCoachTurn(t.id, IOException())
        val settled = turnRow(t.id)
        assertEquals(CoachTurnState.completed, settled.state)
        assertEquals(true, settled.incomplete)
        assertTrue(settled.assistantText != null)
        assertEquals(1, settled.receipts.size)
    }

    @Test fun unrecordedFailureWithoutSavedFoodOffersTryAgain() {
        val t = turn("Synthetic first")
        db.transaction(null) { it.failCoachTurn(t.id, CoachTurnState.analyzing) }
        db.settleCoachTurn(t.id, IOException())
        assertEquals(CoachTurnState.needsRetry, state(t.id))
        assertEquals("IOException", turnRow(t.id).failureReason)
    }

    @Test fun settleLeavesAFinishedTurnAlone() {
        val finished = turn("Synthetic first")
        db.transaction(null) { it.finishCoachTurn(finished.id, "Synthetic answer.") }
        val waiting = turn("Synthetic second")
        db.transaction(null) { it.failCoachTurn(waiting.id, CoachTurnState.waitingForNetwork) }
        val before = listOf(turnRow(finished.id), turnRow(waiting.id))
        db.settleCoachTurn(finished.id, IOException())
        db.settleCoachTurn(waiting.id, IOException())
        assertEquals(before, listOf(turnRow(finished.id), turnRow(waiting.id)))
    }

    @Test fun workerSettlesATurnLeftAnalyzing() = runBlocking {
        val t = turn("Synthetic first")
        val settled = mutableListOf<Pair<UUID, CoachTurnState>>()
        val spy: (DiaryDatabase, UUID, Throwable) -> Unit = { d, id, _ -> settled += id to d.read { it.coachTurnWithoutPhotos(id) }!!.state }
        CoachWorker(repository, { { _, _ -> throw ResponsesClient.Failure.Http(500) } }, sleep = { }, scope = scope, settle = spy)
            .drain(profile.id, true)!!.join()
        // Called once, after the engine recorded its own failure.
        assertEquals(listOf(t.id to CoachTurnState.waitingForNetwork), settled)
        settled.clear()
        val other = turn("Synthetic second")
        CoachWorker(repository, { throw CoachError.ConnectionRequired }, sleep = { }, scope = scope, settle = spy)
            .drain(profile.id, true)!!.join()
        assertTrue(settled.isEmpty())
        assertEquals(CoachTurnState.captured, state(other.id))
    }
}
