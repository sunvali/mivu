package com.yakov103.mivu.ui.manual

import android.content.Context
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertTextContains
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextReplacement
import androidx.lifecycle.SavedStateHandle
import androidx.test.core.app.ApplicationProvider
import androidx.test.espresso.Espresso
import com.yakov103.mivu.diary.Bootstrap
import com.yakov103.mivu.diary.DiaryMeal
import com.yakov103.mivu.diary.DiaryRepository
import com.yakov103.mivu.diary.MealTimePrecision
import com.yakov103.mivu.ui.MivuApp
import com.yakov103.mivu.ui.theme.MivuTheme
import com.yakov103.mivu.ui.today.TodayFixture
import java.io.IOException
import java.util.UUID
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Before
import org.junit.Rule
import org.junit.Test

class ManualNutritionScreenTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private val context: Context = ApplicationProvider.getApplicationContext()
    private var repository: DiaryRepository? = null

    @Before fun wipe() = TodayFixture.wipe(context)

    @After fun close() {
        ManualNutritionViewModel.afterSaveForTest = null
        (repository?.bootstrapState?.value as? Bootstrap.Ready)?.let { repository!!.database(it.profileID).close() }
        TodayFixture.wipe(context)
    }

    private fun launch(): DiaryRepository {
        val repository = DiaryRepository(context).also { repository = it }
        compose.setContent { MivuTheme { MivuApp(repository) } }
        return repository
    }

    private fun waitFor(tag: String) = compose.waitUntil(10_000) { compose.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty() }
    private fun waitGone(tag: String) = compose.waitUntil(10_000) { compose.onAllNodesWithTag(tag).fetchSemanticsNodes().isEmpty() }
    private fun waitForText(text: String) =
        compose.waitUntil(10_000) { compose.onAllNodes(hasText(text), useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty() }

    private fun openEntry() {
        waitFor("addManually")
        compose.onNodeWithTag("addManually").performClick()
        waitFor("manualFoodName")
    }

    private fun enter(tag: String, text: String) = compose.onNodeWithTag(tag).performTextReplacement(text)

    private fun todayMeals(repository: DiaryRepository, profileID: UUID): List<DiaryMeal> =
        repository.database(profileID).read { tx -> tx.dayMeals(tx.head.activeDayID!!) }

    @Test fun saveCreatesMealShownOnToday() {
        val id = TodayFixture.seed(context, photo = false)
        val repository = launch()
        openEntry()
        enter("manualFoodName", "Oat porridge")
        enter("manualCalories", "240")
        enter("manualProtein", "8,5")
        compose.onNodeWithTag("saveManualNutrition").performClick()
        waitGone("manualFoodName")
        waitForText("Oat porridge")
        val meal = todayMeals(repository, id).single { it.items.single().name == "Oat porridge" }
        assertEquals(8.5, meal.items.single().nutrition.protein!!, 0.0)
        assertEquals(null, meal.items.single().nutrition.carbs)
        assertEquals(MealTimePrecision.exact, meal.timePrecision ?: MealTimePrecision.exact)
    }

    @Test fun discardDialogOnBackWhenDirty() {
        val id = TodayFixture.seed(context, photo = false)
        val repository = launch()
        openEntry()
        // Clean: Close leaves without asking.
        compose.onNodeWithTag("cancelManualNutrition").performClick()
        waitGone("manualFoodName")
        openEntry()
        enter("manualFoodName", "Oats")
        Espresso.closeSoftKeyboard() // with the keyboard up, back only hides it
        Espresso.pressBack()
        waitForText("Discard changes?")
        compose.onNodeWithText("Your unsaved food and nutrition will be discarded.").assertIsDisplayed()
        compose.onNodeWithText("Keep editing").performClick()
        compose.onNodeWithTag("manualFoodName").assertTextContains("Oats")
        compose.onNodeWithTag("cancelManualNutrition").performClick()
        waitForText("Discard changes?")
        compose.onNodeWithText("Discard changes").performClick()
        waitGone("manualFoodName")
        assertEquals(2, todayMeals(repository, id).size)
    }

    @Test fun recreateKeepsValues() {
        TodayFixture.seed(context, photo = false)
        val repository = DiaryRepository(context).also { repository = it }
        // Set the content as MainActivity does, so the recreated composition matches the saved one key for key.
        val content = { activity: ComponentActivity -> activity.setContent { MivuTheme { MivuApp(repository) } } }
        compose.activityRule.scenario.onActivity(content)
        openEntry()
        enter("manualFoodName", "Oat porridge")
        enter("manualAmount", "2")
        enter("manualCalories", "240")
        compose.activityRule.scenario.recreate()
        compose.activityRule.scenario.onActivity(content)
        waitFor("manualFoodName")
        compose.onNodeWithTag("manualFoodName").assertTextContains("Oat porridge")
        compose.onNodeWithTag("manualAmount").assertTextContains("2")
        compose.onNodeWithTag("manualCalories").assertTextContains("240")
    }

    @Test fun doubleSaveAfterFailureCreatesOneMeal() {
        val id = TodayFixture.seed(context, photo = false)
        val repository = launch()
        openEntry()
        enter("manualFoodName", "Oat porridge")
        enter("manualCalories", "240")
        // The write commits but its acknowledgement is lost: the retry must find it, not add a second meal.
        ManualNutritionViewModel.afterSaveForTest = { throw IOException("synthetic lost acknowledgement") }
        compose.onNodeWithTag("saveManualNutrition").performClick()
        waitForText("Could not confirm this save. Retry with the same food to check it safely.")
        ManualNutritionViewModel.afterSaveForTest = null
        compose.onNodeWithTag("saveManualNutrition").performClick()
        waitGone("manualFoodName")
        assertEquals(1, todayMeals(repository, id).count { it.items.single().name == "Oat porridge" })
    }

    @Test fun processDeathKeepsDraftAndFrozenPayload() {
        val id = TodayFixture.seed(context, photo = false)
        val repository = DiaryRepository(context).also { repository = it }
        val handle = SavedStateHandle()
        val first = ManualNutritionViewModel(repository, id, null, null, handle)
        compose.runOnUiThread { first.update(ManualNutritionDraft(name = "Oats", kcal = "150")) }
        ManualNutritionViewModel.afterSaveForTest = { throw IOException("synthetic lost acknowledgement") }
        compose.runOnUiThread { first.save() }
        compose.waitUntil(10_000) { first.message != null }
        ManualNutritionViewModel.afterSaveForTest = null
        // A new process gets only what the handle saved.
        val restored = SavedStateHandle(handle.keys().associateWith { handle.get<Any>(it) })
        val second = ManualNutritionViewModel(repository, id, null, null, restored)
        assertEquals(first.draft, second.draft)
        compose.runOnUiThread { second.save() }
        compose.waitUntil(10_000) { second.savedMealID != null }
        assertNotNull(second.savedMealID)
        assertEquals(1, todayMeals(repository, id).count { it.items.single().name == "Oats" })
    }
}
