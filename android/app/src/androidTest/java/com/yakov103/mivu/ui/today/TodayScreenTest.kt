package com.yakov103.mivu.ui.today

import android.content.Context
import androidx.activity.ComponentActivity
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isSelectable
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.unit.Density
import androidx.test.core.app.ApplicationProvider
import com.yakov103.mivu.diary.Bootstrap
import com.yakov103.mivu.diary.DiaryRepository
import com.yakov103.mivu.ui.MivuApp
import com.yakov103.mivu.ui.theme.MivuTheme
import org.junit.After
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test

class TodayScreenTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private val context: Context = ApplicationProvider.getApplicationContext()
    private var repository: DiaryRepository? = null

    @Before fun wipe() = TodayFixture.wipe(context)

    @After fun close() {
        (repository?.bootstrapState?.value as? Bootstrap.Ready)?.let { repository!!.database(it.profileID).close() }
        TodayFixture.wipe(context)
    }

    private fun launch(fontScale: Float? = null) {
        val repository = DiaryRepository(context).also { repository = it }
        compose.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, fontScale ?: density.fontScale)) {
                MivuTheme { MivuApp(repository) }
            }
        }
    }

    private fun waitFor(tag: String) =
        compose.waitUntil(10_000) { compose.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty() }

    private fun waitForText(text: String) =
        compose.waitUntil(10_000) { compose.onAllNodes(hasText(text), useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty() }

    @Test fun everyTagExists() {
        TodayFixture.seed(context, photo = false)
        launch()
        waitFor("mealRow")
        listOf("todayDayActions", "todayGoalSummary", "logMeal", "addManually").forEach { compose.onNodeWithTag(it).assertExists() }
        assertTrue(compose.onAllNodesWithTag("mealRow").fetchSemanticsNodes().size == 2)
        compose.onNodeWithTag("todayDayActions").performClick()
        compose.onNodeWithTag("startNewDay").assertIsDisplayed()
    }

    @Test fun unknownProteinShowsDashAndNote() {
        TodayFixture.seed(context, unknownProtein = true, photo = false)
        launch()
        waitForText("Some nutrients are unknown. Recorded totals may be incomplete.")
        compose.onNodeWithText("1,020").assertIsDisplayed()
        compose.onNodeWithText("129 g").assertIsDisplayed() // carbs stay known
    }

    @Test fun kcalIsDashWhenNull() {
        TodayFixture.diary(context)
        launch()
        waitFor("todayDayActions")
        // kcal and the three macros: unknown, never 0
        compose.onAllNodesWithText("—").assertCountEquals(4).apply { (0 until 4).forEach { get(it).assertIsDisplayed() } }
        compose.onNodeWithText("kcal recorded").assertIsDisplayed()
        compose.onNodeWithText("No meals recorded").assertIsDisplayed()
        compose.onNodeWithText("Your first meal starts here").assertIsDisplayed()
    }

    @Test fun startNewDayCallsTheStore() {
        val id = TodayFixture.diary(context)
        launch()
        waitFor("todayDayActions")
        compose.onNodeWithTag("todayDayActions").performClick()
        compose.onNodeWithTag("startNewDay").performClick()
        compose.waitUntil(10_000) { repository!!.database(id).head().activeDayID != null }
        compose.waitUntil(10_000) { compose.onAllNodes(hasText("No meals recorded")).fetchSemanticsNodes().isEmpty() }
        assertNotNull(repository!!.database(id).head().activeDayID)
    }

    @Test fun addManuallyOpensManualEntry() {
        TodayFixture.seed(context, photo = false)
        launch()
        waitFor("addManually")
        compose.onNodeWithTag("addManually").performClick()
        waitFor("manualEntryRoute")
    }

    @Test fun logWithPipSelectsCoach() {
        TodayFixture.diary(context)
        launch()
        waitFor("logMeal")
        compose.onNodeWithTag("logMeal").assertIsDisplayed().performClick()
        compose.waitUntil(10_000) { compose.onAllNodesWithTag("logMeal").fetchSemanticsNodes().isEmpty() }
        compose.onNode(hasText("Coach") and isSelectable()).assertIsSelected()
    }

    @Test fun doubleFontScaleShowsEverySummaryNodeUnclipped() {
        TodayFixture.seed(context, photo = false)
        launch(fontScale = 2f)
        waitFor("todayGoalSummary")
        val width = compose.onRoot().fetchSemanticsNode().boundsInRoot.width
        val nodes = compose.onAllNodes(hasAnyAncestor(hasTestTag("todaySummary")), useUnmergedTree = true)
        val count = nodes.fetchSemanticsNodes().size
        assertTrue("summary card has nodes", count > 8)
        for (i in 0 until count) {
            val node: SemanticsNodeInteraction = nodes[i]
            node.performScrollTo().assertIsDisplayed()
            val bounds = node.fetchSemanticsNode().boundsInRoot
            assertTrue("node $i within screen: $bounds", bounds.left >= 0f && bounds.right <= width)
        }
        listOf("1,020", "56 g", "129 g", "25 g", "2,000 kcal goal", "980 to goal").forEach {
            compose.onNodeWithText(it, useUnmergedTree = true).performScrollTo().assertIsDisplayed()
        }
    }
}
