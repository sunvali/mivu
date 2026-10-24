package com.yakov103.mivu.ui.coach

import android.content.ClipboardManager
import android.content.Context
import androidx.activity.ComponentActivity
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertIsDisplayed
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

/** Synthetic diaries only: Reply and Copy from a long press, a swipe, or a TalkBack custom action. */
class CoachReplyActionsTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private val context: Context = ApplicationProvider.getApplicationContext()
    private lateinit var repository: DiaryRepository
    private lateinit var profileID: UUID
    private lateinit var model: CoachViewModel
    private val now = Instant.now().truncatedTo(ChronoUnit.SECONDS)

    @Before fun open() {
        TodayFixture.wipe(context)
        profileID = TodayFixture.diary(context)
        repository = DiaryRepository(context)
    }

    @After fun close() {
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
        model = CoachViewModel(repository, profileID, drain = {}, isConnected = { false },
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
}
