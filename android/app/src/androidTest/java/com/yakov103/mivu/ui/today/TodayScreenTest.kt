package com.yakov103.mivu.ui.today

import android.content.Context
import androidx.activity.ComponentActivity
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.SemanticsNodeInteraction
import android.database.sqlite.SQLiteDatabase
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.isSelected
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasScrollAction
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.performScrollToIndex
import androidx.compose.ui.test.performScrollToNode
import com.yakov103.mivu.pip.MotionPolicy.Playback
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
import com.yakov103.mivu.diary.DiaryError
import com.yakov103.mivu.diary.DiaryRepository
import com.yakov103.mivu.diary.DiaryMeal
import com.yakov103.mivu.diary.FoodItem
import com.yakov103.mivu.diary.MealTimePrecision
import com.yakov103.mivu.diary.NutritionProvenance
import com.yakov103.mivu.diary.NutritionValues
import com.yakov103.mivu.diary.startDay
import com.yakov103.mivu.diary.wakingDayTitle
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID
import com.yakov103.mivu.ui.MivuApp
import com.yakov103.mivu.ui.theme.MivuTheme
import org.junit.After
import org.junit.Assert.assertEquals
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
        // One spoken button: the date is not read again from a child node.
        compose.onNodeWithTag("todayDayActions")
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button))
            .assert(SemanticsMatcher.keyNotDefined(SemanticsProperties.Text))
            .assert(hasContentDescription("Day actions, ", substring = true))
        compose.onNodeWithTag("todayDayActions").performClick()
        compose.onNodeWithTag("startNewDay").assertIsDisplayed()
    }

    @Test fun failedReadOffersTryAgainAndKeepsTheLastGoodDay() {
        val id = TodayFixture.seed(context, photo = false)
        val repository = DiaryRepository(context)
        val db = repository.database(id)
        // Synthetic failure: a second connection swaps the diary head for bytes that do not decode, then puts it back.
        val head = SQLiteDatabase.openDatabase(db.file.path, null, SQLiteDatabase.OPEN_READONLY)
            .use { it.rawQuery("SELECT payload FROM head", null).use { c -> c.moveToFirst(); c.getBlob(0) } }
        fun setHead(payload: ByteArray) = SQLiteDatabase.openDatabase(db.file.path, null, SQLiteDatabase.OPEN_READWRITE)
            .use { it.execSQL("UPDATE head SET payload = ?", arrayOf(payload)) }
        fun breakHead() = setHead(byteArrayOf(0))
        fun restoreHead() = setHead(head)
        val failure = "Could not load today. Your diary is preserved."
        try {
            breakHead()
            val model = TodayViewModel(repository, id, sampleMode = false)
            compose.setContent { MivuTheme { TodayScreen(model, null, {}, {}, {}) } }
            waitForText(failure)
            restoreHead()
            compose.onNodeWithText("Try again").performClick()
            waitFor("mealRow")
            compose.onAllNodes(hasText(failure)).assertCountEquals(0)

            breakHead()
            model.retry()
            waitForText(failure)
            compose.onAllNodesWithTag("mealRow").assertCountEquals(2) // the last good day stays on screen
            compose.onNodeWithText("1,020").assertIsDisplayed()
        } finally {
            restoreHead()
            db.close()
        }
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

    @Test fun startNewDayRetriesARacedWriteOnce() {
        val id = TodayFixture.diary(context)
        launch()
        waitFor("todayDayActions")
        var raced = false
        repository!!.database(id).beforeCommit = { if (!raced) { raced = true; throw DiaryError.StaleRevision } }
        compose.onNodeWithTag("todayDayActions").performClick()
        compose.onNodeWithTag("startNewDay").performClick()
        compose.waitUntil(10_000) { repository!!.database(id).head().activeDayID != null }
        assertTrue(raced)
        compose.onAllNodes(hasText("Could not complete action", substring = true)).assertCountEquals(0)
    }

    @Test fun startNewDayFailureShowsSnackbar() {
        val id = TodayFixture.diary(context)
        launch()
        waitFor("todayDayActions")
        repository!!.database(id).beforeCommit = { throw DiaryError.InvalidData("synthetic") }
        compose.onNodeWithTag("todayDayActions").performClick()
        compose.onNodeWithTag("startNewDay").performClick()
        waitForText("Could not complete action. This diary contains invalid or unsupported data.")
        assertEquals(null, repository!!.database(id).head().activeDayID)
        repository!!.database(id).beforeCommit = null
    }

    @Test fun addManuallyOpensManualEntry() {
        TodayFixture.seed(context, photo = false)
        launch()
        waitFor("addManually")
        compose.onNodeWithTag("addManually").performClick()
        waitFor("manualFoodName")
    }

    @Test fun logWithPipSelectsCoach() {
        TodayFixture.diary(context)
        launch()
        waitFor("logMeal")
        compose.onNodeWithTag("logMeal").assertIsDisplayed().performClick()
        compose.waitUntil(10_000) { compose.onAllNodes(hasText("Coach") and isSelectable() and isSelected()).fetchSemanticsNodes().isNotEmpty() }
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

    /** A diary whose active day started at [dayAt], holding one synthetic meal captured at [capturedAt]; returns the meal ID. */
    private fun dayWithMeal(db: com.yakov103.mivu.diary.DiaryDatabase, dayAt: Instant, capturedAt: Instant): UUID {
        val day = db.startDay(dayAt, db.head().revision)
        val item = FoodItem(UUID.randomUUID(), "Toast", 1.0, "slice", NutritionValues(90.0, 15.0, 3.0, 1.0), NutritionProvenance.user,
            "Entered manually", false, emptyMap())
        val meal = DiaryMeal(UUID.randomUUID(), day.id, capturedAt, capturedAt, 1, timePrecision = MealTimePrecision.exact,
            items = listOf(item), photos = emptyList(), submissions = emptyList())
        db.transaction(db.head().revision) { it.putMeal(meal) }
        return meal.id
    }

    @Test fun lateMealReceiptOffersMove() {
        val id = TodayFixture.diary(context)
        val zone = ZoneId.systemDefault()
        val today = LocalDate.now(zone)
        val repo = DiaryRepository(context)
        val db = repo.database(id)
        try {
            // 01:30 today, still on yesterday's waking day.
            val mealID = dayWithMeal(db, today.minusDays(1).atTime(12, 0).atZone(zone).toInstant(), today.atTime(1, 30).atZone(zone).toInstant())
            val model = TodayViewModel(repo, id, sampleMode = false)
            model.showReceipt(mealID)
            compose.setContent { MivuTheme { TodayScreen(model, null, {}, {}, {}) } }
            waitForText("Added to ${wakingDayTitle(today.minusDays(1).toString())}")
            compose.onNodeWithTag("moveLateMeal").assertIsDisplayed()
                .assert(hasText("Move to ${wakingDayTitle(today.toString())}"))
                .performClick()
            compose.waitUntil(10_000) {
                db.read { tx -> tx.meal(mealID)?.dayID?.let(tx::day)?.localDate } == today.toString()
            }
            assertEquals(db.read { it.meal(mealID)?.dayID }, db.head().activeDayID)
            waitForText("Saved on this phone")
            compose.onAllNodesWithTag("moveLateMeal").assertCountEquals(0)
        } finally { db.close() }
    }

    @Test fun ordinaryReceiptStaysSavedOnThisPhone() {
        val id = TodayFixture.diary(context)
        val zone = ZoneId.systemDefault()
        val yesterday = LocalDate.now(zone).minusDays(1)
        val repo = DiaryRepository(context)
        val db = repo.database(id)
        try {
            val mealID = dayWithMeal(db, yesterday.atTime(12, 0).atZone(zone).toInstant(), yesterday.atTime(12, 30).atZone(zone).toInstant())
            val model = TodayViewModel(repo, id, sampleMode = false)
            model.showReceipt(mealID)
            compose.setContent { MivuTheme { TodayScreen(model, null, {}, {}, {}) } }
            waitForText("Saved on this phone")
            compose.onAllNodes(hasText("Added to", substring = true)).assertCountEquals(0)
            compose.onAllNodesWithTag("moveLateMeal").assertCountEquals(0)
        } finally { db.close() }
    }

    @Test fun pipStopsWhenScrolledAwayAndResumes() {
        val id = TodayFixture.diary(context)
        val repo = DiaryRepository(context)
        val db = repo.database(id)
        try {
            val start = Instant.now().minusSeconds(9 * 3600)
            val day = db.startDay(start, db.head().revision)
            repeat(8) { i ->
                val at = start.plusSeconds(3600L * (i + 1))
                val item = FoodItem(UUID.randomUUID(), "Snack $i", 1.0, "serving", NutritionValues(90.0, 15.0, 3.0, 1.0),
                    NutritionProvenance.user, "Entered manually", false, emptyMap())
                db.transaction(db.head().revision) {
                    it.putMeal(DiaryMeal(UUID.randomUUID(), day.id, at, at, 1, timePrecision = MealTimePrecision.exact, items = listOf(item),
                        photos = emptyList(), submissions = emptyList()))
                }
            }
            val model = TodayViewModel(repo, id, sampleMode = false)
            compose.setContent { MivuTheme { TodayScreen(model, null, {}, {}, {}) } }
            compose.waitUntil(10_000) { model.companion.value.playback == Playback.Animated }
            compose.onNode(hasScrollAction()).performScrollToNode(hasTestTag("logWeight"))
            compose.waitUntil(5_000) { model.companion.value.playback == Playback.Hidden }
            compose.onNode(hasScrollAction()).performScrollToIndex(0)
            compose.waitUntil(5_000) { model.companion.value.playback == Playback.Animated }
        } finally { db.close() }
    }

    /** Less than half of Pip on screen holds it still, with the summary item still composed. */
    @Test fun pipHoldsStillBelowHalfVisible() {
        val id = TodayFixture.diary(context)
        val repo = DiaryRepository(context)
        val db = repo.database(id)
        try {
            val start = Instant.now().minusSeconds(9 * 3600)
            val day = db.startDay(start, db.head().revision)
            repeat(8) { i ->
                val at = start.plusSeconds(3600L * (i + 1))
                val item = FoodItem(UUID.randomUUID(), "Snack $i", 1.0, "serving", NutritionValues(90.0, 15.0, 3.0, 1.0),
                    NutritionProvenance.user, "Entered manually", false, emptyMap())
                db.transaction(db.head().revision) {
                    it.putMeal(DiaryMeal(UUID.randomUUID(), day.id, at, at, 1, timePrecision = MealTimePrecision.exact, items = listOf(item),
                        photos = emptyList(), submissions = emptyList()))
                }
            }
            val model = TodayViewModel(repo, id, sampleMode = false)
            compose.setContent { MivuTheme { TodayScreen(model, null, {}, {}, {}) } }
            compose.waitUntil(10_000) { model.companion.value.playback == Playback.Animated }
            val list = compose.onNode(hasScrollAction())
            val top = list.fetchSemanticsNode().boundsInRoot.top
            val pip = compose.onNodeWithTag("todayPip").fetchSemanticsNode().boundsInRoot
            // Scroll so this fraction of Pip stays below the list's top edge.
            fun showFraction(fraction: Float) {
                val now = compose.onNodeWithTag("todayPip").fetchSemanticsNode().boundsInRoot
                list.performSemanticsAction(SemanticsActions.ScrollBy) { it(0f, now.bottom - top - fraction * pip.height) }
                compose.waitForIdle()
            }
            showFraction(0.6f)
            compose.waitUntil(5_000) { model.companion.value.playback == Playback.Animated }
            showFraction(0.4f)
            compose.waitUntil(5_000) { model.companion.value.playback == Playback.Hidden }
            compose.onNodeWithTag("todayPip").assertExists() // still composed: the threshold, not removal, holds it
            showFraction(0.6f)
            compose.waitUntil(5_000) { model.companion.value.playback == Playback.Animated }
        } finally { db.close() }
    }
}
