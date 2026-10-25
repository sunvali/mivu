package com.yakov103.mivu.coach

import android.Manifest
import android.app.Notification
import android.app.NotificationManager
import android.app.job.JobScheduler
import android.content.Context
import android.os.ParcelFileDescriptor
import android.service.notification.StatusBarNotification
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isHeading
import androidx.compose.ui.test.junit4.v2.createEmptyComposeRule
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry
import androidx.test.runner.lifecycle.Stage
import com.yakov103.mivu.MainActivity
import com.yakov103.mivu.MivuApplication
import com.yakov103.mivu.diary.Bootstrap
import com.yakov103.mivu.diary.CoachTurnState
import com.yakov103.mivu.diary.DiaryDatabase
import com.yakov103.mivu.diary.startDay
import com.yakov103.mivu.quick.QuickAction
import com.yakov103.mivu.quick.quickIntent
import com.yakov103.mivu.ui.today.TodayFixture
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.BeforeClass
import org.junit.Rule
import org.junit.Test

/** Synthetic diary and messages; scripted inference only, so no ChatGPT call. A share is `TellCoach.run`, as the sheet calls it. */
class CoachReplyFollowTest {
    @get:Rule val compose = createEmptyComposeRule()
    private val app: MivuApplication = ApplicationProvider.getApplicationContext()
    private val manager = app.getSystemService(NotificationManager::class.java)
    private val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
    private lateinit var db: DiaryDatabase
    private var gate = CompletableDeferred<Unit>().apply { complete(Unit) }
    private val reply = "Synthetic reply: noted your **soup**."

    companion object {
        @BeforeClass @JvmStatic fun fresh() {
            val context: Context = ApplicationProvider.getApplicationContext()
            TodayFixture.wipe(context)
            TodayFixture.diary(context)
        }
    }

    @Before fun open() = runBlocking<Unit> {
        automation.grantRuntimePermission(app.packageName, Manifest.permission.POST_NOTIFICATIONS)
        val ready = (app.repository.bootstrapState.value ?: app.repository.bootstrap()) as Bootstrap.Ready
        db = app.repository.database(ready.profileID)
        if (db.head().activeDayID == null) db.startDay(Instant.now(), db.head().revision)
        app.coachInferenceForTest = { { _, _ -> gate.await(); CoachInferenceResult("fixture-model", reply, emptyList(), emptyList()) } }
        TellCoach.canInferForTest = true
        withTimeout(10_000) { app.drainCoach(retryWaiting = true).join() }
        manager.cancelAll()
    }

    @After fun close() = runBlocking<Unit> {
        gate.complete(Unit)
        withTimeout(10_000) { app.drainCoach(retryWaiting = true).join() }
        TellCoach.canInferForTest = null
        app.coachInferenceForTest = null
        app.getSystemService(JobScheduler::class.java).cancelAll()
        manager.cancelAll()
        automation.grantRuntimePermission(app.packageName, Manifest.permission.POST_NOTIFICATIONS)
    }

    private fun shell(command: String) = ParcelFileDescriptor.AutoCloseInputStream(automation.executeShellCommand(command))
        .use { String(it.readBytes()) }
    private suspend fun until(timeoutMs: Long = 15_000, check: () -> Boolean) = withTimeout(timeoutMs) { while (!check()) delay(50) }
    private fun replies(): List<StatusBarNotification> = manager.activeNotifications.filter { it.tag?.startsWith("coach-reply-") == true }
    private fun body(n: StatusBarNotification) = n.notification.extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()
    private fun share(text: String): UUID = UUID.randomUUID().also {
        assertEquals(TellCoachOutcome.Sent, runBlocking { TellCoach.run(app, text, emptyList(), it) })
    }

    @Test fun backgroundReplyPostsOnceAndOpensCoach() = runBlocking<Unit> {
        app.startActivity(quickIntent(app, QuickAction.Today))
        until { app.screenVisible }
        shell("input keyevent KEYCODE_HOME") // Mivu leaves the screen, as when sharing from another app
        until { !app.screenVisible }
        val id = share("Synthetic soup for lunch")
        until { id !in app.followed }
        val posted = replies().single()
        assertEquals("coach-reply-$id", posted.tag)
        assertEquals(0, posted.id)
        assertEquals("Coach", posted.notification.extras.getCharSequence(Notification.EXTRA_TITLE).toString())
        assertEquals("Synthetic reply: noted your soup.", body(posted))
        assertTrue(posted.notification.flags and Notification.FLAG_AUTO_CANCEL != 0)
        posted.notification.contentIntent.send()
        compose.waitUntil(15_000) { runCatching { compose.onAllNodes(hasText("Coach") and isHeading()).fetchSemanticsNodes().isNotEmpty() }.getOrDefault(false) }
        assertTrue(app.screenVisible)
        InstrumentationRegistry.getInstrumentation().runOnMainSync {
            ActivityLifecycleMonitorRegistry.getInstance().getActivitiesInStage(Stage.RESUMED).forEach { it.finish() }
        }
    }

    @Test fun noNotificationWhileMivuIsOnScreen() = runBlocking<Unit> {
        ActivityScenario.launch(MainActivity::class.java).use {
            val id = share("Synthetic apple")
            until { id !in app.followed }
            assertEquals(CoachTurnState.completed, db.coachTurn(id)!!.state)
            assertEquals(emptyList<StatusBarNotification>(), replies())
        }
    }

    @Test fun stoppedJobPostsTheSavedNote() = runBlocking<Unit> {
        gate = CompletableDeferred()
        val id = share("Synthetic dinner")
        shell("cmd jobscheduler run -f ${app.packageName} ${MivuApplication.COACH_JOB}")
        until { shell("cmd jobscheduler get-job-state ${app.packageName} ${MivuApplication.COACH_JOB}").contains("active") }
        until { db.coachTurn(id)!!.state == CoachTurnState.analyzing }
        shell("cmd jobscheduler timeout ${app.packageName} ${MivuApplication.COACH_JOB}")
        until { replies().isNotEmpty() }
        assertEquals("Your message is saved. Open Mivu for the Coach's reply.", body(replies().single()))
        gate.complete(Unit)
        until { body(replies().single()) == "Synthetic reply: noted your soup." } // the reply replaces the note
        assertEquals("coach-reply-$id", replies().single().tag)
    }
}
