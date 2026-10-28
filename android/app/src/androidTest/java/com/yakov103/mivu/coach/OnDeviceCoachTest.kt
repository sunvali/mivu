package com.yakov103.mivu.coach

import android.app.NotificationManager
import android.app.job.JobScheduler
import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.yakov103.mivu.MivuApplication
import com.yakov103.mivu.analysis.LocalTurn
import com.yakov103.mivu.analysis.NutritionTable
import com.yakov103.mivu.analysis.OnDeviceFailure
import com.yakov103.mivu.analysis.OnDeviceModel
import com.yakov103.mivu.connection.CoachProvider
import com.yakov103.mivu.diary.Bootstrap
import com.yakov103.mivu.diary.CoachCaptureContext
import com.yakov103.mivu.diary.CoachSubmissionPayload
import com.yakov103.mivu.diary.CoachTurn
import com.yakov103.mivu.diary.CoachTurnState
import com.yakov103.mivu.diary.DiaryDatabase
import com.yakov103.mivu.diary.captureCoachSubmission
import com.yakov103.mivu.diary.startDay
import com.yakov103.mivu.diary.undoCoachChange
import com.yakov103.mivu.ui.today.TodayFixture
import java.time.Instant
import java.time.temporal.ChronoUnit
import java.util.UUID
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.BeforeClass
import org.junit.Test

/** The real on-device path (OnDeviceInference and the bundled table) with a scripted model; synthetic diary and text only. */
class OnDeviceCoachTest {
    private val app: MivuApplication = ApplicationProvider.getApplicationContext()
    private lateinit var db: DiaryDatabase
    private val model = Fake()

    private class Fake : OnDeviceModel {
        @Volatile var paused = false
        override suspend fun turn(text: String, images: List<ByteArray>): LocalTurn {
            if (paused) throw OnDeviceFailure.Paused
            return when {
                "eggs" in text -> LocalTurn(LocalTurn.Intent.log, listOf(LocalTurn.Food("Eggs", "egg", 2.0, "piece", kcal = 140.0, protein = 12.0, fat = 10.0)))
                "make it 3" in text -> LocalTurn(LocalTurn.Intent.edit, editQuantity = 3.0)
                else -> LocalTurn(LocalTurn.Intent.other)
            }
        }
        override suspend fun pick(phrase: String, options: List<NutritionTable.Food>) = 0 // keep the model's estimate
    }

    companion object {
        @BeforeClass @JvmStatic fun fresh() {
            val context: Context = ApplicationProvider.getApplicationContext()
            TodayFixture.wipe(context)
            TodayFixture.diary(context)
        }
    }

    @Before fun open() = runBlocking {
        db = app.repository.database((app.repository.bootstrap() as Bootstrap.Ready).profileID)
        if (db.head().activeDayID == null) db.startDay(Instant.now(), db.head().revision)
        app.chatGPT.onDeviceForTest = model
        app.chatGPT.choose(CoachProvider.onDevice)
        app.foregroundForTest = true
        drain() // turns left by earlier tests finish first
    }

    @After fun close() {
        app.foregroundForTest = null
        app.chatGPT.choose(CoachProvider.chatGPT)
        app.getSharedPreferences("chatgpt", Context.MODE_PRIVATE).edit().remove("aiProvider").commit()
        app.chatGPT.onDeviceForTest = null
        app.getSystemService(JobScheduler::class.java).cancelAll()
    }

    private fun drain(retryWaiting: Boolean = true) = runBlocking { withTimeout(30_000) { app.drainCoach(retryWaiting).join() } }
    private fun stored(id: UUID) = db.read { it.coachTurnWithoutPhotos(id) }!!
    private fun send(text: String): CoachTurn {
        val h = db.head()
        return db.captureCoachSubmission(CoachSubmissionPayload(UUID.randomUUID(), text, emptyList(),
            CoachCaptureContext(Instant.now().truncatedTo(ChronoUnit.SECONDS), h.profile.timeZoneID, h.activeDayID,
                h.previousDayConfirmedAt, h.activeConversationSegmentID)), h.revision)
    }

    @Test fun logsAndUndoes() {
        val t = send("Synthetic 2 eggs")
        drain(false)
        val receipt = stored(t.id).also { assertEquals(CoachTurnState.completed, it.state) }.receipts.single()
        val meal = db.read { it.meal(receipt.mealID!!) }!!
        assertEquals(listOf("gemini-nano"), meal.items.map { it.estimatedBy })
        db.undoCoachChange(receipt.operationKey)
        assertNull(db.read { it.meal(meal.id) })
    }

    @Test fun correctsLatest() {
        val logged = send("Synthetic 2 eggs")
        drain(false)
        val mealID = stored(logged.id).receipts.single().mealID!!
        val edit = send("Synthetic make it 3")
        drain(false)
        assertEquals(CoachTurnState.completed, stored(edit.id).state)
        assertEquals(listOf(3.0), db.read { it.meal(mealID) }!!.items.map { it.quantity })
    }

    @Test fun otherRepliesNothingToChange() {
        val t = send("Synthetic hello there")
        drain(false)
        val done = stored(t.id)
        assertEquals(CoachTurnState.completed, done.state)
        assertTrue(done.receipts.isEmpty())
        assertEquals("Nothing to change.", done.assistantText)
    }

    @Test fun pausedTurnWaitsAndResumes() {
        model.paused = true
        val t = send("Synthetic 2 eggs")
        drain(false) // retries after 1, 2 and 4 seconds, then waits
        val waiting = stored(t.id)
        assertEquals(CoachTurnState.waitingForNetwork, waiting.state)
        assertEquals("OnDevice.Paused", waiting.failureReason)
        model.paused = false
        drain(true)
        assertEquals(CoachTurnState.completed, stored(t.id).state)
    }

    @Test fun backgroundDoesNotDrain() {
        app.foregroundForTest = false
        val t = send("Synthetic 2 eggs")
        drain(true)
        assertEquals(CoachTurnState.captured, stored(t.id).state)
    }

    @Test fun tellCoachOnDevice() {
        app.foregroundForTest = false // as from the share sheet once it closes
        val id = UUID.randomUUID()
        assertEquals(TellCoachOutcome.SavedOpenToFinish, runBlocking { TellCoach.run(app, "Synthetic 2 eggs", emptyList(), id) })
        assertEquals("Saved. Pip will finish when you open Mivu.", TellCoachOutcome.SavedOpenToFinish.line)
        assertEquals(CoachTurnState.captured, stored(id).state)
        assertTrue(app.getSystemService(JobScheduler::class.java).allPendingJobs.isEmpty())
        val tags = app.getSystemService(NotificationManager::class.java).activeNotifications.map { it.tag }
        assertTrue("coach-reply-$id" !in tags)
    }

    @Test fun coldStartShareWaitsForTheNanoCheck() {
        app.foregroundForTest = false
        app.chatGPT.onDeviceForTest = null // the launch check has not reported yet
        app.nanoChecked = app.scope.launch { delay(500); app.chatGPT.onDeviceForTest = model }
        val id = UUID.randomUUID()
        assertEquals(TellCoachOutcome.SavedOpenToFinish, runBlocking { TellCoach.run(app, "Synthetic 2 eggs", emptyList(), id) })
        assertTrue(app.getSystemService(JobScheduler::class.java).allPendingJobs.isEmpty())
        assertEquals(CoachTurnState.captured, stored(id).state)
    }

    @Test fun slowNanoCheckDoesNotHoldACapture() {
        app.foregroundForTest = false
        app.chatGPT.onDeviceForTest = null
        val slow = app.scope.launch { delay(60_000) }
        app.nanoChecked = slow
        try {
            val started = System.nanoTime()
            // Not known in time: Nano counts as not available, so the turn waits for a connection.
            assertEquals(TellCoachOutcome.SavedNeedsConnection, runBlocking { TellCoach.run(app, "Synthetic pear", emptyList(), UUID.randomUUID()) })
            assertTrue((System.nanoTime() - started) / 1_000_000 < 5_000)
        } finally {
            slow.cancel()
        }
    }
}
