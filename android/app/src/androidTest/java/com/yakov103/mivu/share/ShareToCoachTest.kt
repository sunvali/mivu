package com.yakov103.mivu.share

import android.Manifest
import android.app.NotificationManager
import android.app.job.JobScheduler
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Color
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.MediaStore
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertTextContains
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.v2.createEmptyComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.SavedStateHandle
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.platform.app.InstrumentationRegistry
import com.yakov103.mivu.MivuApplication
import com.yakov103.mivu.coach.CoachInferenceResult
import com.yakov103.mivu.coach.TellCoach
import com.yakov103.mivu.diary.Bootstrap
import com.yakov103.mivu.diary.CoachTurnState
import com.yakov103.mivu.diary.DiaryDatabase
import com.yakov103.mivu.diary.DiaryRepository
import com.yakov103.mivu.diary.startDay
import com.yakov103.mivu.ui.theme.MivuTheme
import com.yakov103.mivu.ui.today.TodayFixture
import java.io.File
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Before
import org.junit.BeforeClass
import org.junit.Rule
import org.junit.Test

/** Synthetic text and generated JPEGs (inserted as this app's own MediaStore images); scripted inference only. */
class ShareToCoachTest {
    @get:Rule val compose = createEmptyComposeRule()
    private val app: MivuApplication = ApplicationProvider.getApplicationContext()
    private lateinit var db: DiaryDatabase
    private val inserted = mutableListOf<Uri>()

    companion object {
        @BeforeClass @JvmStatic fun fresh() {
            val context: Context = ApplicationProvider.getApplicationContext()
            TodayFixture.wipe(context)
            TodayFixture.diary(context)
        }
    }

    @Before fun open() = runBlocking<Unit> {
        val ready = (app.repository.bootstrapState.value ?: app.repository.bootstrap()) as Bootstrap.Ready
        db = app.repository.database(ready.profileID)
        if (db.head().activeDayID == null) db.startDay(Instant.now(), db.head().revision)
        app.coachInferenceForTest = { { _, _ -> CoachInferenceResult("fixture-model", "Noted.", emptyList(), emptyList()) } }
        TellCoach.canInferForTest = true
        withTimeout(10_000) { app.drainCoach(retryWaiting = true).join() } // an earlier test's turn finishes before this one reads
        asked(true) // the other tests finish on send; firstSendAsksForNotificationsOnce clears it
    }

    private fun asked(value: Boolean) = DiaryRepository.preferences(app).edit().putBoolean(ShareToCoachActivity.NOTIFICATIONS_ASKED, value).commit()

    @After fun close() {
        inserted.forEach { app.contentResolver.delete(it, null, null) }
        TellCoach.canInferForTest = null
        app.getSystemService(JobScheduler::class.java).cancelAll()
        app.coachInferenceForTest = null
    }

    // No hierarchy at all yet (an activity started from outside) or any more (the sheet finished) reads as absent.
    private fun exists(matcher: SemanticsMatcher) = runCatching { compose.onAllNodes(matcher).fetchSemanticsNodes().isNotEmpty() }.getOrDefault(false)
    private fun waitFor(matcher: SemanticsMatcher) = compose.waitUntil(15_000) { exists(matcher) }
    private fun until(check: () -> Boolean) = compose.waitUntil(15_000, check)
    private fun turns(text: String) = db.coachTurnsWithoutPhotos().filter { it.text == text }
    private fun send() = compose.onNode(hasText("Send to Coach") and hasClickAction()).assertIsEnabled().performClick()

    private fun textShare(text: String) = Intent(Intent.ACTION_SEND).setClass(app, ShareToCoachActivity::class.java)
        .setType("text/plain").putExtra(Intent.EXTRA_TEXT, text)

    /** A generated JPEG as another app would share it: a content:// URI this app can read. */
    private fun image(index: Int): Uri {
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, "mivu-share-test-$index-${UUID.randomUUID()}.jpg")
            put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
        }
        val uri = app.contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)!!
        inserted += uri
        app.contentResolver.openOutputStream(uri)!!.use { out ->
            Bitmap.createBitmap(40, 30, Bitmap.Config.ARGB_8888).apply { eraseColor(Color.rgb(200, 160 + index, 110)) }
                .compress(Bitmap.CompressFormat.JPEG, 85, out)
        }
        return uri
    }

    private fun imageShare(count: Int, text: String = "") = Intent(Intent.ACTION_SEND_MULTIPLE).setClass(app, ShareToCoachActivity::class.java)
        .setType("image/jpeg").putExtra(Intent.EXTRA_TEXT, text)
        .putParcelableArrayListExtra(Intent.EXTRA_STREAM, ArrayList((1..count).map(::image)))

    @Test fun textShareShowsTheSheetWithTheText() {
        ActivityScenario.launch<ShareToCoachActivity>(textShare("Synthetic lunch: two boiled eggs and a slice of toast")).use {
            waitFor(hasText("Tell Coach"))
            compose.onNodeWithTag("shareText").assertTextContains("Synthetic lunch: two boiled eggs and a slice of toast")
            compose.onNodeWithText("Cancel").assertIsEnabled()
        }
    }

    @Test fun sendSavesAndFinishes() {
        val text = "Synthetic dinner ${UUID.randomUUID()}"
        ActivityScenario.launch<ShareToCoachActivity>(textShare(text)).use { scenario ->
            waitFor(hasText("Tell Coach"))
            send()
            until { scenario.state == Lifecycle.State.DESTROYED }
            assertEquals(1, turns(text).size)
        }
    }

    // A real denial: the prompt is dismissed. Revoking a granted permission would kill this process, so nothing here grants it.
    @Test fun deniedPermissionPostsNothingAndSaves() {
        assertNotEquals(PackageManager.PERMISSION_GRANTED, app.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS))
        asked(false)
        ActivityScenario.launch<ShareToCoachActivity>(textShare("Synthetic tea ${UUID.randomUUID()}")).use { scenario ->
            waitFor(hasText("Tell Coach"))
            send()
            until { DiaryRepository.preferences(app).getBoolean(ShareToCoachActivity.NOTIFICATIONS_ASKED, false) }
            assertNotEquals(Lifecycle.State.DESTROYED, scenario.state) // the prompt is up; answering it finishes the sheet
            InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand("input keyevent KEYCODE_BACK").close()
            until { scenario.state == Lifecycle.State.DESTROYED }
        }
        // Not asked again: the next send finishes at once, saves, and its reply posts nothing.
        val text = "Synthetic juice ${UUID.randomUUID()}"
        ActivityScenario.launch<ShareToCoachActivity>(textShare(text)).use { scenario ->
            waitFor(hasText("Tell Coach"))
            send()
            until { scenario.state == Lifecycle.State.DESTROYED }
        }
        until { app.followed.isEmpty() && turns(text).singleOrNull()?.state == CoachTurnState.completed }
        assertEquals(emptyList<String>(), app.getSystemService(NotificationManager::class.java).activeNotifications.mapNotNull { it.tag })
    }

    @Test fun nineImagesKeepEightAndSaySo() {
        ActivityScenario.launch<ShareToCoachActivity>(imageShare(9)).use {
            waitFor(hasText("8 of 8 photos"))
            waitFor(hasText("Photo 9 was not added: a meal holds up to 8 photos."))
            compose.onNode(hasText("Send to Coach") and hasClickAction()).assertIsEnabled()
        }
    }

    @Test fun rotationKeepsTheSameSubmission() {
        val text = "Synthetic snack ${UUID.randomUUID()}"
        ActivityScenario.launch<ShareToCoachActivity>(textShare(text)).use { scenario ->
            waitFor(hasText("Tell Coach"))
            lateinit var first: UUID
            scenario.onActivity { first = it.model.submissionID }
            scenario.recreate()
            waitFor(hasText("Tell Coach"))
            scenario.onActivity { assertEquals(first, it.model.submissionID) }
            send()
            until { scenario.state == Lifecycle.State.DESTROYED }
            assertEquals(listOf(first), turns(text).map { it.id })
        }
    }

    @Test fun cancelSavesNothingAndDeletesPhotos() {
        val before = db.coachTurnsWithoutPhotos().size
        ActivityScenario.launch<ShareToCoachActivity>(imageShare(1, "Synthetic cancelled")).use { scenario ->
            waitFor(hasText("1 of 8 photos"))
            lateinit var folder: File
            scenario.onActivity { folder = File(it.cacheDir, "share/${it.model.submissionID}") }
            assertEquals(1, folder.listFiles()!!.size)
            compose.onNodeWithText("Cancel").performClick()
            until { scenario.state == Lifecycle.State.DESTROYED }
            until { !folder.exists() }
        }
        assertEquals(before, db.coachTurnsWithoutPhotos().size)
    }

    @Test fun coldStartShareSavesTheTurn() {
        // Started from outside the app by the share intent alone (no MainActivity), as another app's share sheet does.
        val text = "Synthetic-cold-share-${UUID.randomUUID()}"
        val command = "am start -W -a android.intent.action.SEND -t text/plain --es android.intent.extra.TEXT $text " +
            "-n ${app.packageName}/.share.ShareToCoachActivity"
        ParcelFileDescriptor.AutoCloseInputStream(InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand(command))
            .use { it.readBytes() }
        waitFor(hasText("Tell Coach"))
        compose.onNodeWithTag("shareText").assertTextContains(text)
        send()
        until { turns(text).size == 1 }
        until { !exists(hasText("Tell Coach")) }
        assertEquals(1, turns(text).size)
    }

    @Test fun buttonsAre48dpAtFontScale2() {
        ActivityScenario.launch(ComponentActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                val model = ShareViewModel(app, SharedContent("Synthetic tea", emptyList()), SavedStateHandle())
                activity.setContent {
                    CompositionLocalProvider(LocalDensity provides Density(activity.resources.displayMetrics.density, 2f)) {
                        MivuTheme { ShareSheet(model, onClose = {}, onOpenMivu = {}, onSaved = {}) }
                    }
                }
            }
            waitFor(hasText("Send to Coach"))
            compose.onNode(hasText("Send to Coach") and hasClickAction()).assertHeightIsAtLeast(48.dp)
            compose.onNode(hasText("Cancel") and hasClickAction()).assertHeightIsAtLeast(48.dp)
        }
    }
}
