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
import androidx.compose.ui.test.assert
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
import androidx.compose.ui.test.performSemanticsAction
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
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.assertHeightIsAtLeast
import com.yakov103.mivu.connection.CoachProvider
import com.yakov103.mivu.connection.ConnectionState
import com.yakov103.mivu.connection.NanoStatus
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.requiredWidth
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.assertContentDescriptionEquals
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.text.TextLayoutResult
import com.yakov103.mivu.diary.CoachCaptureContext
import com.yakov103.mivu.diary.CoachSubmissionPayload
import com.yakov103.mivu.diary.CoachTurnState
import com.yakov103.mivu.diary.FoodItem
import com.yakov103.mivu.diary.GoalRecord
import com.yakov103.mivu.diary.ManualNutritionDayChoice
import com.yakov103.mivu.diary.ManualNutritionOperation
import com.yakov103.mivu.diary.ManualNutritionPayload
import com.yakov103.mivu.diary.MealTimePrecision
import com.yakov103.mivu.diary.NutritionProvenance
import com.yakov103.mivu.diary.NutritionValues
import com.yakov103.mivu.diary.captureCoachSubmission
import com.yakov103.mivu.diary.failCoachTurn
import com.yakov103.mivu.diary.prepareManualNutritionTarget
import com.yakov103.mivu.diary.saveManualNutrition
import java.time.ZoneId
import java.time.temporal.ChronoUnit
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
    private val connected = MutableStateFlow(false)
    private var connection by mutableStateOf(ConnectionState())
    private var agreed = 0
    private var connects = 0
    private var seeToday = 0
    private val activity = MutableStateFlow<Pair<UUID, CoachActivity>?>(null)
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
        connected = connected, activity = activity, saved = saved,
        prepare = { preparePhoto(context.contentResolver, it, folder) })

    private var retaking: String? = null

    private fun launch(fontScale: Float? = null, saved: SavedStateHandle = SavedStateHandle(), hasCamera: Boolean = true, width: Int? = null) {
        model = model(saved)
        compose.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, fontScale ?: density.fontScale)) {
                MivuTheme {
                    Box(if (width != null) Modifier.requiredWidth(width.dp) else Modifier) {
                        CoachScreen(model, onOpenMeal = {}, onSeeToday = { seeToday++ }, onSeeProgress = {}, onOpenCamera = { retaking = it },
                            hasCamera = hasCamera, connection = connection, onAgree = { agreed++ }, onConnect = { connects++ })
                    }
                }
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

    private fun importTwo(): List<String> {
        val picked = (1..2).map { png("synthetic-retake-$it.png") }
        try {
            compose.runOnUiThread { model.importPhotos(picked.map(Uri::fromFile)) }
            waitForText("2 of 8 photos")
        } finally {
            picked.forEach { it.delete() }
        }
        return model.draft.value.photos
    }

    @Test fun retakeReplacesPhotoInPlace() {
        launch()
        val (first, second) = importTwo()
        compose.onNodeWithContentDescription("Retake photo 1").performClick()
        assertEquals(first, retaking)
        val shot = png("synthetic-retake-shot.png")
        compose.runOnUiThread { model.retakePhoto(first, shot) }
        compose.waitUntil(10_000) { model.draft.value.photos.first() != first }
        assertEquals(2, model.draft.value.photos.size)
        assertEquals(second, model.draft.value.photos[1])
        assertFalse(File(first).exists())
        assertFalse(shot.exists()) // the raw shot is prepared, then deleted
        assertNull(model.message.value)
    }

    @Test fun failedRetakeKeepsOldPhoto() {
        launch()
        val photos = importTwo()
        val broken = File(context.cacheDir, "synthetic-broken.jpg").apply { writeText("not an image") }
        compose.runOnUiThread { model.retakePhoto(photos[0], broken) }
        compose.waitUntil(10_000) { model.message.value == PHOTO_NOT_TAKEN }
        assertEquals(photos, model.draft.value.photos)
        assertTrue(File(photos[0]).exists())
        assertFalse(broken.exists())
    }

    @Test fun noCameraHidesCameraAndRetake() {
        launch(hasCamera = false)
        importTwo()
        compose.onNodeWithContentDescription("Add photos").assertDoesNotExist()
        compose.onNodeWithContentDescription("Retake photo 1").assertDoesNotExist()
        compose.onNodeWithContentDescription("Choose photos").assertIsDisplayed()
        compose.onNodeWithContentDescription("Remove photo 1").assertIsDisplayed()
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

    @Test fun committedSendWithClearedCacheCountsAsSent() {
        launch()
        val picked = png("synthetic-cleared.png")
        try {
            compose.runOnUiThread { model.importPhotos(listOf(Uri.fromFile(picked))) }
            waitForText("1 of 8 photos")
        } finally {
            picked.delete()
        }
        type("Synthetic stew")
        var lost = false
        // The capture commits, then the acknowledgement is lost and the cache is cleared, so the reconcile cannot run.
        CoachViewModel.afterCaptureForTest = {
            if (!lost) { lost = true; model.draft.value.photos.forEach { File(it).delete() }; throw IOException("synthetic lost acknowledgement") }
        }
        compose.onNodeWithContentDescription("Send").performClick()
        compose.waitUntil(10_000) { lost && model.message.value != null && !model.sending.value }
        assertEquals(1, turns().size)
        compose.onNodeWithContentDescription("Send").performClick()
        compose.waitUntil(10_000) { model.draft.value.text.isEmpty() && !model.sending.value }
        assertEquals(1, turns().size)
        assertTrue(model.draft.value.photos.isEmpty())
        assertNull(model.message.value)
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

    private val greetings = listOf("Morning! What’s for breakfast?", "Ready for lunch?", "What have you had today?", "What’s for dinner?",
        "Anything to log?")

    private fun goal(kcal: Double) = db().transaction(db().head().revision) {
        it.putGoal(GoalRecord(UUID.randomUUID(), "2026-01-01", ZoneId.systemDefault().id, 1, NutritionValues(kcal, 220.0, 120.0, 70.0), null, false))
    }

    private fun meal(kcal: Double) {
        val at = Instant.now().truncatedTo(ChronoUnit.SECONDS)
        val item = FoodItem(UUID.randomUUID(), "Synthetic plate", 1.0, "serving", NutritionValues(kcal, 10.0, 10.0, 10.0),
            NutritionProvenance.user, "Entered manually", false, emptyMap())
        db().saveManualNutrition(ManualNutritionPayload(profileID, UUID.randomUUID(), UUID.randomUUID(), ManualNutritionOperation.create,
            db().prepareManualNutritionTarget(ManualNutritionDayChoice.Current, at), at, at, MealTimePrecision.exact, null, listOf(item)),
            db().head().revision)
    }

    private fun failedTurn(): CoachTurn {
        val h = db().head()
        val turn = db().captureCoachSubmission(CoachSubmissionPayload(UUID.randomUUID(), "Synthetic soup", emptyList(),
            CoachCaptureContext(Instant.now().truncatedTo(ChronoUnit.SECONDS), h.profile.timeZoneID, h.activeDayID, h.previousDayConfirmedAt,
                h.activeConversationSegmentID)), h.revision)
        db().transaction(null) { it.failCoachTurn(turn.id, CoachTurnState.needsRetry) }
        return turn
    }

    private fun inBubble(text: String) = compose.onNode(hasText(text) and hasAnyAncestor(hasTestTag("coachPipLine")))

    private fun waitForTag(tag: String) = compose.waitUntil(10_000) { compose.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty() }

    @Test fun idleBubbleGreetsAndChipOpensToday() {
        connected.value = true
        goal(2100.0)
        launch()
        waitForTag("coachDate")
        val said = greetings.filter { compose.onAllNodes(hasText(it) and hasAnyAncestor(hasTestTag("coachPipLine"))).fetchSemanticsNodes().isNotEmpty() }
        assertEquals(1, said.size)
        compose.onNodeWithTag("coachDate").assert(hasText("Today · 0 / 2,100 kcal"))
            .assertContentDescriptionEquals("Logging to today, 0 of 2,100 kcal").assertHeightIsAtLeast(48.dp)
            .performSemanticsAction(SemanticsActions.OnClick) // as TalkBack, Switch Access and Voice Access activate it
        assertEquals(1, seeToday)
        assertEquals("Opens Today", compose.onNodeWithTag("coachDate").fetchSemanticsNode().config[SemanticsActions.OnClick].label)
    }

    @Test fun bubbleSpansTheComposerWidth() {
        connected.value = true
        goal(2100.0)
        meal(1935.0)
        launch(width = 360)
        val text = "Today · 1,935 / 2,100 kcal"
        waitForText(text)
        inBubble("Anything else to log?").assertIsDisplayed()
        val bubble = compose.onNodeWithTag("coachPipLine").getBoundsInRoot()
        val button = compose.onNodeWithContentDescription("Speak your meal").getBoundsInRoot()
        assertTrue("Bubble $bubble passes the button $button", bubble.right > button.left)
        val layouts = mutableListOf<TextLayoutResult>()
        compose.onNode(hasText(text), useUnmergedTree = true).fetchSemanticsNode().config[SemanticsActions.GetTextLayoutResult].action!!(layouts)
        assertEquals(1, layouts.single().lineCount)
    }

    @Test fun typingHidesTheGreeting() {
        connected.value = true
        launch()
        waitForTag("coachPipLine")
        compose.onNodeWithTag("coachInput").performClick()
        compose.waitUntil(5_000) { compose.onAllNodesWithTag("coachPipLine").fetchSemanticsNodes().isEmpty() }
        compose.onNodeWithTag("coachDate").assertIsDisplayed()
    }

    @Test fun needsRetryBubbleOffersTryAgain() {
        connected.value = true
        val turn = failedTurn()
        launch()
        waitForText("That one didn’t go through.")
        // A failed send adds the explanation under Pip's line.
        CoachViewModel.beforeCaptureForTest = { throw IOException("synthetic write failure") }
        type("Synthetic tea")
        compose.onNodeWithContentDescription("Send").performClick()
        compose.waitUntil(10_000) { model.message.value != null && !model.sending.value }
        inBubble(model.message.value!!).assertIsDisplayed()
        inBubble("That one didn’t go through.").assertIsDisplayed()
        activity.value = turn.id to CoachActivity.thinking
        inBubble("Try again").assertIsNotEnabled()
        activity.value = null
        inBubble("Try again").assertIsEnabled().assertHeightIsAtLeast(48.dp).performClick()
        compose.waitUntil(10_000) { db().coachTurn(turn.id)!!.state == CoachTurnState.captured && drains > 0 }
    }

    @Test fun largeFontHidesOnlyTheGreeting() {
        connected.value = true
        launch(fontScale = 2f)
        waitForTag("coachDate")
        compose.onNodeWithTag("coachPipLine").assertDoesNotExist()
        failedTurn()
        waitForText("That one didn’t go through.")
        inBubble("Try again").assertIsDisplayed()
    }

    @Test fun notConnectedBubbleOffersConnect() {
        launch()
        inBubble("Connect ChatGPT so I can count for you").assertIsDisplayed()
        inBubble("Connect").assertIsDisplayed().assertHeightIsAtLeast(48.dp)
        compose.onNodeWithText("Messages save on this phone.").assertDoesNotExist()
        compose.onNodeWithText("Manage usage").assertDoesNotExist()
    }

    @Test fun bubbleConnectAsksConsentFirst() {
        launch()
        inBubble("Connect").performClick()
        compose.onNodeWithText("Share with OpenAI?").assertIsDisplayed()
        assertEquals(0, connects)
        compose.onNodeWithText("Agree and Continue").performClick()
        compose.waitForIdle()
        assertEquals(1, agreed)
        assertEquals(1, connects)
    }

    @Test fun connectedFootnoteShowsManageUsage() {
        connected.value = true
        launch()
        compose.onNodeWithText("Using ChatGPT plan", substring = true).assertIsDisplayed()
        compose.onNodeWithText("Manage usage").assertIsDisplayed().assertHeightIsAtLeast(48.dp)
        compose.onNodeWithText("Connect ChatGPT for replies").assertDoesNotExist()
    }

    @Test fun onDeviceFootnoteExplainsTheLimits() {
        connected.value = true
        connection = ConnectionState(nano = NanoStatus.available, storedProvider = CoachProvider.onDevice)
        launch()
        compose.onNodeWithText("Gemini Nano on this phone only logs meals and changes amounts, with lower accuracy. " +
            "Choose ChatGPT in Settings → Coach AI for more.").assertIsDisplayed()
        compose.onNodeWithText("Using ChatGPT plan", substring = true).assertDoesNotExist()
    }
}
