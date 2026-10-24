package com.yakov103.mivu.coach

import android.app.job.JobInfo
import android.app.job.JobScheduler
import android.os.ParcelFileDescriptor
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.platform.app.InstrumentationRegistry
import com.yakov103.mivu.MainActivity
import com.yakov103.mivu.MivuApplication
import com.yakov103.mivu.diary.Bootstrap
import com.yakov103.mivu.diary.CoachCaptureContext
import com.yakov103.mivu.diary.CoachSubmissionPayload
import com.yakov103.mivu.diary.CoachTurn
import com.yakov103.mivu.diary.CoachTurnState
import com.yakov103.mivu.diary.DiaryDatabase
import com.yakov103.mivu.diary.captureCoachSubmission
import com.yakov103.mivu.diary.startDay
import java.io.File
import java.time.Instant
import java.util.UUID
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.BeforeClass
import org.junit.Test

/** Synthetic diary and scripted inference only; the job is forced and stopped through `cmd jobscheduler`. */
class CoachJobServiceTest {
    private val app: MivuApplication = ApplicationProvider.getApplicationContext()
    private val jobs = app.getSystemService(JobScheduler::class.java)
    private lateinit var db: DiaryDatabase
    private var gate = CompletableDeferred<Unit>().apply { complete(Unit) }
    private val calls = AtomicInteger()

    companion object {
        private var today = ""

        // Before anything opens the app's diary, so the repository bootstraps a fresh synthetic one.
        @BeforeClass @JvmStatic fun fresh() {
            File(ApplicationProvider.getApplicationContext<MivuApplication>().filesDir, "profiles").deleteRecursively()
        }
    }

    @Before fun open() = runBlocking {
        jobs.cancelAll()
        // Each round waits on the gate; the first logs a meal, the next answers, so a finished turn has one receipt.
        app.coachInferenceForTest = {
            { input, _ ->
                gate.await()
                calls.incrementAndGet()
                if (input.last() is CoachInferenceInput.FunctionOutput) CoachInferenceResult("fixture-model", "Logged.", emptyList(), emptyList())
                else logFood()
            }
        }
        val ready = (app.repository.bootstrapState.value ?: app.repository.bootstrap()) as Bootstrap.Ready
        db = app.repository.database(ready.profileID)
        if (db.head().activeDayID == null) today = db.startDay(Instant.now(), db.head().revision).localDate
        app.drainCoach(retryWaiting = true).join() // finishes anything an earlier test left
        calls.set(0)
    }

    @After fun close() = runBlocking {
        gate.complete(Unit)
        withTimeout(10_000) { app.drainCoach(retryWaiting = true).join() }
        jobs.cancelAll()
        app.coachInferenceForTest = null
    }

    private fun logFood(): CoachInferenceResult {
        val arguments = """{"target_local_date":"$today","items":[{"name":"Synthetic toast","quantity":1,"unit":"piece","kcal":90,"carbs":null,"protein":null,"fat":null}]}"""
        val call = CoachToolCall("fc_log", "call_log", "log_food", "mivu", arguments)
        return CoachInferenceResult("fixture-model", "", listOf(call), listOf(buildJsonObject {
            put("type", "function_call"); put("id", call.id); put("call_id", call.callID); put("name", call.name)
            put("namespace", "mivu"); put("arguments", call.arguments); put("status", "completed")
        }.toString()))
    }

    private fun turn(text: String): CoachTurn {
        val h = db.head()
        return db.captureCoachSubmission(CoachSubmissionPayload(UUID.randomUUID(), text, emptyList(),
            CoachCaptureContext(Instant.now(), h.profile.timeZoneID, h.activeDayID, h.previousDayConfirmedAt, h.activeConversationSegmentID)), h.revision)
    }
    private fun stored(id: UUID) = db.read { it.coachTurnWithoutPhotos(id) }!!
    private fun shell(command: String) {
        ParcelFileDescriptor.AutoCloseInputStream(InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand(command))
            .use { it.readBytes() }
    }
    private suspend fun until(timeoutMs: Long = 10_000, check: () -> Boolean) = withTimeout(timeoutMs) { while (!check()) delay(50) }
    private fun pending(): JobInfo? = jobs.getPendingJob(MivuApplication.COACH_JOB)

    @Test fun stopWithPendingTurnSchedulesExpeditedJob() = runBlocking {
        gate = CompletableDeferred()
        val t = turn("Synthetic breakfast")
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            app.drainCoach() // as a send would; the turn then waits on the gate
            until { stored(t.id).state == CoachTurnState.analyzing }
            scenario.moveToState(Lifecycle.State.CREATED)
            until { pending() != null }
            val job = pending()!!
            assertTrue(job.isExpedited)
            assertNotNull(job.requiredNetwork)
        }
    }

    @Test fun stopWithNothingPendingSchedulesNothing() = runBlocking {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.moveToState(Lifecycle.State.CREATED)
            delay(2_000)
            assertNull(pending())
        }
    }

    @Test fun jobFinishesPendingTurn() = runBlocking {
        val t = turn("Synthetic lunch")
        app.scheduleBackgroundDrain()
        shell("cmd jobscheduler run -f ${app.packageName} ${MivuApplication.COACH_JOB}")
        until { stored(t.id).state == CoachTurnState.completed }
        until { pending() == null } // jobFinished without a reschedule
        assertEquals(1, stored(t.id).receipts.size)
    }

    @Test fun stoppedJobLeavesTurnPendingAndRelaunchResumes() = runBlocking {
        gate = CompletableDeferred()
        val before = db.coachTurnsWithoutPhotos().size
        val t = turn("Synthetic dinner")
        app.scheduleBackgroundDrain()
        shell("cmd jobscheduler run -f ${app.packageName} ${MivuApplication.COACH_JOB}")
        until { stored(t.id).state == CoachTurnState.analyzing }
        shell("cmd jobscheduler timeout ${app.packageName} ${MivuApplication.COACH_JOB}")
        delay(500)
        assertNotNull(pending()) // onStopJob asked for a reschedule
        assertNotEquals(CoachTurnState.completed, stored(t.id).state)
        assertTrue(stored(t.id).state in setOf(CoachTurnState.analyzing, CoachTurnState.captured))
        assertEquals(before + 1, db.coachTurnsWithoutPhotos().size)
        gate.complete(Unit)
        app.drainCoach().join()
        until { stored(t.id).state == CoachTurnState.completed }
        assertEquals(before + 1, db.coachTurnsWithoutPhotos().size)
        assertEquals(1, stored(t.id).receipts.size)
        assertEquals(2, calls.get()) // one log round and one answer: the stopped job ran no second copy
    }
}
