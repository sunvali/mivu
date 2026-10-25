package com.yakov103.mivu.ui.coach

import android.content.Context
import androidx.activity.ComponentActivity
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertHeightIsEqualTo
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.assertWidthIsEqualTo
import androidx.compose.ui.test.getBoundsInRoot
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToIndex
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeDown
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.lifecycle.SavedStateHandle
import androidx.test.core.app.ApplicationProvider
import com.yakov103.mivu.coach.CoachActivity
import com.yakov103.mivu.coach.CoachReplyLines
import com.yakov103.mivu.coach.CoachManualEdit
import com.yakov103.mivu.coach.CoachWrite
import com.yakov103.mivu.diary.CalendarDayRule
import com.yakov103.mivu.diary.CoachDestination
import com.yakov103.mivu.diary.CoachCaptureContext
import com.yakov103.mivu.diary.CoachClarification
import com.yakov103.mivu.diary.CoachPageRequest
import com.yakov103.mivu.diary.CoachQuestion
import com.yakov103.mivu.diary.CoachReceipt
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
import com.yakov103.mivu.diary.coachPage
import com.yakov103.mivu.diary.failCoachTurn
import com.yakov103.mivu.diary.finishCoachTurn
import com.yakov103.mivu.diary.scaleMeal
import com.yakov103.mivu.diary.startDay
import com.yakov103.mivu.ui.theme.MivuTheme
import com.yakov103.mivu.ui.today.TodayFixture
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import java.util.UUID
import kotlin.math.abs
import kotlinx.coroutines.flow.MutableStateFlow
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test

/** Synthetic diaries only, seeded through the 4a store calls; drain is a counter, so no inference runs. */
class CoachScreenTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    @get:Rule val calendarDay = CalendarDayRule()
    private val context: Context = ApplicationProvider.getApplicationContext()
    private lateinit var repository: DiaryRepository
    private lateinit var profileID: UUID
    private val activity = MutableStateFlow<Pair<UUID, CoachActivity>?>(null)
    private var drains = 0
    private var opened: UUID? = null
    private val destinations = mutableListOf<String>()
    private lateinit var model: CoachViewModel
    private val now = Instant.now().truncatedTo(ChronoUnit.SECONDS)
    private val today = LocalDate.now(ZoneId.systemDefault()).toString()

    @Before fun open() {
        TodayFixture.wipe(context)
        profileID = TodayFixture.diary(context)
        repository = DiaryRepository(context)
    }

    @After fun close() {
        db().close()
        TodayFixture.wipe(context)
    }

    private fun db() = repository.database(profileID)

    private fun start(at: Instant = now) = db().startDay(at, db().head().revision)

    private fun launch(fontScale: Float? = null) {
        model = CoachViewModel(repository, profileID, drain = { drains++ }, connected = MutableStateFlow(false), activity = activity, saved = SavedStateHandle())
        compose.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, fontScale ?: density.fontScale)) {
                MivuTheme { CoachScreen(model, onOpenMeal = { opened = it }, onSeeToday = {}, onSeeProgress = {},
                    onOpenConnection = { destinations += "connection" }, onOpenSettings = { destinations += "settings" }) }
            }
        }
        compose.waitUntil(10_000) { model.timeline.value.loaded }
    }

    private fun turn(text: String = "Synthetic breakfast"): CoachTurn {
        val h = db().head()
        return db().captureCoachSubmission(CoachSubmissionPayload(UUID.randomUUID(), text, emptyList(),
            CoachCaptureContext(now, h.profile.timeZoneID, h.activeDayID, h.previousDayConfirmedAt, h.activeConversationSegmentID)), h.revision)
    }

    private fun food() = FoodItem(UUID.randomUUID(), "Synthetic oatmeal", 1.0, "bowl", NutritionValues(427.0, 62.0, 14.0, 13.0),
        NutritionProvenance.estimate, "Synthetic", false, emptyMap())

    /** A finished turn that logged one food, with its receipt. */
    private fun logged(): CoachReceipt {
        val t = turn()
        val receipt = db().applyCoachWrites(t.id, listOf(CoachWrite.Food(today, listOf(food()), null)), at = now).single()
        db().transaction(null) { it.finishCoachTurn(t.id, "Saved — about **430** kcal.") }
        return receipt
    }

    private fun asked(mealID: UUID, kind: CoachClarification = CoachClarification.meal): CoachTurn {
        val t = turn("Synthetic change")
        db().transaction(null) { it.finishCoachTurn(t.id, "Which one?", CoachQuestion(kind, listOf(CoachReply.Target.Meal(mealID)), "Synthetic change")) }
        return t
    }

    private fun seed(count: Int, lastPending: Boolean = false): List<CoachTurn> {
        start()
        val active = db().head().activeDayID
        val turns = List(count) {
            val pending = lastPending && it == count - 1
            CoachTurn(UUID.randomUUID(), now, "Synthetic $it", emptyList(), if (pending) CoachTurnState.captured else CoachTurnState.completed,
                if (pending) null else "Synthetic reply $it", emptyList(), ZoneId.systemDefault().id, active, emptyList())
        }
        db().replaceAll(db().snapshot().copy(revision = db().head().revision.toInt() + 1, coachTurns = turns))
        return turns
    }

    private fun waitForText(text: String) =
        compose.waitUntil(10_000) { compose.onAllNodes(hasText(text, substring = true), useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty() }

    private fun gone(text: String) =
        compose.waitUntil(10_000) { compose.onAllNodes(hasText(text), useUnmergedTree = true).fetchSemanticsNodes().isEmpty() }

    private fun latest() = db().coachPage(CoachPageRequest.Latest).exchanges.last().turn

    @Test fun emptyStateShowsIosCopy() {
        start()
        launch()
        compose.onNodeWithText("What would you like to record?").assertIsDisplayed()
        compose.onNodeWithText("Describe a meal, add a photo, or record a weigh-in or workout. You can review and correct every " +
            "estimate. Coach gives estimates, not medical advice.").assertIsDisplayed()
    }

    @Test fun receiptCardShowsSavedFoodAndMacros() {
        start(); logged()
        launch()
        waitForText("Saved food")
        compose.onNode(hasContentDescription("Synthetic oatmeal, 427 kcal")).assertExists() // title and energy are one stop
        listOf("Carbs 62 g", "Protein 14 g", "Fat 13 g", "Review / Edit", "Undo")
            .forEach { compose.onNode(hasText(it), useUnmergedTree = true).assertExists() }
        compose.onNodeWithText("Saved on this phone").assertDoesNotExist()
    }

    @Test fun undoRestoresAndCardReadsUndone() {
        start(); val receipt = logged()
        launch()
        waitForText("Undo")
        compose.onNodeWithText("Undo").performClick()
        waitForText("Undone")
        gone("Undo")
        assertNull(db().read { it.mealWithoutPhotoBytes(receipt.mealID!!) })
    }

    @Test fun undoHiddenAfterManualEdit() {
        start(); val receipt = logged()
        val meal = db().read { it.mealWithoutPhotoBytes(receipt.mealID!!) }!!
        db().scaleMeal(meal.id, 200.0, meal.revision)
        launch()
        waitForText("Review / Edit")
        compose.onNodeWithText("Undo").assertDoesNotExist()
    }

    @Test fun reviewEditOpensMealDetail() {
        start(); val receipt = logged()
        launch()
        waitForText("Review / Edit")
        compose.onNodeWithText("Review / Edit", useUnmergedTree = true).performClick()
        compose.waitUntil(5_000) { opened != null }
        assertEquals(receipt.mealID, opened)
    }

    @Test fun questionChipsOnlyOnLatestAndSendAnswer() {
        start(); val receipt = logged()
        asked(receipt.mealID!!); asked(receipt.mealID!!)
        launch()
        compose.waitUntil(10_000) { compose.onAllNodesWithTag("coachQuestionChip").fetchSemanticsNodes().isNotEmpty() }
        compose.onAllNodesWithTag("coachQuestionChip").assertCountEquals(1)
        compose.onNodeWithTag("coachQuestionChip").performClick()
        compose.waitUntil(10_000) { latest().text == "Synthetic oatmeal" }
        assertEquals(CoachReply(CoachReply.Target.Meal(receipt.mealID!!), "Synthetic oatmeal"), latest().submissionManifest?.reply)
        compose.waitUntil(5_000) { drains > 0 }
    }

    @Test fun mealChipWithoutPhotoShowsTheMealIcon() {
        start(); val receipt = logged()
        asked(receipt.mealID!!)
        launch()
        compose.waitUntil(10_000) { compose.onAllNodesWithTag("coachPhotoPlaceholder", useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty() }
    }

    @Test fun confirmShowsRemoveAndKeep() {
        start(); val receipt = logged()
        asked(receipt.mealID!!, CoachClarification.confirm)
        launch()
        waitForText("Keep")
        compose.onNodeWithText("Keep").assertIsDisplayed()
        compose.onNodeWithText("Remove").performClick()
        compose.waitUntil(10_000) { latest().text == "Remove it" }
        assertEquals(CoachReply(CoachReply.Target.Meal(receipt.mealID!!), "Synthetic oatmeal"), latest().submissionManifest?.reply)
    }

    @Test fun activityShowsThinking() {
        start(); val t = turn()
        activity.value = t.id to CoachActivity.thinking
        launch()
        waitForText("Thinking…")
        compose.onNode(hasContentDescription("Thinking…, Your message is saved."), useUnmergedTree = true).assertExists()
        compose.onNodeWithText("Saved on this phone").assertExists()
    }

    @Test fun needsRetryShowsTryAgain() {
        start(); val t = turn()
        db().transaction(null) { it.failCoachTurn(t.id, CoachTurnState.needsRetry) }
        launch()
        waitForText("Couldn't finish. Your message is saved.")
        compose.onNodeWithText("Try again").performClick()
        compose.waitUntil(10_000) { latest().state == CoachTurnState.captured && drains > 0 }
    }

    @Test fun dayChoiceLogsToChosenDay() {
        val yesterday = now.minus(1, ChronoUnit.DAYS)
        start(yesterday)
        val t = turn()
        db().transaction(null) { it.failCoachTurn(t.id, CoachTurnState.needsClarification, needsDayChoice = true) }
        launch()
        val previous = "Log to " + CoachReplyLines.shortDate(LocalDate.now(ZoneId.systemDefault()).minusDays(1).toString())
        waitForText(previous)
        compose.onNodeWithText("Log to " + CoachReplyLines.shortDate(today)).assertExists()
        compose.onNodeWithText(previous).performClick()
        compose.waitUntil(10_000) { latest().state == CoachTurnState.captured && drains > 0 }
        assertEquals(t.activeDayID, latest().resolvedDayID)
    }

    @Test fun earlierPagesLoadOnScroll() {
        seed(60)
        launch()
        assertEquals(20, model.timeline.value.exchanges.size)
        compose.waitUntil(20_000) {
            val size = model.timeline.value.exchanges.size
            compose.onNodeWithTag("coachTimeline").performScrollToIndex(size - 1)
            compose.onAllNodes(hasText("Synthetic 0"), useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()
        }
        assertEquals(60, model.timeline.value.exchanges.size)
    }

    @Test fun jumpToLatestAppearsAndReturns() {
        seed(30)
        launch()
        compose.onNodeWithContentDescription("Jump to latest").assertDoesNotExist()
        compose.onNodeWithTag("coachTimeline").performScrollToIndex(15)
        compose.onNodeWithContentDescription("Jump to latest").assertIsDisplayed().performClick()
        compose.waitUntil(10_000) { compose.onAllNodes(hasContentDescription("Jump to latest")).fetchSemanticsNodes().isEmpty() }
        compose.onNodeWithText("Synthetic reply 29").assertIsDisplayed()
    }

    @Test fun jumpToLatestIs48dpWithSpokenLabel() {
        seed(30)
        launch()
        compose.onNodeWithTag("coachTimeline").performScrollToIndex(15)
        compose.onNodeWithContentDescription("Jump to latest")
            .assertWidthIsEqualTo(48.dp).assertHeightIsEqualTo(48.dp)
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button))
            .assert(SemanticsMatcher.keyNotDefined(SemanticsProperties.Focused).or(SemanticsMatcher.expectValue(SemanticsProperties.Focused, false)))
    }

    @Test fun dragOnJumpToLatestScrollsTimeline() {
        seed(30)
        launch()
        compose.onNodeWithTag("coachTimeline").performScrollToIndex(10)
        compose.waitForIdle()
        val before = compose.onNodeWithText("Synthetic 17").getBoundsInRoot().top
        compose.onNodeWithContentDescription("Jump to latest").performTouchInput { swipeDown(startY = centerY, endY = centerY + 300f, durationMillis = 2_000) }
        compose.waitForIdle()
        val after = compose.onNodeWithText("Synthetic 17").getBoundsInRoot().top
        assertTrue("the row moved with the finger: $before -> $after", after - before > 50.dp)
        compose.onNodeWithContentDescription("Jump to latest").assertExists()
    }

    @Test fun replyWhileBrowsingKeepsPositionWithin2dp() {
        val turns = seed(30, lastPending = true)
        launch()
        compose.onNodeWithTag("coachTimeline").performScrollToIndex(12)
        compose.waitForIdle()
        val before = compose.onNodeWithText("Synthetic 16").getBoundsInRoot().top
        db().transaction(null) { it.finishCoachTurn(turns.last().id, "Synthetic reply that is long enough to wrap onto more lines than one. ".repeat(4)) }
        turn("Synthetic new message")
        compose.waitUntil(10_000) { model.timeline.value.exchanges.any { it.turn.state == CoachTurnState.completed && it.turn.id == turns.last().id } }
        compose.waitForIdle()
        val after = compose.onNodeWithText("Synthetic 16").getBoundsInRoot().top
        assertTrue("moved ${abs((after - before).value)} dp", abs((after - before).value) <= 2f)
        compose.onNodeWithContentDescription("Jump to latest").assertIsDisplayed()
    }

    @Test fun largeFontStacksUndo() {
        start(); logged()
        launch(fontScale = 2f)
        waitForText("Undo")
        compose.onNodeWithTag("coachTimeline").performScrollToIndex(0)
        val review = compose.onNodeWithText("Review / Edit", useUnmergedTree = true).getBoundsInRoot()
        val undo = compose.onNodeWithText("Undo", useUnmergedTree = true).getBoundsInRoot()
        assertTrue("Undo $undo sits below Review / Edit $review", undo.top >= review.bottom)
    }

    /** A finished turn whose receipt hands off to [destination]. */
    private fun handoff(destination: CoachDestination, reply: String) {
        val t = turn("Synthetic help")
        db().applyCoachWrites(t.id, listOf(CoachWrite.Manual(CoachManualEdit.Open(destination))), at = now)
        db().transaction(null) { it.finishCoachTurn(t.id, reply) }
    }

    @Test fun connectionReceiptOpensConnection() {
        start()
        handoff(CoachDestination.settings, "Synthetic settings reply")
        handoff(CoachDestination.connection, "Synthetic connection reply")
        launch()
        waitForText("Synthetic connection reply")
        compose.onNodeWithText("Open ChatGPT connection").assertHeightIsAtLeast(48.dp).performClick()
        compose.onNodeWithText("Open Settings").assertHeightIsAtLeast(48.dp).performClick()
        assertEquals(listOf("connection", "settings"), destinations)
    }

    @Test fun unsupportedDestinationShowsNoLink() {
        start()
        handoff(CoachDestination.profiles, "Synthetic profiles reply")
        launch()
        waitForText("Synthetic profiles reply")
        compose.onNodeWithText("Open local profiles").assertDoesNotExist()
        compose.onNodeWithText("Open Settings").assertDoesNotExist()
        compose.onNodeWithText("Open ChatGPT connection").assertDoesNotExist()
    }
}
