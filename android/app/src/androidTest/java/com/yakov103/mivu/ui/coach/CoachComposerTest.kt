package com.yakov103.mivu.ui.coach

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.net.Uri
import androidx.activity.ComponentActivity
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.getBoundsInRoot
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextReplacement
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.lifecycle.SavedStateHandle
import androidx.test.core.app.ApplicationProvider
import com.yakov103.mivu.coach.CoachActivity
import com.yakov103.mivu.diary.CoachReply
import com.yakov103.mivu.diary.CoachTurn
import com.yakov103.mivu.diary.DiaryRepository
import com.yakov103.mivu.diary.startDay
import com.yakov103.mivu.pip.CompanionPose
import com.yakov103.mivu.pip.MotionPolicy.Playback
import com.yakov103.mivu.ui.composer.preparePhoto
import com.yakov103.mivu.ui.theme.MivuTheme
import com.yakov103.mivu.ui.today.TodayFixture
import java.io.File
import java.io.IOException
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.flow.MutableStateFlow
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test

/** Synthetic diaries only; drain is a counter, so no inference runs. */
class CoachComposerTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private val context: Context = ApplicationProvider.getApplicationContext()
    private lateinit var repository: DiaryRepository
    private lateinit var profileID: UUID
    private var drains = 0
    private lateinit var model: CoachViewModel
    private val folder get() = File(context.cacheDir, "coach-test")

    @Before fun open() {
        TodayFixture.wipe(context)
        profileID = TodayFixture.diary(context)
        repository = DiaryRepository(context)
        db().startDay(Instant.now(), db().head().revision)
    }

    @After fun close() {
        CoachViewModel.afterCaptureForTest = null
        CoachViewModel.beforeCaptureForTest = null
        db().close()
        folder.deleteRecursively()
        TodayFixture.wipe(context)
    }

    private fun db() = repository.database(profileID)

    private fun model(saved: SavedStateHandle = SavedStateHandle()) = CoachViewModel(repository, profileID, drain = { drains++ },
        isConnected = { false }, activity = MutableStateFlow<Pair<UUID, CoachActivity>?>(null), saved = saved,
        prepare = { preparePhoto(context.contentResolver, it, folder) })

    private fun launch(fontScale: Float? = null, saved: SavedStateHandle = SavedStateHandle()) {
        model = model(saved)
        compose.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, fontScale ?: density.fontScale)) {
                MivuTheme { CoachScreen(model, onOpenMeal = {}, onSeeToday = {}, onSeeProgress = {}) }
            }
        }
        compose.waitUntil(10_000) { model.timeline.value.loaded }
    }

    private fun turns(): List<CoachTurn> = db().coachTurnsWithoutPhotos()

    private fun waitForText(text: String) =
        compose.waitUntil(10_000) { compose.onAllNodes(hasText(text, substring = true), useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty() }

    private fun type(text: String) = compose.onNodeWithTag("coachInput").performTextReplacement(text)

    @Test fun sendSavesTurnAndClearsDraft() {
        launch()
        type("Synthetic toast")
        compose.onNodeWithContentDescription("Send").performClick()
        compose.waitUntil(10_000) { turns().size == 1 && model.draft.value.text.isEmpty() }
        assertEquals("Synthetic toast", turns().single().text)
        compose.waitUntil(10_000) { drains > 0 }
        compose.onNodeWithContentDescription("Speak your meal").assertIsDisplayed()
    }

    @Test fun uncertainSaveReconcilesWithoutDuplicate() {
        launch()
        var thrown = false
        CoachViewModel.afterCaptureForTest = { if (!thrown) { thrown = true; throw IOException("synthetic lost acknowledgement") } }
        type("Synthetic soup")
        compose.onNodeWithContentDescription("Send").performClick()
        compose.waitUntil(10_000) { thrown && model.draft.value.text.isEmpty() }
        assertEquals(1, turns().size)
        assertNull(model.message.value)
    }

    @Test fun micWhenEmptySendWhenText() {
        launch()
        compose.onNodeWithContentDescription("Speak your meal").assertIsDisplayed()
        compose.onNodeWithContentDescription("Send").assertDoesNotExist()
        type("Synthetic tea")
        compose.onNodeWithContentDescription("Send").assertIsDisplayed()
        compose.onNodeWithContentDescription("Speak your meal").assertDoesNotExist()
    }

    private fun png(name: String) = File(context.cacheDir, name).apply {
        val bitmap = Bitmap.createBitmap(64, 64, Bitmap.Config.ARGB_8888)
        Canvas(bitmap).drawColor(Color.rgb(196, 48, 43))
        outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }

    @Test fun importAddsUpToEightAndRemoves() {
        launch()
        val picked = (1..9).map { png("synthetic-coach-$it.png") }
        try {
            // The field's camera opens the camera, which hosts the Photo Picker (CoachCameraTest); here the model imports directly.
            compose.runOnUiThread { model.importPhotos(picked.map(Uri::fromFile)) }
            waitForText("8 of 8 photos")
        } finally {
            picked.forEach { it.delete() }
        }
        waitForText("Photo 9 was not added: a meal holds up to 8 photos.")
        assertEquals(8, compose.onAllNodesWithContentDescription("Remove photo", substring = true).fetchSemanticsNodes().size)
        compose.onNodeWithContentDescription("Send").assertIsDisplayed() // photos alone can be sent
        compose.onNodeWithContentDescription("Remove photo 1").performClick()
        waitForText("7 of 8 photos")
        assertEquals(7, model.draft.value.photos.size)
    }

    @Test fun failedSendThenRemovedPhotoStillSendsOnce() {
        launch()
        val picked = (1..2).map { png("synthetic-retry-$it.png") }
        try {
            compose.runOnUiThread { model.importPhotos(picked.map(Uri::fromFile)) }
            waitForText("2 of 8 photos")
        } finally {
            picked.forEach { it.delete() }
        }
        var failed = false
        CoachViewModel.beforeCaptureForTest = { if (!failed) { failed = true; throw IOException("synthetic write failure") } }
        compose.onNodeWithContentDescription("Send").performClick()
        compose.waitUntil(10_000) { failed && model.message.value != null && !model.sending.value }
        assertTrue(turns().isEmpty())
        compose.onNodeWithContentDescription("Remove photo 1").performClick()
        compose.waitUntil(5_000) { model.draft.value.photos.size == 1 }
        compose.onNodeWithContentDescription("Send").performClick()
        compose.waitUntil(10_000) { turns().size == 1 && model.draft.value.photos.isEmpty() }
        assertNull(model.message.value)
        assertEquals(1, db().coachTurn(turns().single().id)!!.photos.size)
    }

    @Test fun fieldClampsToTheSendableLength() {
        launch()
        type("a".repeat(20_001))
        compose.waitUntil(5_000) { model.draft.value.text.length == 20_000 }
        val shown = compose.onNodeWithTag("coachInput").fetchSemanticsNode().config[SemanticsProperties.EditableText].text
        assertEquals(20_000, shown.length)
    }

    @Test fun suggestionChipFillsDraftOnly() {
        launch()
        compose.onNodeWithText("Log breakfast").performClick()
        compose.waitUntil(5_000) { model.draft.value.text == "For breakfast I had " }
        assertTrue(turns().isEmpty())
        compose.onNodeWithText("Log breakfast").assertDoesNotExist() // chips leave once a draft starts
    }

    @Test fun askPipFromFoodQuotesAndPrefills() {
        launch()
        val mealID = UUID.randomUUID()
        val itemID = UUID.randomUUID()
        compose.runOnUiThread {
            val (reply, draft) = AskPip.Food(mealID, itemID, "Synthetic honey", "2026-10-24").handoff()
            assertTrue(model.startReply(reply, draft))
        }
        waitForText("From Diary")
        compose.onNodeWithText("Synthetic honey").assertIsDisplayed()
        assertEquals("About the Synthetic honey from Sat 24 Oct: ", model.draft.value.text)
        assertEquals(CoachReply(CoachReply.Target.Item(mealID, itemID), "Synthetic honey"), model.draft.value.reply)
        compose.onNodeWithContentDescription("Cancel reply").assertIsDisplayed()
    }

    @Test fun askPipKeepsDraftInProgress() {
        launch()
        type("Synthetic lunch")
        compose.runOnUiThread {
            val (reply, draft) = AskPip.Meal(UUID.randomUUID(), "Synthetic meal").handoff()
            assertFalse(model.startReply(reply, draft))
        }
        assertEquals("Synthetic lunch", model.draft.value.text)
        assertNull(model.draft.value.reply)
        compose.onNodeWithText("From Diary").assertDoesNotExist()
    }

    @Test fun cancelReplyRemovesQuote() {
        launch()
        compose.runOnUiThread { model.startReply(AskPip.Day(UUID.randomUUID(), "2026-10-24").handoff().first) }
        waitForText("Saturday, 24 Oct")
        compose.onNodeWithContentDescription("Cancel reply").performClick()
        compose.waitUntil(5_000) { model.draft.value.reply == null }
        compose.onNodeWithText("From Diary").assertDoesNotExist()
    }

    @Test fun draftSurvivesRecreate() {
        val saved = SavedStateHandle()
        launch(saved = saved)
        type("Synthetic dinner")
        compose.runOnUiThread { model.startReply(AskPip.Meal(UUID.randomUUID(), "Synthetic meal").handoff().first) }
        val before = model.draft.value
        // A new model over the same saved state, as after process death.
        val restored = model(saved)
        assertEquals(before, restored.draft.value)
        assertEquals("Synthetic dinner", restored.draft.value.text)
    }

    @Test fun pipPeeksAboveFieldHiddenFromAccessibility() {
        launch()
        compose.waitUntil(30_000) { compose.onAllNodesWithTag("pipCompanion", useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty() }
        val pip = compose.onNodeWithTag("pipCompanion", useUnmergedTree = true)
        val pipBounds = pip.getBoundsInRoot()
        val field = compose.onNodeWithTag("coachField").getBoundsInRoot()
        assertTrue("Pip $pipBounds stands on the field $field", kotlin.math.abs((pipBounds.bottom - field.top).value) <= 2f)
        assertTrue("Pip sits at the field's left", pipBounds.left < field.left + 48.dp)
        val node = pip.fetchSemanticsNode()
        assertFalse(SemanticsProperties.ContentDescription in node.config)
        assertFalse(SemanticsProperties.Text in node.config)
    }

    @Test fun sendShowsSubmittedThenSaved() {
        model = model()
        compose.runOnUiThread {
            model.reportPlayback(Playback.Animated)
            model.updateText("Synthetic apple")
            assertTrue(model.send())
        }
        compose.waitUntil(5_000) { model.companion.value.pose == CompanionPose.Submitted }
        compose.waitUntil(10_000) { model.companion.value.pose == CompanionPose.Saved }
        assertEquals(1, turns().size)
    }

    @Test fun largeFontKeepsSendReachable() {
        launch(fontScale = 2f)
        type("Synthetic porridge with a long description of everything in the bowl")
        val send = compose.onNodeWithContentDescription("Send").assertIsDisplayed().getBoundsInRoot()
        val root = compose.onRoot().getBoundsInRoot()
        assertTrue("Send $send fits $root", send.right <= root.right && send.bottom <= root.bottom)
        assertTrue(send.right - send.left >= 48.dp && send.bottom - send.top >= 48.dp)
        compose.onNodeWithContentDescription("Send").performClick()
        compose.waitUntil(10_000) { turns().size == 1 }
    }
}
