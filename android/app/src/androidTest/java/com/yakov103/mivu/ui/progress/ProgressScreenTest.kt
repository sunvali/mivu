package com.yakov103.mivu.ui.progress

import android.content.Context
import androidx.activity.ComponentActivity
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasScrollToNodeAction
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isHeading
import androidx.compose.ui.test.isSelectable
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.unit.Density
import androidx.test.core.app.ApplicationProvider
import com.yakov103.mivu.diary.Bootstrap
import com.yakov103.mivu.diary.DayCompleteness
import com.yakov103.mivu.diary.DayCutoff
import com.yakov103.mivu.diary.DiaryMeal
import com.yakov103.mivu.diary.DiaryRepository
import com.yakov103.mivu.diary.FoodItem
import com.yakov103.mivu.diary.GoalRecord
import com.yakov103.mivu.diary.MealSubmission
import com.yakov103.mivu.diary.MealTimePrecision
import com.yakov103.mivu.diary.NutritionProvenance
import com.yakov103.mivu.diary.NutritionValues
import com.yakov103.mivu.diary.SubmissionState
import com.yakov103.mivu.diary.TrackingDay
import com.yakov103.mivu.diary.WeightEntry
import com.yakov103.mivu.diary.WorkoutKind
import com.yakov103.mivu.diary.WorkoutSession
import com.yakov103.mivu.diary.progressRange
import com.yakov103.mivu.diary.startDay
import com.yakov103.mivu.ui.MivuApp
import com.yakov103.mivu.ui.theme.MivuTheme
import com.yakov103.mivu.ui.today.TodayFixture
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.Locale
import java.util.UUID
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test

/** The Progress tab on a synthetic 90-day diary: ranges, cards, detail screens, the weight ledger and spoken charts. */
class ProgressScreenTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private val context: Context = ApplicationProvider.getApplicationContext()
    private var repository: DiaryRepository? = null
    private val cutoff = DayCutoff.hour
    private lateinit var today: LocalDate

    @Before fun wipe() {
        DayCutoff.hour = 0 // the waking day is the calendar date at any hour
        TodayFixture.wipe(context)
    }

    @After fun close() {
        DayCutoff.hour = cutoff
        (repository?.bootstrapState?.value as? Bootstrap.Ready)?.let { repository!!.database(it.profileID).close() }
        TodayFixture.wipe(context)
    }

    /**
     * 90 synthetic days ending today: a meal on every past day except two days ago and every ninth day (no log), today
     * open with one meal, a 2,100 kcal goal with a 68 kg goal weight, a workout yesterday, and a weigh-in every
     * [weighInEvery] days (only yesterday when null). Leaves no database open.
     */
    private fun seed(weighInEvery: Int? = 2): UUID {
        val id = TodayFixture.diary(context)
        val db = DiaryRepository(context).database(id)
        val zone = ZoneId.systemDefault()
        val active = db.startDay(Instant.now().truncatedTo(ChronoUnit.SECONDS), db.head().revision)
        today = LocalDate.parse(active.localDate)
        fun at(date: LocalDate, hour: Int) = date.atTime(hour, 0).atZone(zone).toInstant()
        db.transaction(db.head().revision) { tx ->
            tx.putGoal(GoalRecord(UUID.randomUUID(), today.minusDays(200).toString(), zone.id, 1,
                NutritionValues(2100.0, 230.0, 120.0, 70.0), 68.0, false))
            fun meal(day: TrackingDay, name: String, kcal: Double) {
                val date = LocalDate.parse(day.localDate)
                val item = FoodItem(UUID.randomUUID(), name, 1.0, "serving", NutritionValues(kcal, kcal * 0.11, kcal * 0.06, kcal * 0.03),
                    NutritionProvenance.user, "Entered manually", false, emptyMap())
                tx.putMeal(DiaryMeal(UUID.randomUUID(), day.id, at(date, 12), at(date, 12), 1, timePrecision = MealTimePrecision.exact,
                    items = listOf(item), photos = emptyList(),
                    submissions = listOf(MealSubmission(UUID.randomUUID(), 0, name, emptyList(), false, SubmissionState.saved))))
            }
            meal(active, "Synthetic soup", 600.0)
            for (back in 1L..89L) {
                if (back == 2L || back % 9 == 0L) continue
                val date = today.minusDays(back)
                val day = TrackingDay(UUID.randomUUID(), date.toString(), zone.id, at(date, 7), DayCompleteness.unknown).also(tx::putDay)
                meal(day, if (back % 3 == 0L) "Synthetic soup" else "Synthetic oats", 1700.0 + (back * 37) % 700)
                val weighs = if (weighInEvery == null) back == 1L else back % weighInEvery == 1L
                if (weighs) tx.putWeight(WeightEntry(UUID.randomUUID(), day.id, at(date, 7), 70.0 + back * 0.04, "kg"))
                if (back == 1L) tx.putWorkout(WorkoutSession(UUID.randomUUID(), day.id, at(date, 18), MealTimePrecision.exact, 1,
                    WorkoutKind.strength, 45, emptyList()))
            }
        }
        db.close()
        return id
    }

    private fun launchApp() {
        val app = DiaryRepository(context).also { repository = it }
        compose.setContent { MivuTheme { MivuApp(app) } }
        compose.waitUntil(10_000) { compose.onAllNodes(hasText("Progress") and isSelectable()).fetchSemanticsNodes().isNotEmpty() }
        compose.onNode(hasText("Progress") and isSelectable()).performClick()
        waitForTag("progressHeadline")
    }

    /** Progress alone, at [fontScale], on its own view model. */
    private fun host(model: ProgressViewModel, fontScale: Float? = null) = compose.setContent {
        val density = LocalDensity.current
        CompositionLocalProvider(LocalDensity provides Density(density.density, fontScale ?: density.fontScale)) {
            MivuTheme { ProgressScreen(model, onOpenDetail = {}, onOpenGoals = {}, onOpenDiary = {}) }
        }
    }

    private fun waitFor(matcher: SemanticsMatcher) =
        compose.waitUntil(10_000) { compose.onAllNodes(matcher).fetchSemanticsNodes().isNotEmpty() }
    private fun waitForTag(tag: String) = waitFor(hasTestTag(tag))
    private fun waitForText(text: String) = waitFor(hasText(text, substring = true))
    private fun scrollTo(matcher: SemanticsMatcher) = compose.onAllNodes(hasScrollToNodeAction()).onFirst().performScrollToNode(matcher)
    /** Charts inside tappable cards are merged into the card, so their own node is read from the unmerged tree. */
    private fun description(tag: String) =
        compose.onNodeWithTag(tag, useUnmergedTree = true).fetchSemanticsNode().config.getOrElse(SemanticsProperties.ContentDescription) { emptyList() }.joinToString()
    private fun dates() = compose.onNodeWithTag("progressDates").fetchSemanticsNode().config[SemanticsProperties.Text].joinToString()
    private fun label(date: LocalDate) = date.format(DateTimeFormatter.ofPattern("MMM d", Locale.US))
    private fun range(title: String) = compose.onNode(hasText(title) and isSelectable()).performClick()

    private fun openDetail(tag: String, title: String) {
        scrollTo(hasTestTag(tag))
        compose.onNodeWithTag(tag).performClick()
        waitFor(hasText(title) and isHeading())
    }

    private fun back() {
        compose.onNodeWithTag("progressDetailBack").performClick()
        waitForTag("progressList") // the list comes back where it was scrolled
    }

    @Test fun everyRangeRendersHeadlineWeightAndMacros() {
        seed()
        launchApp()
        val seen = mutableSetOf<String>()
        for (title in listOf("Week", "Month", "3M", "Year")) {
            val before = dates()
            range(title)
            if (title != "Week") compose.waitUntil(10_000) { dates() != before }
            seen += dates()
            compose.onNodeWithTag("progressHeadline").assertIsDisplayed()
            assertTrue(description("nutritionChartSummary").contains("kcal"))
            scrollTo(hasTestTag("openWeight")); compose.onNodeWithTag("openWeight").assertIsDisplayed()
            scrollTo(hasTestTag("progressMacros")); compose.onNodeWithTag("progressMacros").assertIsDisplayed()
            scrollTo(hasTestTag("progressHeadline"))
        }
        assertEquals(4, seen.size) // each range shows its own window
    }

    @Test fun missingDayIsNoLogNotZero() {
        seed()
        launchApp()
        compose.onNodeWithTag("missingDayCopy").assertIsDisplayed()
        val missing = today.minusDays(2)
        val summary = description("nutritionChartSummary")
        assertTrue(summary.contains("${label(today.minusDays(1))}:"))
        assertFalse(summary.contains("${label(missing)}:"))
        openDetail("progressCalories", "Calories")
        waitForTag("nutritionChartSummary")
        val row = missing.format(DateTimeFormatter.ofPattern("EEE d MMM", Locale.US))
        scrollTo(hasText(row))
        waitFor(hasTestTag("progressDayRow") and hasText(row, substring = true) and hasText("No log", substring = true))
    }

    @Test fun eachMoreRowOpensItsDetail() {
        seed()
        launchApp()
        listOf(
            "progressCalendar" to "Calendar", "progressCalories" to "Calories", "progressBurn" to "Estimated burn",
            "progressTopFoods" to "Top foods", "openWorkouts" to "Workouts", "openWeight" to "Weight", "progressMacros" to "Macros",
        ).forEach { (tag, title) ->
            openDetail(tag, title)
            back()
        }
        openDetail("progressTopFoods", "Top foods")
        waitForText("Synthetic oats")
    }

    @Test fun goalsRowOpensTheGoalEditor() {
        seed()
        launchApp()
        scrollTo(hasTestTag("progressGoals"))
        compose.onNodeWithTag("progressGoals").performClick()
        waitFor(hasText("Goals") and isHeading())
        waitForTag("saveGoals")
    }

    @Test fun weightLedgerPagesAndEdits() {
        seed(weighInEvery = 2)
        launchApp()
        openDetail("openWeight", "Weight")
        waitForTag("weightChart")
        waitForTag("editWeight")
        scrollTo(hasText("Older measurements"))
        compose.onNode(hasText("Older measurements") and hasClickAction()).performClick()
        // The oldest weigh-in (89 days back) is only on the second page.
        val oldest = today.minusDays(89).toString()
        waitFor(hasText(oldest))
        scrollTo(hasText("Latest measurements"))
        compose.onNode(hasText("Latest measurements") and hasClickAction()).performClick()
        waitFor(hasText(today.minusDays(1).toString()))
        scrollTo(hasTestTag("editWeight"))
        compose.onAllNodesWithTag("editWeight").onFirst().performClick()
        waitFor(hasText("Edit weight") and isHeading())
    }

    @Test fun notEnoughDataShowsTheCountdownPlaceholder() {
        seed(weighInEvery = null)
        launchApp()
        scrollTo(hasTestTag("openWeight"))
        waitForText("Weigh in on 2 more days to see your trend.")
    }

    @Test fun rangeSwitchKeepsTheLastReportOnFailure() {
        val id = seed()
        val repo = DiaryRepository(context).also { repository = it }
        val model = ProgressViewModel(repo, id) { db, end, days ->
            if (days == 91) error("synthetic failure") else db.progressRange(end, days, includeDailyReports = true)
        }
        host(model)
        waitForTag("progressHeadline")
        val week = dates()
        range("3M")
        waitForText("Could not load progress. Your diary is preserved.")
        compose.onNodeWithTag("progressHeadline").assertIsDisplayed()
        assertEquals(week, dates())
        compose.onNode(hasText("Retry loading progress") and hasClickAction()).assertIsDisplayed()
        assertTrue(model.state.value is ProgressUiState.Failed)
        repo.database(id).close()
    }

    @Test fun chartsHaveSpokenSummaries() {
        seed()
        launchApp()
        assertTrue(description("nutritionChartSummary").startsWith("Calories by day"))
        scrollTo(hasTestTag("openWeight"))
        assertTrue(description("weightTrendSummary").contains("weigh-ins"))
        scrollTo(hasTestTag("progressMacros"))
        assertTrue(description("macroDonut").contains("Protein"))
        openDetail("progressCalendar", "Calendar")
        waitForTag("progressCalendarRow")
        assertTrue(compose.onAllNodesWithTag("progressCalendarRow").fetchSemanticsNodes().first()
            .config.getOrElse(SemanticsProperties.ContentDescription) { emptyList() }.joinToString().contains("logged"))
    }

    @Test fun fontScale2StacksLegends() {
        val id = seed()
        val repo = DiaryRepository(context).also { repository = it }
        host(ProgressViewModel(repo, id), fontScale = 2f)
        waitForTag("progressHeadline")
        compose.onNodeWithTag("chartLegend").performScrollTo()
        val tops = compose.onAllNodesWithTag("legendItem", useUnmergedTree = true).fetchSemanticsNodes().map { it.boundsInRoot.top }
        assertEquals(5, tops.size)
        assertEquals("each legend entry on its own line", 5, tops.distinct().size)
        repo.database(id).close()
    }
}
