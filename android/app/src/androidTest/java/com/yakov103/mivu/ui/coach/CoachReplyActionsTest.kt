package com.yakov103.mivu.ui.coach

import android.app.Activity
import android.app.Instrumentation
import android.content.ActivityNotFoundException
import android.content.ClipboardManager
import android.content.Intent
import android.net.Uri
import android.content.Context
import androidx.activity.ComponentActivity
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.performTextReplacement
import androidx.test.espresso.intent.Intents
import androidx.test.espresso.intent.Intents.intended
import androidx.test.espresso.intent.Intents.intending
import androidx.test.espresso.intent.VerificationModes.times
import androidx.test.espresso.intent.matcher.IntentMatchers.hasAction
import androidx.test.espresso.intent.matcher.IntentMatchers.hasData
import androidx.test.espresso.intent.matcher.IntentMatchers.hasExtra
import org.hamcrest.Matchers.allOf
import org.hamcrest.Matchers.equalTo
import androidx.compose.ui.test.assertIsFocused
import androidx.compose.ui.test.assertIsNotDisplayed
import androidx.compose.ui.test.hasAnyDescendant
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.longClick
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipe
import androidx.compose.ui.unit.dp
import androidx.lifecycle.SavedStateHandle
import androidx.test.core.app.ApplicationProvider
import com.yakov103.mivu.coach.CoachActivity
import com.yakov103.mivu.diary.CoachReply
import com.yakov103.mivu.diary.CoachTurn
import com.yakov103.mivu.diary.CoachTurnState
import com.yakov103.mivu.diary.DiaryRepository
import com.yakov103.mivu.diary.MealPhoto
import com.yakov103.mivu.diary.PhotoRole
import com.yakov103.mivu.diary.startDay
import com.yakov103.mivu.ui.theme.MivuTheme
import com.yakov103.mivu.ui.today.TodayFixture
import java.time.Instant
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import java.util.UUID
import kotlinx.coroutines.flow.MutableStateFlow
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Rule
import org.junit.Test

/** Synthetic diaries only: Reply, Copy and Report reply from a long press, a swipe, or a TalkBack custom action. */
class CoachReplyActionsTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private val context: Context = ApplicationProvider.getApplicationContext()
    private lateinit var repository: DiaryRepository
    private lateinit var profileID: UUID
    private lateinit var model: CoachViewModel
    private val now = Instant.now().truncatedTo(ChronoUnit.SECONDS)

    @Before fun open() {
        CoachReports.file(context).delete()
        TodayFixture.wipe(context)
        profileID = TodayFixture.diary(context)
        repository = DiaryRepository(context)
    }

    @After fun close() {
        startEmailForTest = null
        CoachReports.file(context).delete()
        repository.database(profileID).close()
        TodayFixture.wipe(context)
    }

    /** [count] finished exchanges, oldest first; the newest asks "Synthetic breakfast" and Pip answers in Markdown. */
    private fun seed(count: Int = 1, text: String = "Synthetic breakfast", photo: Boolean = false): List<CoachTurn> {
        val db = repository.database(profileID)
        db.startDay(now, db.head().revision)
        val day = db.head().activeDayID
        val turns = List(count) {
            val last = it == count - 1
            val photos = if (last && photo) listOf(MealPhoto(UUID.randomUUID(), byteArrayOf(1), now, PhotoRole.unspecified)) else emptyList()
            CoachTurn(UUID.randomUUID(), now.minus(count - it.toLong(), ChronoUnit.MINUTES), if (last) text else "Synthetic $it", photos,
                CoachTurnState.completed, if (last) "Saved — about **430** kcal." else "Synthetic reply $it", emptyList(),
                ZoneId.systemDefault().id, day, photos.map { p -> p.id })
        }
        db.replaceAll(db.snapshot().copy(revision = db.head().revision.toInt() + 1, coachTurns = turns))
        return turns
    }

    private fun launch() {
        model = CoachViewModel(repository, profileID, drain = {}, connected = MutableStateFlow(false),
            activity = MutableStateFlow<Pair<UUID, CoachActivity>?>(null), saved = SavedStateHandle())
        compose.setContent { MivuTheme { CoachScreen(model, onOpenMeal = {}, onSeeToday = {}, onSeeProgress = {}) } }
        compose.waitUntil(10_000) { model.timeline.value.loaded }
        compose.waitUntil(10_000) { compose.onAllNodes(hasText("Saved — about 430 kcal.")).fetchSemanticsNodes().isNotEmpty() }
    }

    private fun quote(turn: CoachTurn, fromPip: Boolean, excerpt: String) = CoachReply(CoachReply.Target.Message(turn.id, fromPip), excerpt)

    private fun waitForReply() = compose.waitUntil(5_000) { model.draft.value.reply != null }

    @Test fun longPressReplyQuotesPip() {
        val turn = seed().last()
        launch()
        compose.onNodeWithText("Saved — about 430 kcal.").performTouchInput { longClick() }
        compose.onNodeWithText("Reply").performClick()
        waitForReply()
        assertEquals(quote(turn, true, "Saved — about 430 kcal."), model.draft.value.reply)
        compose.onNodeWithTag("coachInput").assertIsFocused() // as iOS reply(to:): typing follows
    }

    @Test fun longPressReplyQuotesOwnMessage() {
        val turn = seed().last()
        launch()
        compose.onNodeWithText("Synthetic breakfast").performTouchInput { longClick() }
        compose.onNodeWithText("Reply").performClick()
        waitForReply()
        assertEquals(quote(turn, false, "Synthetic breakfast"), model.draft.value.reply)
    }

    @Test fun copyPutsPlainTextOnClipboard() {
        seed()
        launch()
        compose.onNodeWithText("Saved — about 430 kcal.").performTouchInput { longClick() }
        compose.onNodeWithText("Copy").performClick()
        val clipboard = context.getSystemService(ClipboardManager::class.java)
        compose.waitUntil(5_000) { compose.runOnUiThread<String?> { clipboard.primaryClip?.getItemAt(0)?.text?.toString() } == "Saved — about 430 kcal." }
        assertNull(model.draft.value.reply)
    }

    @Test fun copyHiddenForPhotoOnlyMessage() {
        val turn = seed(text = "", photo = true).last()
        launch()
        compose.onNodeWithText("1 photo").performTouchInput { longClick() }
        compose.onNodeWithText("Reply").assertIsDisplayed()
        compose.onNodeWithText("Copy").assertDoesNotExist()
        compose.onNodeWithText("Reply").performClick()
        waitForReply()
        assertEquals(quote(turn, false, "Photo"), model.draft.value.reply)
    }

    @Test fun swipePastThresholdReplies() {
        val turn = seed().last()
        launch()
        compose.onNodeWithText("Saved — about 430 kcal.").performTouchInput {
            swipe(center.copy(x = 64.dp.toPx()), center.copy(x = 200.dp.toPx()), 300)
        }
        waitForReply()
        assertEquals(quote(turn, true, "Saved — about 430 kcal."), model.draft.value.reply) // Pip's answer when there is one
    }

    @Test fun shortSwipeDoesNothing() {
        seed()
        launch()
        compose.onNodeWithText("Saved — about 430 kcal.").performTouchInput {
            swipe(center.copy(x = 64.dp.toPx()), center.copy(x = 104.dp.toPx()), 300)
        }
        compose.waitForIdle()
        assertNull(model.draft.value.reply)
    }

    @Test fun verticalDragStillScrolls() {
        seed(count = 20)
        launch()
        // Mostly down with a little rightward drift: the list scrolls back in time and nothing is quoted.
        compose.onNodeWithTag("coachTimeline").performTouchInput {
            swipe(Offset(64.dp.toPx(), top + 40.dp.toPx()), Offset(124.dp.toPx(), bottom - 40.dp.toPx()), 400)
        }
        compose.waitForIdle()
        compose.onNodeWithText("Saved — about 430 kcal.").assertIsNotDisplayed()
        assertNull(model.draft.value.reply)
    }

    @Test fun replyCustomActionExists() {
        val turn = seed().last()
        launch()
        val bubble = SemanticsMatcher("has Reply") { node ->
            SemanticsActions.CustomActions in node.config && node.config[SemanticsActions.CustomActions].any { it.label == "Reply" }
        }
        // TalkBack runs actions on the main thread; the test calls them there too.
        fun reply(matcher: SemanticsMatcher) {
            val action = compose.onNode(matcher).fetchSemanticsNode().config[SemanticsActions.CustomActions].single { it.label == "Reply" }
            compose.runOnUiThread { action.action() }
        }
        reply(bubble and hasAnyDescendant(hasText("Synthetic breakfast")))
        waitForReply()
        assertEquals(quote(turn, false, "Synthetic breakfast"), model.draft.value.reply)
        reply(bubble and hasText("Saved — about 430 kcal."))
        compose.waitUntil(5_000) { model.draft.value.reply == quote(turn, true, "Saved — about 430 kcal.") }
    }

    private val pipReply = "Saved — about 430 kcal."

    private fun reports() = CoachReports.read(CoachReports.file(context))

    private fun openReport() {
        compose.onNodeWithText(pipReply).performTouchInput { longClick() }
        compose.onNodeWithText("Report reply").performClick()
        compose.onNodeWithText("Report this reply?").assertIsDisplayed()
    }

    @Test fun replyMenuOffersReport() {
        seed()
        launch()
        compose.onNodeWithText(pipReply).performTouchInput { longClick() }
        compose.onNodeWithText("Report reply").assertIsDisplayed()
        compose.onNodeWithText("Copy").performClick() // closes the menu
        compose.onNodeWithText("Synthetic breakfast").performTouchInput { longClick() }
        compose.onNodeWithText("Reply").assertIsDisplayed()
        compose.onNodeWithText("Report reply").assertDoesNotExist()
    }

    @Test fun reportSavesThenOpensEmail() {
        val turn = seed().last()
        launch()
        openReport()
        compose.onNodeWithText("Mivu opens your email app with this reply so you can send it to us. " +
            "Nothing else from your diary is included.").assertIsDisplayed()
        compose.onNode(hasText("Report") and hasClickAction()).assertIsNotEnabled() // a reason comes first
        compose.onNodeWithText("Wrong or misleading").performClick()
        compose.onNodeWithTag("reportNote").performTextReplacement("Synthetic note")
        Intents.init()
        try {
            intending(hasAction(Intent.ACTION_SENDTO)).respondWith(Instrumentation.ActivityResult(Activity.RESULT_OK, null))
            compose.onNode(hasText("Report") and hasClickAction()).performClick()
            compose.waitUntil(5_000) { Intents.getIntents().isNotEmpty() }
            intended(allOf(hasAction(Intent.ACTION_SENDTO), hasData(Uri.parse("mailto:")),
                hasExtra(Intent.EXTRA_EMAIL, arrayOf("support@mivuapp.com")), hasExtra(Intent.EXTRA_SUBJECT, "Mivu Coach reply report"),
                hasExtra(Intent.EXTRA_TEXT, "Reason: Wrong or misleading\nNote: Synthetic note\n\nCoach reply:\n$pipReply")), times(1))
        } finally {
            Intents.release()
        }
        compose.waitUntil(5_000) { compose.onAllNodes(hasText("Report this reply?")).fetchSemanticsNodes().isEmpty() }
        val saved = reports().single()
        assertEquals(turn.id.toString(), saved.getString("turnID"))
        assertEquals("Wrong or misleading", saved.getString("reason"))
        assertEquals("Synthetic note", saved.getString("note"))
        assert(Instant.parse(saved.getString("at")) >= now)
    }

    @Test fun cancelSavesAndOpensNothing() {
        seed()
        launch()
        openReport()
        compose.onNodeWithText("Harmful or unsafe").performClick()
        Intents.init()
        try {
            compose.onNodeWithText("Cancel").performClick()
            compose.waitUntil(5_000) { compose.onAllNodes(hasText("Report this reply?")).fetchSemanticsNodes().isEmpty() }
            assertEquals(0, Intents.getIntents().size)
        } finally {
            Intents.release()
        }
        assertEquals(0, reports().size)
    }

    @Test fun noEmailAppKeepsTheReportAndShowsTheAddress() {
        val turn = seed().last()
        startEmailForTest = { throw ActivityNotFoundException() }
        launch()
        openReport()
        compose.onNodeWithText("Something else").performClick()
        compose.onNode(hasText("Report") and hasClickAction()).performClick()
        compose.waitUntil(5_000) { compose.onAllNodes(hasText("Copy address")).fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText("Report saved on this phone. No email app was found, so send it to support@mivuapp.com.").assertIsDisplayed()
        assertEquals(turn.id.toString(), reports().single().getString("turnID"))
        assertEquals("", reports().single().getString("note"))
        compose.onNodeWithText("Copy address").performClick()
        val clipboard = context.getSystemService(ClipboardManager::class.java)
        compose.waitUntil(5_000) { compose.runOnUiThread<String?> { clipboard.primaryClip?.getItemAt(0)?.text?.toString() } == "support@mivuapp.com" }
    }

    @Test fun noEmailAppOffersAShareSheetWithTheSameReport() {
        seed()
        startEmailForTest = { throw ActivityNotFoundException() }
        launch()
        openReport()
        compose.onNodeWithText("Harmful or unsafe").performClick()
        compose.onNode(hasText("Report") and hasClickAction()).performClick()
        compose.waitUntil(5_000) { compose.onAllNodes(hasText("Share")).fetchSemanticsNodes().isNotEmpty() }
        Intents.init()
        try {
            intending(hasAction(Intent.ACTION_CHOOSER)).respondWith(Instrumentation.ActivityResult(Activity.RESULT_OK, null))
            compose.onNodeWithText("Share").performClick()
            compose.waitUntil(5_000) { Intents.getIntents().isNotEmpty() }
            intended(allOf(hasAction(Intent.ACTION_CHOOSER), hasExtra(equalTo(Intent.EXTRA_INTENT), allOf(hasAction(Intent.ACTION_SEND),
                hasExtra(Intent.EXTRA_EMAIL, arrayOf("support@mivuapp.com")),
                hasExtra(Intent.EXTRA_TEXT, "Reason: Harmful or unsafe\n\nCoach reply:\n$pipReply")))), times(1))
        } finally {
            Intents.release()
        }
        assertEquals(1, reports().size)
    }

    @Test fun reportIsATalkBackActionOnPipRepliesOnly() {
        seed()
        launch()
        fun labels(matcher: SemanticsMatcher) = compose.onNode(matcher).fetchSemanticsNode().config[SemanticsActions.CustomActions].map { it.label }
        val actionable = SemanticsMatcher.keyIsDefined(SemanticsActions.CustomActions)
        assertEquals(listOf("Reply", "Copy", "Report reply"), labels(actionable and hasText(pipReply)))
        assertEquals(listOf("Reply", "Copy"), labels(actionable and hasAnyDescendant(hasText("Synthetic breakfast"))))
        val report = compose.onNode(actionable and hasText(pipReply)).fetchSemanticsNode().config[SemanticsActions.CustomActions]
            .single { it.label == "Report reply" }
        compose.runOnUiThread { report.action() }
        compose.waitUntil(5_000) { compose.onAllNodes(hasText("Report this reply?")).fetchSemanticsNodes().isNotEmpty() }
    }
}
