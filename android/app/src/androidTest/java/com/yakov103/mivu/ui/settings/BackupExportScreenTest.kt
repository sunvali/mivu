package com.yakov103.mivu.ui.settings

import android.app.Activity
import android.app.Instrumentation.ActivityResult
import android.content.Intent
import android.net.Uri
import androidx.activity.ComponentActivity
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.espresso.intent.Intents
import androidx.test.espresso.intent.Intents.intended
import androidx.test.espresso.intent.Intents.intending
import androidx.test.espresso.intent.matcher.IntentMatchers.hasAction
import com.yakov103.mivu.diary.DiaryProfile
import com.yakov103.mivu.diary.DiarySnapshot
import com.yakov103.mivu.ui.theme.MivuTheme
import java.util.UUID
import kotlinx.coroutines.CompletableDeferred
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test

/** A synthetic empty diary; the share sheet is stubbed, so nothing leaves the device. */
class BackupExportScreenTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private val profile = DiaryProfile(UUID.randomUUID(), "Sample", "en", "UTC", "")
    private val diary = DiarySnapshot(1, 1, profile, emptyList(), emptyList(), emptyList(), deletedMealIDs = emptyList())
    private val folder get() = reportsDirectory(compose.activity)

    @Before fun stubChooser() {
        Intents.init()
        intending(hasAction(Intent.ACTION_CHOOSER)).respondWith(ActivityResult(Activity.RESULT_OK, null))
    }

    @After fun release() = Intents.release()

    private fun reportFiles() = folder.walkBottomUp().filter { it.isFile }.toList()

    @Test fun shareLaunchesAChooserWithReadableUris() {
        compose.setContent { MivuTheme { BackupExportScreen(profile.id, { diary }, { profile.id }, onBack = {}) } }
        compose.onNodeWithText("CSV").performClick()
        compose.onNodeWithText("Share report").performClick()
        compose.waitUntil(10_000) { Intents.getIntents().isNotEmpty() }
        intended(hasAction(Intent.ACTION_CHOOSER))
        val target = Intents.getIntents().single().getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)!!
        assertEquals(Intent.ACTION_SEND_MULTIPLE, target.action)
        assertTrue(target.flags and Intent.FLAG_GRANT_READ_URI_PERMISSION != 0)
        val uris = target.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)!!
        assertEquals(3, uris.size)
        uris.forEach { assertEquals("${compose.activity.packageName}.reports", it.authority) }
        // The stubbed chooser returns at once, and its files go with it.
        compose.waitUntil(5_000) { reportFiles().isEmpty() }
    }

    @Test fun profileChangeDuringPreparationDropsTheFiles() {
        val gate = CompletableDeferred<Unit>()
        var current: UUID? = profile.id
        compose.setContent { MivuTheme { BackupExportScreen(profile.id, { gate.await(); diary }, { current }, onBack = {}) } }
        compose.onNodeWithText("Share report").performClick()
        compose.waitUntil(5_000) { compose.onAllNodesWithText("Preparing report").fetchSemanticsNodes().isNotEmpty() }
        current = UUID.randomUUID()
        gate.complete(Unit)
        compose.waitUntil(5_000) { compose.onAllNodesWithText("Share report").fetchSemanticsNodes().isNotEmpty() }
        assertTrue(Intents.getIntents().isEmpty())
        assertTrue(reportFiles().isEmpty())
    }
}
