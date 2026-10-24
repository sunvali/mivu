package com.yakov103.mivu.ui.coach

import android.content.Context
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasAnyDescendant
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasStateDescription
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import androidx.lifecycle.ViewModelProvider
import androidx.test.core.app.ApplicationProvider
import com.yakov103.mivu.coach.CoachWrite
import com.yakov103.mivu.diary.Bootstrap
import com.yakov103.mivu.diary.CoachCaptureContext
import com.yakov103.mivu.diary.CoachReply
import com.yakov103.mivu.diary.CoachSubmissionPayload
import com.yakov103.mivu.diary.CoachTurn
import com.yakov103.mivu.diary.CoachTurnState
import com.yakov103.mivu.diary.DiaryRepository
import com.yakov103.mivu.diary.FoodItem
import com.yakov103.mivu.diary.NutritionProvenance
import com.yakov103.mivu.diary.NutritionValues
import com.yakov103.mivu.diary.applyCoachWrites
import com.yakov103.mivu.diary.captureCoachSubmission
import com.yakov103.mivu.diary.finishCoachTurn
import com.yakov103.mivu.diary.startDay
import com.yakov103.mivu.ui.MivuApp
import com.yakov103.mivu.ui.theme.MivuTheme
import com.yakov103.mivu.ui.today.TodayFixture
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import java.util.UUID
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test

/** Synthetic diaries only; the app shell drives the Coach bar, history route and meal Ask Pip. */
class CoachHistoryScreenTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private val context: Context = ApplicationProvider.getApplicationContext()
    private lateinit var repository: DiaryRepository
    private lateinit var profileID: UUID
    private val now = Instant.now().truncatedTo(ChronoUnit.SECONDS)
    private val zone = ZoneId.systemDefault()
    private val today = LocalDate.now(zone).toString()

    @Before fun open() {
        TodayFixture.wipe(context)
        profileID = TodayFixture.diary(context)
        repository = DiaryRepository(context)
    }

    @After fun close() {
        CoachViewModel.readPageForTest = null
        (repository.bootstrapState.value as? Bootstrap.Ready)?.let { repository.database(it.profileID).close() }
        TodayFixture.wipe(context)
    }

    private fun db() = repository.database(profileID)

    private fun launchApp(tab: String? = "Coach") {
        compose.activityRule.scenario.onActivity { it.setContent { MivuTheme { MivuApp(repository) } } }
        compose.waitUntil(10_000) { exists(hasText("Coach")) }
        if (tab != null) {
            compose.onNodeWithText(tab).performClick()
            compose.waitUntil(10_000) { model().timeline.value.loaded }
        }
    }

    private fun model(): CoachViewModel {
        lateinit var model: CoachViewModel
        compose.activityRule.scenario.onActivity { model = ViewModelProvider(it)["coach-$profileID", CoachViewModel::class.java] }
        return model
    }

    private fun exists(matcher: SemanticsMatcher) = compose.onAllNodes(matcher, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()

    private fun waitFor(matcher: SemanticsMatcher) = compose.waitUntil(10_000) { exists(matcher) }

    private fun openHistory() {
        compose.onNodeWithContentDescription("Chat history").performClick()
        waitFor(hasText("Chat history"))
    }

    private fun synthetic(text: String, at: Instant, zone: String = this.zone.id, day: UUID? = null, segment: UUID? = UUID.randomUUID()) =
        CoachTurn(UUID.randomUUID(), at, text, emptyList(), CoachTurnState.completed, "Reply to $text", emptyList(), zone, day, emptyList(),
            captureSegmentID = segment)

    /** Appends [turns] after the stored ones, in order. */
    private fun append(turns: List<CoachTurn>): List<CoachTurn> {
        val snapshot = db().snapshot()
        db().replaceAll(snapshot.copy(revision = db().head().revision.toInt() + 1, coachTurns = snapshot.coachTurns + turns))
        return turns
    }

    /** One conversation per turn, [count] days apart, oldest first: "Synthetic visit 0" is the oldest. */
    private fun visits(count: Int) = append(List(count) { synthetic("Synthetic visit $it", now.minus((count - it).toLong(), ChronoUnit.DAYS)) })

    /** [count] turns in one conversation on the active day. */
    private fun chat(count: Int): List<CoachTurn> {
        db().startDay(now, db().head().revision)
        val day = db().head().activeDayID
        val segment = UUID.randomUUID()
        return append(List(count) { synthetic("Synthetic $it", now, day = day, segment = segment) })
    }

    private fun highlighted(id: UUID) {
        compose.waitUntil(10_000) { model().timeline.value.highlighted == id }
        val text = model().timeline.value.exchanges.first { it.turn.id == id }.turn.text
        compose.waitUntil(10_000) {
            runCatching {
                compose.onNode(hasStateDescription("Selected source message") and hasAnyDescendant(hasText(text))).assertIsDisplayed()
            }.isSuccess
        }
    }

    @Test fun listsNewestFirstWithCaptureLabel() {
        val london = Instant.parse("2026-10-24T07:12:05Z")
        append(listOf(
            synthetic("Greek yogurt with berries and honey", Instant.parse("2026-10-22T11:05:44Z"), "Europe/Paris"),
            synthetic("Oatmeal with banana and a coffee with oat milk", london, "Europe/London"),
        ))
        launchApp()
        openHistory()
        waitFor(hasText("Oatmeal with banana and a coffee with oat milk"))
        compose.onNodeWithText("24 Oct 2026, 08:12:05 · Europe/London").assertIsDisplayed()
        compose.onNodeWithText("22 Oct 2026, 13:05:44 · Europe/Paris").assertIsDisplayed()
        val newest = compose.onNodeWithText("2026-10-24").fetchSemanticsNode().boundsInRoot.top
        val older = compose.onNodeWithText("2026-10-22").fetchSemanticsNode().boundsInRoot.top
        assertTrue("newest first: $newest < $older", newest < older)
    }

    @Test fun earlierConversationsLoadsNextPage() {
        visits(35)
        launchApp()
        openHistory()
        waitFor(hasText("Synthetic visit 34"))
        compose.onNodeWithText("Synthetic visit 4").assertDoesNotExist()
        compose.onNodeWithTag("coachHistoryList").performScrollToNode(hasText("Earlier conversations"))
        compose.onNodeWithText("Earlier conversations").performClick()
        waitFor(hasText("Synthetic visit 4"))
        compose.onNodeWithText("Synthetic visit 0").assertExists()
        compose.onNodeWithText("Synthetic visit 34").assertDoesNotExist() // each screenful stays one bounded page
        compose.onNodeWithText("Earlier conversations").assertDoesNotExist()
    }

    @Test fun chooseDateFiltersAndShowAllClears() {
        append(listOf(
            synthetic("Synthetic older visit", now.minus(3, ChronoUnit.DAYS)),
            synthetic("Synthetic morning visit", now),
            synthetic("Synthetic evening visit", now), // a separate visit on the same date stays a separate row
        ))
        launchApp()
        openHistory()
        waitFor(hasText("Synthetic older visit"))
        compose.onNodeWithContentDescription("Choose date").performClick()
        waitFor(hasText("Choose the date shown in your conversation. Separate visits remain separate choices."))
        compose.onNodeWithText("Show date").performClick()
        waitFor(hasText("Selected date"))
        compose.onNode(hasText("Selected date") and hasText(today)).assertExists()
        compose.onNodeWithText("Synthetic morning visit").assertExists()
        compose.onNodeWithText("Synthetic evening visit").assertExists()
        compose.onNodeWithText("Synthetic older visit").assertDoesNotExist()
        compose.onNodeWithText("Show all chat history").performClick()
        waitFor(hasText("Synthetic older visit"))
        compose.onNodeWithText("Selected date").assertDoesNotExist()
    }

    @Test fun emptyAndFilteredEmptyCopy() {
        launchApp()
        openHistory()
        waitFor(hasText("No saved chat"))
        compose.onNodeWithText("Your saved conversations will appear here.").assertIsDisplayed()
        compose.onNodeWithContentDescription("Choose date").performClick()
        compose.onNodeWithText("Show date").performClick()
        waitFor(hasText("No chat for this date"))
        compose.onNodeWithText("No saved conversation is labeled $today.").assertIsDisplayed()
    }

    @Test fun rowSeeksAndHighlightsFirstMessage() {
        val turns = visits(35)
        launchApp()
        openHistory()
        compose.waitUntil(10_000) { exists(hasTestTag("coachHistoryList")) }
        compose.onNodeWithTag("coachHistoryList").performScrollToNode(hasText("Synthetic visit 6"))
        compose.onNodeWithText("Synthetic visit 6").performClick()
        waitFor(hasTestTag("coachTimeline"))
        highlighted(turns[6].id)
        assertTrue(model().timeline.value.exchanges.none { it.turn.id == turns.last().id }) // the window moved to that conversation
    }

    @Test fun sentQuoteSeeksOriginalMessage() {
        val turns = chat(30)
        val h = db().head()
        db().captureCoachSubmission(CoachSubmissionPayload(UUID.randomUUID(), "Synthetic follow-up", emptyList(),
            CoachCaptureContext(now, h.profile.timeZoneID, h.activeDayID, h.previousDayConfirmedAt, h.activeConversationSegmentID),
            reply = CoachReply(CoachReply.Target.Message(turns[2].id, fromPip = false), "Synthetic 2")), h.revision)
        launchApp()
        waitFor(hasContentDescription("Reply to your message: Synthetic 2"))
        compose.onNode(hasContentDescription("Reply to your message: Synthetic 2"), useUnmergedTree = true)
            .assert(SemanticsMatcher("hint Shows the original") { it.config.getOrNull(SemanticsActions.OnClick)?.label == "Shows the original" })
            .performClick()
        highlighted(turns[2].id)
    }

    @Test fun mealAskPipSeeksSourceTurn() {
        db().startDay(now, db().head().revision)
        val h = db().head()
        val source = db().captureCoachSubmission(CoachSubmissionPayload(UUID.randomUUID(), "Synthetic oatmeal breakfast", emptyList(),
            CoachCaptureContext(now, h.profile.timeZoneID, h.activeDayID, h.previousDayConfirmedAt, h.activeConversationSegmentID)), h.revision)
        val food = FoodItem(UUID.randomUUID(), "Synthetic oatmeal", 1.0, "bowl", NutritionValues(427.0, 62.0, 14.0, 13.0),
            NutritionProvenance.estimate, "Synthetic", false, emptyMap())
        val mealID = db().applyCoachWrites(source.id, listOf(CoachWrite.Food(today, listOf(food), null)), at = now).single().mealID!!
        db().transaction(null) { it.finishCoachTurn(source.id, "Saved.") }
        append(List(30) { synthetic("Synthetic later $it", now, day = h.activeDayID) })
        launchApp(tab = null)
        waitFor(hasText("Synthetic oatmeal"))
        compose.onNodeWithText("Synthetic oatmeal").performClick()
        waitFor(hasTestTag("mealAskPip"))
        compose.onNodeWithTag("mealAskPip").performClick()
        waitFor(hasTestTag("coachTimeline"))
        highlighted(source.id)
        assertEquals(CoachReply.Target.Meal(mealID), model().draft.value.reply?.target) // the quote was taken first
    }

    @Test fun seekWhilePagingStaysWithinWindow() {
        val turns = chat(120)
        launchApp()
        val model = model()
        compose.runOnUiThread {
            val visible = setOf(model.timeline.value.exchanges.last().turn.id)
            model.loadEarlier(visible)
            model.seek(CoachSeekTarget.Turn(turns[3].id))
            model.loadEarlier(visible)
            model.seek(CoachSeekTarget.Turn(turns[60].id))
        }
        highlighted(turns[60].id)
        repeat(6) {
            compose.runOnUiThread {
                val state = model.timeline.value
                model.loadEarlier(state.exchanges.take(1).map { it.turn.id }.toSet())
                model.loadLater(state.exchanges.takeLast(1).map { it.turn.id }.toSet())
            }
            compose.waitForIdle()
            assertTrue(model.timeline.value.exchanges.size <= CoachHistoryWindow.maximumExchanges)
        }
        assertTrue(model.timeline.value.exchanges.map { it.ordinal }.zipWithNext().all { (a, b) -> a < b })
    }

    @Test fun invalidSeekPageKeepsWindow() {
        val turns = chat(40)
        launchApp()
        val before = model().timeline.value.exchanges.map { it.turn.id }
        // Out of order: the window must refuse it.
        CoachViewModel.readPageForTest = { request, page ->
            if (request is com.yakov103.mivu.diary.CoachPageRequest.AroundTurn) page.copy(exchanges = page.exchanges.reversed()) else page
        }
        compose.runOnUiThread { model().seek(CoachSeekTarget.Turn(turns[3].id)) }
        compose.waitUntil(10_000) { model().message.value == "The conversation page was invalid. Try again." }
        assertEquals(before, model().timeline.value.exchanges.map { it.turn.id })
        assertEquals(null, model().timeline.value.highlighted)
    }

    @Test fun historyButtonHasPagingActions() {
        chat(30)
        launchApp()
        val button = compose.onNodeWithContentDescription("Chat history")
        compose.waitUntil(10_000) {
            button.fetchSemanticsNode().config.getOrNull(SemanticsActions.CustomActions).orEmpty().any { it.label == "Load earlier messages" }
        }
        val actions = button.fetchSemanticsNode().config[SemanticsActions.CustomActions]
        assertTrue(actions.none { it.label == "Load later messages" })
        compose.runOnUiThread { actions.first { it.label == "Load earlier messages" }.action() }
        compose.waitUntil(10_000) { model().timeline.value.exchanges.size == 30 }
        compose.waitUntil(10_000) { button.fetchSemanticsNode().config.getOrNull(SemanticsActions.CustomActions).isNullOrEmpty() }
    }

    @Test fun backReturnsToCoachUnchanged() {
        chat(30)
        launchApp()
        val before = model().timeline.value.exchanges.map { it.turn.id }
        openHistory()
        waitFor(hasText("Synthetic 0"))
        compose.activityRule.scenario.onActivity { it.onBackPressedDispatcher.onBackPressed() }
        waitFor(hasTestTag("coachTimeline"))
        compose.onNodeWithText("Synthetic 29").assertIsDisplayed()
        assertEquals(before, model().timeline.value.exchanges.map { it.turn.id })
        assertEquals(null, model().timeline.value.highlighted)
        assertTrue(compose.onAllNodes(hasText("Chat history") and SemanticsMatcher.keyIsDefined(SemanticsProperties.Heading)).fetchSemanticsNodes().isEmpty())
    }
}
