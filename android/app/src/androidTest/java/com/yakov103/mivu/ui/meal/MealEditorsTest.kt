package com.yakov103.mivu.ui.meal

import android.content.Context
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertTextContains
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isHeading
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextReplacement
import androidx.lifecycle.SavedStateHandle
import androidx.test.core.app.ApplicationProvider
import com.yakov103.mivu.diary.DayCompleteness
import com.yakov103.mivu.diary.DiaryMeal
import com.yakov103.mivu.diary.DiaryRepository
import com.yakov103.mivu.diary.FoodItem
import com.yakov103.mivu.diary.MealSubmission
import com.yakov103.mivu.diary.MealTimePrecision
import com.yakov103.mivu.diary.NutritionProvenance
import com.yakov103.mivu.diary.NutritionValues
import com.yakov103.mivu.diary.SubmissionState
import com.yakov103.mivu.diary.TrackingDay
import com.yakov103.mivu.diary.diaryWeek
import com.yakov103.mivu.diary.scaleMeal
import com.yakov103.mivu.diary.startDay
import com.yakov103.mivu.ui.MivuApp
import com.yakov103.mivu.ui.theme.MivuTheme
import com.yakov103.mivu.ui.today.TodayFixture
import java.time.Instant
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.Locale
import java.util.UUID
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Rule
import org.junit.Test

class MealEditorsTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private val context: Context = ApplicationProvider.getApplicationContext()
    private lateinit var repository: DiaryRepository
    private lateinit var profileID: UUID

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

    private fun food(name: String, kcal: Double, quantity: Double, unit: String = "g") =
        FoodItem(UUID.randomUUID(), name, quantity, unit, NutritionValues(kcal, kcal / 10, kcal / 20, kcal / 40), NutritionProvenance.user,
            "Entered manually", false, emptyMap())

    private fun savedMeal(vararg items: FoodItem): DiaryMeal {
        val at = Instant.now().truncatedTo(ChronoUnit.SECONDS).minus(1, ChronoUnit.HOURS)
        val meal = DiaryMeal(UUID.randomUUID(), db().head().activeDayID!!, at, at, 1, timePrecision = MealTimePrecision.exact,
            items = items.toList(), photos = emptyList(), submissions = listOf(MealSubmission(UUID.randomUUID(), 0, "", emptyList(), false, SubmissionState.saved)))
        db().transaction(db().head().revision) { it.putMeal(meal) }
        return meal
    }

    private fun meal(id: UUID) = db().read { it.meal(id) }!!

    private fun open(mealID: UUID) {
        val model = MealDetailViewModel(repository, profileID, mealID, sampleMode = false, SavedStateHandle())
        compose.setContent { MivuTheme { MealDetailScreen(model, onBack = {}, onAskPip = {}, onAddFoodManually = {}) } }
    }

    private fun waitFor(matcher: SemanticsMatcher) =
        compose.waitUntil(10_000) { compose.onAllNodes(matcher, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty() }
    private fun waitGone(matcher: SemanticsMatcher) =
        compose.waitUntil(10_000) { compose.onAllNodes(matcher, useUnmergedTree = true).fetchSemanticsNodes().isEmpty() }

    @Test fun editFoodSavesAndUpdatesTotals() {
        val meal = savedMeal(food("Greek yogurt", 190.0, 200.0), food("Blueberries", 46.0, 80.0))
        open(meal.id)
        waitFor(hasTestTag("editItem"))
        compose.onAllNodesWithTag("editItem").onFirst().performScrollTo().performClick()
        waitFor(hasTestTag("itemQuantity"))
        compose.onNodeWithText("Edit food").assertIsDisplayed()
        compose.onNodeWithTag("itemQuantity").performTextReplacement("400")
        waitFor(hasTestTag("foodPreviewCalories") and hasContentDescription("380 kcal"))
        compose.onNodeWithTag("saveItem").performClick()
        waitGone(hasTestTag("itemQuantity"))
        waitFor(hasText("426"))
        val saved = meal(meal.id).items.first()
        assertEquals(400.0, saved.quantity, 0.0)
        assertEquals(380.0, saved.nutrition.kcal!!, 0.001)
    }

    @Test fun staleEditShowsMessageAndReloads() {
        val meal = savedMeal(food("Greek yogurt", 190.0, 200.0))
        open(meal.id)
        waitFor(hasTestTag("editItem"))
        compose.onNodeWithTag("editItem").performClick()
        waitFor(hasTestTag("itemQuantity"))
        compose.onNodeWithTag("itemQuantity").performTextReplacement("400")
        // Another writer halves the meal after the editor opened.
        db().scaleMeal(meal.id, 95.0, 1)
        compose.onNodeWithTag("saveItem").performClick()
        waitFor(hasText("Could not complete action", substring = true))
        assertEquals(100.0, meal(meal.id).items.single().quantity, 0.0)
        compose.onNodeWithTag("cancelEditItem").performClick()
        compose.onNodeWithText("Discard changes").performClick()
        waitGone(hasTestTag("itemQuantity"))
        waitFor(hasText("95 kcal"))
    }

    @Test fun scaleToTargetUpdatesFoods() {
        val meal = savedMeal(food("Greek yogurt", 300.0, 200.0), food("Blueberries", 100.0, 80.0))
        open(meal.id)
        waitFor(hasTestTag("adjustMealTotal"))
        compose.onNodeWithTag("adjustMealTotal").performClick()
        waitFor(hasTestTag("mealTargetKcal"))
        compose.onNode(hasText("Adjust total") and isHeading()).assertIsDisplayed()
        compose.onNodeWithTag("mealTargetKcal").assertTextContains("400")
        compose.onNodeWithTag("mealTargetKcal").performTextReplacement("200")
        waitFor(hasTestTag("mealPreviewKcal") and hasContentDescription("200 kcal"))
        compose.onNodeWithText("0.50× of the current portions").assertIsDisplayed()
        compose.onNodeWithTag("saveMealTotal").performClick()
        waitGone(hasTestTag("mealTargetKcal"))
        assertEquals(listOf(100.0, 40.0), meal(meal.id).items.map { it.quantity })
        waitFor(hasText("200"))
    }

    @Test fun moveMealShowsReceiptAndMovesTotals() {
        val meal = savedMeal(food("Greek yogurt", 190.0, 200.0))
        val today = LocalDate.parse(db().read { it.day(meal.dayID)!!.localDate })
        val yesterday = TrackingDay(UUID.randomUUID(), today.minusDays(1).toString(), "UTC",
            Instant.now().minus(1, ChronoUnit.DAYS), DayCompleteness.unknown)
        db().transaction(db().head().revision) { it.putDay(yesterday) }
        open(meal.id)
        waitFor(hasText("Greek yogurt") and isHeading())
        compose.onNodeWithTag("mealActions").performClick()
        compose.onNodeWithTag("moveMeal").performClick()
        waitFor(hasTestTag("confirmMoveMeal"))
        compose.onNode(hasText("Move meal") and isHeading()).assertIsDisplayed()
        compose.onNodeWithTag("moveDay:${yesterday.localDate}").performClick()
        compose.onNodeWithTag("confirmMoveMeal").performClick()
        waitFor(hasTestTag("movedMealDayReceipt"))
        val label = today.minusDays(1).format(DateTimeFormatter.ofPattern("EEEE, d MMM", Locale.getDefault()))
        compose.onNodeWithText("Moved to $label").assertIsDisplayed()
        assertEquals(yesterday.id, meal(meal.id).dayID)
        val week = db().diaryWeek(today.minusDays(1).toString(), today.toString())
        assertEquals(190.0, week[0].totals.kcal!!, 0.001)
        assertEquals(0, week[1].mealCount)
    }

    @Test fun editorSurvivesRecreate() {
        savedMeal(food("Greek yogurt", 190.0, 200.0))
        val content = { activity: ComponentActivity -> activity.setContent { MivuTheme { MivuApp(repository) } } }
        compose.activityRule.scenario.onActivity(content)
        waitFor(hasTestTag("mealRow"))
        compose.onAllNodesWithTag("mealRow").onFirst().performClick()
        waitFor(hasTestTag("editItem"))
        compose.onNodeWithTag("editItem").performScrollTo().performClick()
        waitFor(hasTestTag("itemQuantity"))
        compose.onNodeWithTag("itemQuantity").performTextReplacement("300")
        compose.onNodeWithTag("foodMoreDetails").performScrollTo().performClick()
        compose.onNodeWithTag("itemCalories").performScrollTo().performTextReplacement("999")
        compose.activityRule.scenario.recreate()
        compose.activityRule.scenario.onActivity(content)
        waitFor(hasTestTag("itemQuantity"))
        compose.onNodeWithTag("itemQuantity").assertTextContains("300")
        // The explicit energy survives too: without it the preview could not keep 999 kcal.
        waitFor(hasTestTag("foodPreviewCalories") and hasContentDescription("999 kcal"))
    }
}
