package com.yakov103.mivu.ui.meal

import android.content.Context
import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.doubleClick
import androidx.compose.ui.test.pinch
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isDialog
import androidx.compose.ui.test.isHeading
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextReplacement
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeLeft
import androidx.lifecycle.SavedStateHandle
import androidx.test.core.app.ApplicationProvider
import com.yakov103.mivu.analysis.MealAnalysisWorker
import com.yakov103.mivu.analysis.SampleAnalyzer
import com.yakov103.mivu.diary.DiaryMeal
import com.yakov103.mivu.diary.DiaryRepository
import com.yakov103.mivu.diary.FoodItem
import com.yakov103.mivu.diary.MealPhoto
import com.yakov103.mivu.diary.MealSubmission
import com.yakov103.mivu.diary.MealTimePrecision
import com.yakov103.mivu.diary.NutritionProvenance
import com.yakov103.mivu.diary.NutritionValues
import com.yakov103.mivu.diary.PhotoRole
import com.yakov103.mivu.diary.SubmissionState
import com.yakov103.mivu.diary.captureProjection
import com.yakov103.mivu.diary.deleteMeal
import com.yakov103.mivu.diary.startDay
import com.yakov103.mivu.ui.MivuApp
import com.yakov103.mivu.ui.coach.AskPip
import com.yakov103.mivu.ui.theme.MivuTheme
import com.yakov103.mivu.ui.today.TodayFixture
import java.time.Instant
import java.time.temporal.ChronoUnit
import java.util.UUID
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.flow.MutableStateFlow
import com.yakov103.mivu.diary.CoachTurn
import com.yakov103.mivu.diary.CoachTurnState
import com.yakov103.mivu.ui.coach.CoachViewModel
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test

class MealDetailScreenTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private val context: Context = ApplicationProvider.getApplicationContext()
    private lateinit var repository: DiaryRepository
    private lateinit var profileID: UUID
    private var wentBack = false
    private var asked: AskPip? = null

    @Before fun wipe() {
        TodayFixture.wipe(context)
        profileID = TodayFixture.diary(context)
        repository = DiaryRepository(context)
        db().startDay(Instant.now().truncatedTo(ChronoUnit.SECONDS), db().head().revision)
    }

    @After fun close() {
        db().close()
        TodayFixture.wipe(context)
    }

    private fun db() = repository.database(profileID)

    private fun food(name: String, kcal: Double, p: Double, c: Double, f: Double, quantity: Double = 1.0, unit: String = "serving",
                     uncertain: Boolean = false) =
        FoodItem(UUID.randomUUID(), name, quantity, unit, NutritionValues(kcal, c, p, f), NutritionProvenance.user, "Entered manually",
            uncertain, emptyMap())

    /** A saved meal on the active day, written through the store. */
    private fun savedMeal(vararg items: FoodItem, photos: Int = 0): DiaryMeal {
        val at = Instant.now().truncatedTo(ChronoUnit.SECONDS).minus(1, ChronoUnit.HOURS)
        val pictures = List(photos) { MealPhoto(UUID.randomUUID(), TodayFixture.plateJpeg(), at, PhotoRole.unspecified) }
        val meal = DiaryMeal(UUID.randomUUID(), db().head().activeDayID!!, at, at, 1, timePrecision = MealTimePrecision.exact,
            items = items.toList(), photos = pictures,
            submissions = listOf(MealSubmission(UUID.randomUUID(), 0, "", pictures.map { it.id }, false, SubmissionState.saved)))
        db().transaction(db().head().revision) { it.putMeal(meal) }
        return meal
    }

    private fun meal(id: UUID) = db().read { it.meal(id) }

    private fun open(mealID: UUID, onRetryAnalysis: () -> Unit = {}) {
        val model = MealDetailViewModel(repository, profileID, mealID, sampleMode = false, SavedStateHandle())
        compose.setContent {
            MivuTheme { MealDetailScreen(model, onBack = { wentBack = true }, onAskPip = { asked = it }, onAddFoodManually = {}, onRetryAnalysis = onRetryAnalysis) }
        }
    }

    private fun waitFor(matcher: SemanticsMatcher) =
        compose.waitUntil(10_000) { compose.onAllNodes(matcher, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty() }
    private fun waitGone(matcher: SemanticsMatcher) =
        compose.waitUntil(10_000) { compose.onAllNodes(matcher, useUnmergedTree = true).fetchSemanticsNodes().isEmpty() }
    private fun deleteAction() = SemanticsMatcher("has Delete action") { node ->
        node.config.getOrNull(SemanticsActions.CustomActions).orEmpty().any { it.label == "Delete" }
    }

    @Test fun showsFoodsAndTotals() {
        val meal = savedMeal(food("Greek yogurt", 190.0, 17.0, 8.0, 5.0, 200.0, "g"), food("Blueberries", 46.0, 0.6, 11.5, 0.3, 80.0, "g"),
            food("Honey", 74.0, 0.4, 13.0, 3.8, 1.0, "tbsp", uncertain = true))
        open(meal.id)
        waitFor(hasText("Greek yogurt") and isHeading())
        compose.onNodeWithText("Saved on this phone").assertIsDisplayed()
        compose.onNodeWithText("310").assertIsDisplayed()
        compose.onNodeWithText("18.0 g").assertIsDisplayed()
        compose.onNodeWithText("32.5 g").assertIsDisplayed()
        compose.onNodeWithText("9.1 g").assertIsDisplayed()
        compose.onNodeWithTag("adjustMealTotal").assertIsDisplayed()
        compose.onNodeWithText("Foods").performScrollTo()
        compose.onNodeWithText("200 g", substring = true).assertIsDisplayed()
        compose.onNodeWithText("Portion or nutrients are uncertain", substring = true).performScrollTo().assertIsDisplayed()
        compose.onNodeWithText("74 kcal").assertIsDisplayed()
        compose.onNodeWithTag("addFoodManually").performScrollTo().assertIsDisplayed()
        compose.onNodeWithTag("mealAskPip").assertIsDisplayed()
    }

    @Test fun askPipQuotesMealAndFood() {
        val honey = food("Honey", 74.0, 0.4, 13.0, 3.8)
        val meal = savedMeal(food("Greek yogurt", 190.0, 17.0, 8.0, 5.0), honey)
        open(meal.id)
        waitFor(hasTestTag("mealAskPip"))
        compose.onNodeWithTag("mealAskPip").performClick()
        assertEquals(meal.id, (asked as AskPip.Meal).mealID)
        compose.onNodeWithContentDescription("Ask Pip about Honey").performScrollTo().performClick()
        val food = asked as AskPip.Food
        assertEquals(listOf(meal.id, honey.id, "Honey"), listOf(food.mealID, food.itemID, food.name))
        assertEquals(db().read { it.day(meal.dayID) }!!.localDate, food.dayLocalDate)
    }

    @Test fun deleteFoodConfirmsAndRemoves() {
        val meal = savedMeal(food("Greek yogurt", 190.0, 17.0, 8.0, 5.0), food("Blueberries", 46.0, 0.6, 11.5, 0.3))
        open(meal.id)
        waitFor(hasText("Blueberries"))
        compose.onAllNodesWithTag("editItem")[1].performScrollTo().performTouchInput { swipeLeft() }
        waitFor(isDialog())
        compose.onNodeWithText("Delete Blueberries?").assertIsDisplayed()
        compose.onNodeWithText("Only this food is removed. The meal keeps its other foods.").assertIsDisplayed()
        compose.onNodeWithTag("confirmDeleteFood").performClick()
        waitGone(hasText("Blueberries"))
        assertEquals(listOf("Greek yogurt"), meal(meal.id)!!.items.map { it.name })
    }

    @Test fun deleteFoodHiddenForSingleFood() {
        val meal = savedMeal(food("Greek yogurt", 190.0, 17.0, 8.0, 5.0))
        open(meal.id)
        waitFor(hasTestTag("editItem"))
        assertTrue(compose.onAllNodes(hasTestTag("editItem") and deleteAction()).fetchSemanticsNodes().isEmpty())
        compose.onNodeWithTag("editItem").performTouchInput { swipeLeft() }
        compose.waitForIdle()
        assertTrue(compose.onAllNodes(isDialog()).fetchSemanticsNodes().isEmpty())
        assertEquals(1, meal(meal.id)!!.items.size)
    }

    @Test fun deleteMealConfirmsAndReturns() {
        val meal = savedMeal(food("Greek yogurt", 190.0, 17.0, 8.0, 5.0))
        open(meal.id)
        waitFor(hasText("Greek yogurt") and isHeading())
        compose.onNodeWithTag("mealActions").performClick()
        compose.onNodeWithTag("deleteMeal").performClick()
        val date = db().read { it.day(meal.dayID)!!.localDate }
        compose.onNodeWithText("Delete “Greek yogurt” on $date?").assertIsDisplayed()
        compose.onNodeWithText("This removes the meal and its attached photos from this diary.").assertIsDisplayed()
        compose.onNodeWithTag("confirmDeleteMeal").performClick()
        compose.waitUntil(10_000) { wentBack }
        assertNull(meal(meal.id))
    }

    @Test fun photoViewerDeleteKeepsMeal() {
        val meal = savedMeal(food("Greek yogurt", 190.0, 17.0, 8.0, 5.0), photos = 1)
        open(meal.id)
        waitFor(hasTestTag("viewMealPhoto"))
        compose.onAllNodesWithTag("viewMealPhoto").onFirst().performClick()
        waitFor(hasTestTag("deleteViewedPhoto"))
        compose.onNodeWithTag("zoomInPhoto").performClick()
        compose.onNodeWithText("200%").assertIsDisplayed()
        compose.onNodeWithTag("deleteViewedPhoto").performClick()
        compose.onNodeWithText("Delete this photo?").assertIsDisplayed()
        compose.onNodeWithText("Only this photo will be removed. The meal and its notes are kept.").assertIsDisplayed()
        compose.onNodeWithTag("confirmDeletePhoto").performClick()
        waitGone(hasTestTag("deleteViewedPhoto"))
        waitGone(hasTestTag("viewMealPhoto"))
        compose.onNode(hasText("Greek yogurt") and isHeading()).assertIsDisplayed()
        assertEquals(0, meal(meal.id)!!.photos.size)
        assertEquals(1, meal(meal.id)!!.items.size)
    }

    @Test fun photoViewerZoomsAroundTheTapAndHidesUnsetTiming() {
        val meal = savedMeal(food("Greek yogurt", 190.0, 17.0, 8.0, 5.0), photos = 1)
        open(meal.id)
        waitFor(hasTestTag("viewMealPhoto"))
        assertTrue(compose.onAllNodes(hasText("Timing unspecified")).fetchSemanticsNodes().isEmpty())
        compose.onAllNodesWithTag("viewMealPhoto").onFirst().performClick()
        waitFor(hasTestTag("mealPhotoZoom"))
        assertTrue(compose.onAllNodes(hasText("Photo timing", substring = true)).fetchSemanticsNodes().isEmpty())
        compose.onNodeWithTag("mealPhotoZoom").performTouchInput { doubleClick(Offset(width * 0.75f, height * 0.5f)) }
        compose.onNodeWithText("200%").assertIsDisplayed()
        compose.onNodeWithTag("mealPhotoZoom").assert(SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, "Zoom 200 percent"))
        compose.onNodeWithTag("mealPhotoZoom").performTouchInput { doubleClick(center) }
        compose.onNodeWithText("100%").assertIsDisplayed()
        compose.onNodeWithTag("mealPhotoZoom").performTouchInput { pinch(Offset(width * 0.45f, height * 0.5f), Offset(width * 0.55f, height * 0.5f),
            Offset(width * 0.3f, height * 0.5f), Offset(width * 0.7f, height * 0.5f)) }
        compose.waitUntil(5_000) { compose.onAllNodes(hasText("100%")).fetchSemanticsNodes().isEmpty() }
    }

    @Test fun markReviewedSavesProposal() {
        val at = Instant.now().truncatedTo(ChronoUnit.SECONDS)
        db().captureProjection("Afternoon snack", listOf(MealPhoto(UUID.randomUUID(), TodayFixture.plateJpeg(), at, PhotoRole.unspecified)),
            reviewFirst = true, dayID = db().head().activeDayID!!, at = at, expectedRevision = db().head().revision)
        runBlocking { MealAnalysisWorker(repository, SampleAnalyzer::analyze).drain(profileID) }
        val mealID = db().read { tx -> tx.dayMeals(tx.head.activeDayID!!).single().id }
        assertEquals(SubmissionState.awaitingReview, meal(mealID)!!.submissions.last().state)
        open(mealID)
        waitFor(hasText("Review estimate"))
        compose.onNodeWithText("Check the portions before marking this reviewed. This proposal does not count in totals until you save it.")
            .performScrollTo().assertIsDisplayed()
        compose.onNodeWithTag("acceptReview").performClick()
        waitGone(hasText("Review estimate"))
        val saved = meal(mealID)!!
        assertEquals(SubmissionState.saved, saved.submissions.last().state)
        assertEquals(saved.submissions.last().proposal!!.items, saved.items)
    }

    @Test fun deletedMealShowsUnavailable() {
        val meal = savedMeal(food("Greek yogurt", 190.0, 17.0, 8.0, 5.0))
        open(meal.id)
        waitFor(hasText("Greek yogurt") and isHeading())
        db().deleteMeal(meal.id, db().head().revision)
        waitFor(hasText("Meal unavailable"))
        compose.onNodeWithText("It may have been deleted or belong to another profile.").assertIsDisplayed()
    }

    @Test fun addFoodManuallyAppendsToMeal() {
        val meal = savedMeal(food("Greek yogurt", 190.0, 17.0, 8.0, 5.0))
        compose.setContent { MivuTheme { MivuApp(repository) } }
        waitFor(hasTestTag("mealRow"))
        compose.onAllNodesWithTag("mealRow").onFirst().performClick()
        waitFor(hasTestTag("addFoodManually"))
        compose.onNodeWithTag("addFoodManually").performScrollTo().performClick()
        waitFor(hasTestTag("manualFoodName"))
        compose.onNode(hasText("Add food manually") and hasAnyAncestor(isDialog())).assertIsDisplayed()
        compose.onNodeWithTag("manualFoodName").performTextReplacement("Blueberries")
        compose.onNodeWithTag("manualCalories").performTextReplacement("46")
        compose.onNodeWithTag("saveManualNutrition").performClick()
        waitGone(hasTestTag("manualFoodName"))
        waitFor(hasText("Blueberries"))
        compose.onNode(hasText("Greek yogurt") and isHeading()).assertIsDisplayed()
        assertEquals(listOf("Greek yogurt", "Blueberries"), meal(meal.id)!!.items.map { it.name })
    }

    private fun captured(): DiaryMeal = db().head().let {
        db().captureProjection("Synthetic eggs and toast", emptyList(), false, it.activeDayID!!, Instant.now().truncatedTo(ChronoUnit.SECONDS),
            expectedRevision = it.revision)
    }

    private fun coach() = CoachViewModel(repository, profileID, drain = {}, connected = MutableStateFlow(true),
        activity = MutableStateFlow(null), saved = SavedStateHandle())

    private fun retry() {
        waitFor(hasText("Synthetic eggs and toast", substring = true))
        compose.onNodeWithTag("mealActions").performClick()
        waitFor(hasText("Retry analysis"))
        compose.onNodeWithText("Retry analysis").performClick()
    }

    @Test fun liveRetryAnalysisRerunsSameTurn() {
        val meal = captured()
        val turn = CoachTurn(meal.submissions.single().id, meal.capturedAt, "Synthetic eggs and toast", emptyList(), CoachTurnState.needsRetry,
            null, emptyList(), "UTC", meal.dayID, emptyList(), pendingMealID = meal.id, pendingMealRevision = 0)
        db().replaceAll(db().snapshot().let { it.copy(coachTurns = it.coachTurns + turn) })
        val coach = coach()
        open(meal.id) { coach.retryMeal(meal.id) }
        retry()
        compose.waitUntil(10_000) { db().coachTurnsWithoutPhotos().single().state == CoachTurnState.captured }
        assertEquals(listOf(turn.id), db().coachTurnsWithoutPhotos().map { it.id })
        assertNull(coach.message.value)
    }

    @Test fun retryWithoutTurnShowsMealChanged() {
        val meal = captured()
        val coach = coach()
        open(meal.id) { coach.retryMeal(meal.id) }
        retry()
        compose.waitUntil(10_000) { coach.message.value == "This meal changed. Review it before retrying its earlier input." }
        assertTrue(db().coachTurnsWithoutPhotos().isEmpty())
    }
}
