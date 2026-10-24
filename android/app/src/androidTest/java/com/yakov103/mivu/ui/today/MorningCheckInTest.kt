package com.yakov103.mivu.ui.today

import android.content.Context
import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsFocused
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isSelectable
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextReplacement
import androidx.core.content.edit
import androidx.test.core.app.ApplicationProvider
import com.yakov103.mivu.day.greeting
import com.yakov103.mivu.diary.Bootstrap
import com.yakov103.mivu.diary.DayCutoff
import com.yakov103.mivu.diary.DiaryDatabase
import com.yakov103.mivu.diary.DiaryMeal
import com.yakov103.mivu.diary.DiaryRepository
import com.yakov103.mivu.diary.FoodItem
import com.yakov103.mivu.diary.GoalRecord
import com.yakov103.mivu.diary.MealSubmission
import com.yakov103.mivu.diary.MealTimePrecision
import com.yakov103.mivu.diary.NutritionProvenance
import com.yakov103.mivu.diary.NutritionValues
import com.yakov103.mivu.diary.SubmissionState
import com.yakov103.mivu.diary.WeightEntry
import com.yakov103.mivu.diary.TrackingDay
import com.yakov103.mivu.diary.DayCompleteness
import com.yakov103.mivu.diary.rollOverDay
import com.yakov103.mivu.diary.startDay
import com.yakov103.mivu.ui.MivuApp
import com.yakov103.mivu.ui.settings.SettingsScreen
import com.yakov103.mivu.connection.ConnectionState
import com.yakov103.mivu.ui.theme.MivuTheme
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import java.util.UUID
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assume.assumeTrue
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Before
import org.junit.Rule
import org.junit.Test

/** Synthetic diaries only: yesterday's waking day with a 1,870 kcal meal and a 2,100 kcal goal, rolled over to today. */
class MorningCheckInTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private val context: Context = ApplicationProvider.getApplicationContext()
    private var repository: DiaryRepository? = null
    private lateinit var profileID: UUID

    @Before fun wipe() = TodayFixture.wipe(context)

    @After fun close() {
        (repository?.bootstrapState?.value as? Bootstrap.Ready)?.let { repository!!.database(it.profileID).close() }
        DayCutoff.set(DiaryRepository.preferences(context), 4)
        TodayFixture.wipe(context)
    }

    private fun seed(kcal: Double? = 1870.0, weights: Map<Long, Double> = emptyMap()) { profileID = seedMorning(context, kcal, weights) }

    private fun db(): DiaryDatabase = repository!!.database(profileID)

    private fun launch() {
        val app = DiaryRepository(context).also { repository = it }
        compose.setContent { MivuTheme { MivuApp(app) } }
    }

    private fun exists(text: String, substring: Boolean = false) =
        compose.onAllNodes(hasText(text, substring = substring), useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()

    private fun waitForText(text: String, substring: Boolean = false) = compose.waitUntil(10_000) { exists(text, substring) }
    private fun waitUntilGone(text: String) = compose.waitUntil(10_000) { !exists(text) }
    private fun waitForTag(tag: String) =
        compose.waitUntil(10_000) { compose.onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty() }

    private val greetingText get() = greeting(LocalTime.now().hour)

    private fun openCoach() {
        compose.onNode(hasText("Coach") and isSelectable()).performClick()
        waitForTag("coachInput")
    }

    @Test fun cardAppearsAfterARolloverWithYesterdaysRecap() {
        seed()
        launch()
        waitForTag("morningCheckIn")
        compose.onNodeWithText(greetingText).assertIsDisplayed()
        compose.onNodeWithText("Yesterday").assertIsDisplayed()
        compose.onNodeWithText("1,870").assertIsDisplayed()
        compose.onNodeWithText("of 2,100 kcal").assertIsDisplayed()
        compose.onNode(hasContentDescription("Intake toward that day's goal")).assertExists()
        compose.onNodeWithText("Morning weight", useUnmergedTree = true).assertExists()
    }

    @Test fun noRecapWhenYesterdayHasNoMeals() {
        seed(kcal = null)
        launch()
        waitForTag("morningCheckIn")
        compose.onNodeWithTag("morningWeight").assertExists()
        assertEquals(false, exists("Yesterday"))
        assertEquals(false, exists("of 2,100 kcal"))
    }

    @Test fun skipCollapsesToTheDoneLine() {
        seed()
        launch()
        waitForTag("morningWeightSkip")
        compose.onNodeWithTag("morningWeightSkip").performClick()
        waitForText("You're set for today")
        compose.onAllNodes(hasTestTag("morningWeight")).fetchSemanticsNodes().let { assertEquals(0, it.size) }
        assertEquals(db().head().activeDayID.toString(),
            DiaryRepository.preferences(context).getString("morningWeightSkippedDay", null))
    }

    @Test fun saveRecordsOnTheOpenDayAndShowsTheWeeklyTrend() {
        seed(weights = mapOf(1L to 72.5, 2L to 72.5, 8L to 73.0, 9L to 73.0, 10L to 73.0))
        launch()
        waitForTag("morningWeight")
        compose.onNodeWithTag("morningWeight").performTextReplacement("72.54")
        compose.onNodeWithTag("morningWeightSave").performClick()
        waitForText("−0.5 kg this week")
        compose.onNodeWithText("72.5 kg", useUnmergedTree = true).assertExists()
        compose.onNodeWithText("You're set for today", useUnmergedTree = true).assertExists()
        val active = db().head().activeDayID!!
        val weight = db().read { it.dayWeight(active) }!!
        assertEquals(72.5, weight.value, 0.0)
        assertEquals("kg", weight.unit)
    }

    @Test fun poundsAreSavedAsKilograms() {
        seed()
        launch()
        waitForTag("morningWeight")
        compose.onNodeWithContentDescription("Unit, kg").performClick()
        compose.onNodeWithText("lb").performClick()
        compose.onNode(hasContentDescription("Unit, lb")).assertExists()
        compose.onNode(hasTestTag("morningWeight") and hasText("Weight in pounds")).assertExists()
        compose.onNodeWithTag("morningWeight").performTextReplacement("160")
        compose.onNodeWithTag("morningWeightSave").performClick()
        compose.waitUntil(10_000) { db().read { it.dayWeight(db().head().activeDayID!!) } != null }
        val weight = db().read { it.dayWeight(db().head().activeDayID!!) }!!
        assertEquals(72.6, weight.value, 0.0) // 160 lb = 72.57 kg, kept to 0.1
        assertEquals("kg", weight.unit)
        waitForText("160.1 lb")
    }

    @Test fun outOfRangeWeightCannotBeSaved() {
        seed()
        launch()
        waitForTag("morningWeight")
        val save = compose.onNodeWithTag("morningWeightSave")
        save.assertIsNotEnabled()
        compose.onNodeWithTag("morningWeight").performTextReplacement("19.9")
        save.assertIsNotEnabled()
        compose.onNodeWithTag("morningWeight").performTextReplacement("400.1")
        save.assertIsNotEnabled()
        compose.onNodeWithTag("morningWeight").performTextReplacement("abc")
        save.assertIsNotEnabled()
        compose.onNodeWithTag("morningWeight").performTextReplacement("72")
        save.assertIsEnabled()
    }

    @Test fun firstMealHidesTheCard() {
        seed()
        launch()
        waitForTag("morningCheckIn")
        val active = db().head().activeDayID!!
        val at = Instant.now()
        db().transaction(db().head().revision) { tx ->
            tx.putMeal(DiaryMeal(UUID.randomUUID(), active, at, at, 1, timePrecision = MealTimePrecision.exact,
                items = listOf(FoodItem(UUID.randomUUID(), "Synthetic toast", 1.0, "slice", NutritionValues(90.0, 15.0, 3.0, 1.0),
                    NutritionProvenance.user, "Entered manually", false, emptyMap())), photos = emptyList(),
                submissions = listOf(MealSubmission(UUID.randomUUID(), 0, "Synthetic toast", emptyList(), false, SubmissionState.saved))))
        }
        compose.waitUntil(10_000) { compose.onAllNodes(hasTestTag("morningCheckIn"), useUnmergedTree = true).fetchSemanticsNodes().isEmpty() }
    }

    @Test fun closeHidesItForThisDayOnly() {
        seed()
        launch()
        waitForTag("morningCheckIn")
        compose.onNodeWithContentDescription("Hide check-in").performClick()
        compose.waitUntil(10_000) { compose.onAllNodes(hasTestTag("morningCheckIn"), useUnmergedTree = true).fetchSemanticsNodes().isEmpty() }
        val prefs = DiaryRepository.preferences(context)
        assertEquals(db().head().activeDayID.toString(), prefs.getString("morningCardDismissedDay", null))
        // Another day's dismissal does not hide this one.
        prefs.edit(commit = true) { putString("morningCardDismissedDay", UUID.randomUUID().toString()) }
        waitForTag("morningCheckIn")
    }

    @Test fun coachBubbleTellCoachFillsTheDraft() {
        seed()
        launch()
        waitForTag("morningCheckIn")
        openCoach()
        waitForText("$greetingText. Weighed in yet?")
        compose.onNodeWithText("Tell Coach instead").performClick()
        compose.onNodeWithTag("coachInput").assertIsFocused()
        compose.waitUntil(5_000) {
            compose.onNodeWithTag("coachInput").fetchSemanticsNode().config[SemanticsProperties.EditableText].text == "My weight this morning is "
        }
        // Typing hides the bubble.
        waitUntilGone("$greetingText. Weighed in yet?")
    }

    @Test fun dismissalIsSharedWithCoach() {
        seed()
        launch()
        waitForTag("morningCheckIn")
        openCoach()
        waitForText("$greetingText. Weighed in yet?")
        compose.onNodeWithContentDescription("Hide check-in").performClick()
        waitUntilGone("$greetingText. Weighed in yet?")
        compose.onNode(hasText("Today") and isSelectable()).performClick()
        waitForTag("todaySummary")
        assertEquals(0, compose.onAllNodes(hasTestTag("morningCheckIn"), useUnmergedTree = true).fetchSemanticsNodes().size)
    }

    @Test fun dayStartsAtChangesTheFooterAndCutoff() {
        compose.setContent { MivuTheme { SettingsScreen(ConnectionState(), onOpenConnection = {}, onBack = {}) } }
        compose.onNodeWithText("Your day").assertIsDisplayed()
        compose.onNodeWithText("Food before 4 AM still counts for the day before. A new day starts the first time you open Mivu after that.")
            .assertIsDisplayed()
        compose.onNodeWithTag("dayStartHour").performClick()
        compose.onNodeWithText("6 AM").performClick()
        waitForText("Food before 6 AM still counts for the day before. A new day starts the first time you open Mivu after that.")
        assertEquals(6, DayCutoff.hour)
        assertEquals(6, DiaryRepository.preferences(context).getInt(DayCutoff.KEY, 0))
        compose.onNodeWithText("Morning check-in").assertIsDisplayed()
        assertEquals(0, compose.onAllNodes(hasText("Reminder time")).fetchSemanticsNodes().size) // off by default
    }
}

/** Yesterday (with [kcal] eaten, unless null) rolled over to a new active day; weights at the given days back, in kg. */
internal fun seedMorning(context: Context, kcal: Double? = 1870.0, weights: Map<Long, Double> = emptyMap()): UUID {
    val zone = ZoneId.systemDefault()
    val profileID = TodayFixture.diary(context)
    val db = DiaryRepository(context).database(profileID)
    val now = Instant.now()
    val yesterday = db.startDay(now.minus(1, ChronoUnit.DAYS), db.head().revision)
    db.transaction(db.head().revision) { tx ->
        tx.putGoal(GoalRecord(UUID.randomUUID(), "2026-01-01", zone.id, 1, NutritionValues(2100.0, 230.0, 120.0, 70.0), null, false))
        if (kcal != null) {
            val at = yesterday.startAt.plusSeconds(60)
            val item = FoodItem(UUID.randomUUID(), "Synthetic stew", 1.0, "serving", NutritionValues(kcal, 200.0, 90.0, 60.0),
                NutritionProvenance.user, "Entered manually", false, emptyMap())
            tx.putMeal(DiaryMeal(UUID.randomUUID(), yesterday.id, at, at, 1, timePrecision = MealTimePrecision.exact,
                items = listOf(item), photos = emptyList(),
                submissions = listOf(MealSubmission(UUID.randomUUID(), 0, "Synthetic stew", emptyList(), false, SubmissionState.saved))))
        }
        for ((back, kg) in weights) {
            val day = if (back == 1L) yesterday else TrackingDay(UUID.randomUUID(),
                LocalDate.parse(yesterday.localDate).minusDays(back - 1).toString(), zone.id,
                yesterday.startAt.minus(back - 1, ChronoUnit.DAYS), DayCompleteness.unknown).also(tx::putDay)
            tx.putWeight(WeightEntry(UUID.randomUUID(), day.id, day.startAt.plusSeconds(30), kg, "kg"))
        }
    }
    db.rollOverDay(now)
    db.close()
    return profileID
}

/** Seeds the emulator app for the check-in screenshot; skipped unless run with `-e seedMorningFixture true`. */
class MorningCheckInSeed {
    @Test fun seedMorningFixture() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("seedMorningFixture") == "true")
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        TodayFixture.wipe(context)
        seedMorning(context, weights = mapOf(1L to 72.8, 2L to 72.9, 8L to 73.2, 9L to 73.3, 10L to 73.2))
    }
}
