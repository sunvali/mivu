package com.yakov103.mivu.quick

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.ShortcutManager
import android.service.quicksettings.TileService
import android.view.KeyEvent
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsFocused
import androidx.compose.ui.test.assertIsNotFocused
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isHeading
import androidx.compose.ui.test.junit4.v2.createEmptyComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry
import androidx.test.runner.lifecycle.Stage
import com.yakov103.mivu.MainActivity
import com.yakov103.mivu.MivuApplication
import com.yakov103.mivu.coach.CoachReplyNotification
import com.yakov103.mivu.diary.Bootstrap
import com.yakov103.mivu.diary.DiaryDatabase
import com.yakov103.mivu.diary.DiaryProfile
import com.yakov103.mivu.diary.DiaryRepository
import com.yakov103.mivu.ui.today.TodayFixture
import java.util.UUID
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.BeforeClass
import org.junit.Rule
import org.junit.Test

/** Synthetic diaries only; the real MainActivity and the app's own repository, as a shortcut or the tile opens them. */
class QuickCaptureTest {
    @get:Rule val compose = createEmptyComposeRule()
    private val app: MivuApplication = ApplicationProvider.getApplicationContext()

    companion object {
        // Before anything opens the app's diary, so the repository opens one existing synthetic diary (no setup with Pip).
        @BeforeClass @JvmStatic fun fresh() {
            val context: Context = ApplicationProvider.getApplicationContext()
            TodayFixture.wipe(context)
            TodayFixture.diary(context)
        }
    }

    @Before fun grant() {
        InstrumentationRegistry.getInstrumentation().uiAutomation.grantRuntimePermission(app.packageName, Manifest.permission.CAMERA)
        app.quickRequest.value = null
    }

    private fun exists(matcher: SemanticsMatcher) = compose.onAllNodes(matcher).fetchSemanticsNodes().isNotEmpty()
    private fun waitFor(matcher: SemanticsMatcher) = compose.waitUntil(15_000) { exists(matcher) }
    private val camera = hasContentDescription("Take photo")
    // The title, not the tab: the bar hides while the focused composer's keyboard is up.
    private fun coachShown() = compose.onNode(hasText("Coach") and isHeading())

    private fun resumed(): Collection<Activity> {
        var activities: Collection<Activity> = emptyList()
        InstrumentationRegistry.getInstrumentation().runOnMainSync {
            activities = ActivityLifecycleMonitorRegistry.getInstance().getActivitiesInStage(Stage.RESUMED)
        }
        return activities
    }

    @Test fun snapItOpensTheCoachCamera() {
        ActivityScenario.launch<MainActivity>(quickIntent(app, QuickAction.SnapIt)).use {
            waitFor(camera)
            compose.onNodeWithContentDescription("Take photo").assertIsDisplayed()
            assertNull(app.quickRequest.value)
        }
    }

    @Test fun coachFocusesTheComposer() {
        ActivityScenario.launch<MainActivity>(quickIntent(app, QuickAction.OpenCoach)).use {
            waitFor(hasTestTag("coachInput"))
            coachShown().assertIsDisplayed()
            compose.waitUntil(10_000) { runCatching { compose.onNodeWithTag("coachInput").assertIsFocused() }.isSuccess }
        }
    }

    // iOS QuickLog: a reply notification only selects the Coach tab; the keyboard stays down.
    @Test fun replyNotificationSelectsCoachWithoutFocus() {
        val reply = quickIntent(app, QuickAction.OpenCoach).putExtra(CoachReplyNotification.TURN, UUID.randomUUID().toString())
        ActivityScenario.launch<MainActivity>(reply).use {
            waitFor(hasTestTag("coachInput"))
            coachShown().assertIsDisplayed()
            compose.waitForIdle()
            compose.onNodeWithTag("coachInput").assertIsNotFocused()
        }
    }

    @Test fun snapItWhileOpenReusesTheActivity() {
        val launched = quickIntent(app, QuickAction.OpenCoach)
        ActivityScenario.launch<MainActivity>(launched).use { scenario ->
            waitFor(hasTestTag("coachInput"))
            lateinit var first: Activity
            scenario.onActivity { first = it }
            app.startActivity(quickIntent(app, QuickAction.SnapIt))
            waitFor(camera)
            assertSame(first, resumed().single())
            // Back (the key, which reaches the camera's window) closes the camera onto Coach.
            InstrumentationRegistry.getInstrumentation().sendKeyDownUpSync(KeyEvent.KEYCODE_BACK)
            compose.waitUntil(10_000) { !exists(camera) && exists(hasTestTag("coachInput")) }
            coachShown().assertIsDisplayed()
            // onNewIntent's setIntent hides the activity from the scenario, which matches lifecycle events by intent.
            scenario.onActivity { it.intent = launched }
        }
    }

    @Test fun requestWaitsForTheDiaryChooser() {
        // A second diary and a lost selection: the app asks to choose before any diary is ready, and the camera opens after.
        val other = DiaryProfile(UUID.randomUUID(), "Synthetic other", "en", "UTC", "")
        DiaryDatabase.create(app, other).close()
        DiaryRepository.preferences(app).edit().putString("selectedProfile", UUID.randomUUID().toString()).commit()
        runBlocking { app.repository.bootstrap() }
        assertTrue(app.repository.bootstrapState.value is Bootstrap.Choose)
        ActivityScenario.launch<MainActivity>(quickIntent(app, QuickAction.SnapIt)).use {
            waitFor(hasText("Choose a diary"))
            assertTrue(!exists(camera))
            compose.onNodeWithText("My diary").performClick()
            waitFor(camera)
            assertNull(app.quickRequest.value)
        }
    }

    @Test fun snapItOnANewDiaryWaitsForSetup() {
        TodayFixture.wipe(app)
        runBlocking { app.repository.bootstrap() } // creates "My diary", so setup with Pip opens once
        try {
            ActivityScenario.launch<MainActivity>(quickIntent(app, QuickAction.SnapIt)).use {
                waitFor(hasTestTag("onboardingLater"))
                compose.waitForIdle()
                assertTrue(!exists(camera))
                compose.onNodeWithTag("onboardingLater").performClick()
                waitFor(camera)
                assertNull(app.quickRequest.value)
            }
        } finally {
            TodayFixture.wipe(app)
            TodayFixture.diary(app)
            runBlocking { app.repository.bootstrap() }
        }
    }

    @Test fun manifestShortcutsAreSnapItAndCoach() {
        val shortcuts = app.getSystemService(ShortcutManager::class.java).manifestShortcuts.sortedBy { it.rank }
        assertEquals(listOf("snap_it", "coach"), shortcuts.map { it.id })
        assertEquals(listOf("Snap It", "Coach"), shortcuts.map { it.shortLabel.toString() })
        assertEquals(listOf(QuickAction.SnapIt.action, QuickAction.OpenCoach.action), shortcuts.map { it.intent!!.action })
        assertEquals(listOf(QuickAction.SnapIt, QuickAction.OpenCoach), shortcuts.map { QuickAction.from(it.intent) })
    }

    @Test fun snapItTileIsDeclared() {
        val tiles = app.packageManager.queryIntentServices(Intent(TileService.ACTION_QS_TILE).setPackage(app.packageName), 0)
        val tile = tiles.single().serviceInfo
        assertEquals(SnapItTileService::class.java.name, tile.name)
        assertEquals("Snap It", tile.loadLabel(app.packageManager).toString())
    }

    @Test fun unknownOrForeignIntentsAreIgnored() {
        assertNull(QuickAction.from(null))
        assertNull(QuickAction.from(Intent(Intent.ACTION_MAIN)))
        assertNull(QuickAction.from(Intent("com.yakov103.mivu.action.DELETE_EVERYTHING")))
    }
}
