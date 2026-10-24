package com.yakov103.mivu.ui.diary

import android.content.Context
import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.test.assert
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.width
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.assertWidthIsAtLeast
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isDialog
import androidx.compose.ui.test.isHeading
import androidx.compose.ui.test.isSelectable
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextClearance
import androidx.compose.ui.test.performTextInput
import androidx.test.core.app.ApplicationProvider
import com.yakov103.mivu.diary.Bootstrap
import com.yakov103.mivu.diary.DiaryRepository
import com.yakov103.mivu.ui.MivuApp
import com.yakov103.mivu.ui.theme.MivuTheme
import com.yakov103.mivu.ui.today.TodayFixture
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale
import java.util.UUID
import org.junit.After
import org.junit.Assert.assertNotNull
import org.junit.Before
import org.junit.Rule
import org.junit.Test

class DiaryScreenTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private val context: Context = ApplicationProvider.getApplicationContext()
    private var repository: DiaryRepository? = null
    private var profileID: UUID? = null
    private var openedMeal: UUID? = null

    @Before fun wipe() = TodayFixture.wipe(context)

    @After fun close() {
        profileID?.let { repository?.database(it)?.close() }
        (repository?.bootstrapState?.value as? Bootstrap.Ready)?.let { repository!!.database(it.profileID).close() }
        TodayFixture.wipe(context)
    }

    /** The Diary alone, with a week that puts three past and three future days around today. */
    private fun launchDiary(width: Dp? = null): DiaryFixture.Seeded {
        val seeded = DiaryFixture.seed(context)
        val repository = DiaryRepository(context).also { repository = it; profileID = seeded.profileID }
        val firstDay: DayOfWeek = seeded.today.dayOfWeek.minus(3)
        val model = DiaryViewModel(repository, seeded.profileID, sampleMode = false, firstDay = firstDay)
        compose.setContent {
            MivuTheme {
                Box(if (width != null) Modifier.width(width) else Modifier) {
                    DiaryScreen(model, onOpenMeal = { openedMeal = it }, onAskPip = {}, onEnterNutrition = {}, onProfile = {})
                }
            }
        }
        waitFor(pillMatcher(seeded.today))
        return seeded
    }

    private fun launchApp(): DiaryFixture.Seeded {
        val seeded = DiaryFixture.seed(context)
        val repository = DiaryRepository(context).also { repository = it }
        compose.setContent { MivuTheme { MivuApp(repository) } }
        return seeded
    }

    private fun pillMatcher(date: LocalDate) =
        hasTestTag("diaryDayPill") and SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, date.toString())
    private fun pill(date: LocalDate) = compose.onNode(pillMatcher(date))
    private fun title(date: LocalDate) = date.format(DateTimeFormatter.ofPattern("EEEE, d MMMM", Locale.US))

    private fun waitFor(matcher: SemanticsMatcher) =
        compose.waitUntil(10_000) { compose.onAllNodes(matcher, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty() }
    private fun waitForText(text: String) = waitFor(hasText(text))
    private fun chip(): SemanticsNodeInteraction = compose.onNodeWithTag("diaryDayStatusChip")
    private fun chipState(state: String) = SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, state)

    private fun chooseDate(date: LocalDate) {
        compose.onNodeWithTag("chooseDiaryDate").performClick()
        compose.onNodeWithContentDescription("Switch to text input mode").performClick()
        val field = compose.onNode(hasSetTextAction() and hasAnyAncestor(isDialog()))
        field.performTextClearance()
        field.performTextInput(date.format(DateTimeFormatter.ofPattern(inputDigits())))
        compose.onNodeWithTag("applyDiaryDate").performClick()
        waitForText(title(date))
    }

    /** The digits M3's date input expects: the locale's short date pattern as dd, MM and yyyy, delimiters dropped. */
    private fun inputDigits(): String {
        val pattern = (java.text.DateFormat.getDateInstance(java.text.DateFormat.SHORT, Locale.getDefault()) as java.text.SimpleDateFormat).toPattern()
        return pattern.filter { it in "dMy" }.replace(Regex("d+"), "dd").replace(Regex("M+"), "MM").replace(Regex("y+"), "yyyy")
    }

    @Test fun everyPillHasFullTouchTargetOnNarrowPhone() {
        val seeded = launchDiary(width = 360.dp)
        // The pill node is the whole slot, so its bounds are its touch target.
        (-3L..3L).forEach { pill(seeded.today.plusDays(it)).assertWidthIsAtLeast(48.dp).assertHeightIsAtLeast(48.dp) }
    }

    @Test fun selectingPillShowsDay() {
        val seeded = launchDiary()
        val yesterday = seeded.today.minusDays(1)
        pill(yesterday).performClick()
        waitForText("Oat porridge")
        pill(yesterday).assertIsSelected()
        compose.onNode(hasText(title(yesterday)) and isHeading()).assertIsDisplayed()
        compose.onNodeWithText("45 minutes", substring = true).performScrollTo().assertIsDisplayed()
        compose.onAllNodesWithTag("historyMeal").onFirst().performScrollTo().performClick()
        assertNotNull(openedMeal)
        // A skipped day with no meals.
        pill(seeded.today.minusDays(2)).performClick()
        waitForText("No meals recorded for this day.")
    }

    @Test fun futurePillDisabled() {
        val seeded = launchDiary()
        pill(seeded.today.plusDays(1)).assertIsNotEnabled()
        pill(seeded.today).assertIsEnabled().assertIsSelected()
            .assert(hasContentDescription("Open, 2 meals", substring = true))
    }

    @Test fun skipDayChangesChipAndStatus() {
        val seeded = launchDiary()
        val yesterday = seeded.today.minusDays(1)
        pill(yesterday).performClick()
        waitForText(title(yesterday))
        chip().assert(chipState("Closed")).performClick()
        compose.onNodeWithText("Skipped days stay out of your statistics.").assertIsDisplayed()
        compose.onNodeWithText("Skip This Day").performClick()
        waitFor(hasTestTag("diaryDayStatusChip") and chipState("Skipped"))
        pill(yesterday).assert(hasContentDescription("Skipped, 1 meal", substring = true))
        chip().performClick()
        compose.onNodeWithText("Count This Day").performClick()
        waitFor(hasTestTag("diaryDayStatusChip") and chipState("Closed"))
    }

    @Test fun chooseDateJumpsToWeek() {
        val seeded = launchDiary()
        val earliest = seeded.today.minusDays(16)
        chooseDate(earliest)
        waitForText("Rice bowl")
        pill(earliest).assertIsDisplayed().assertIsSelected()
        // A date with no record reads as nothing logged.
        chooseDate(earliest.plusDays(1))
        waitForText("Nothing logged")
        compose.onNodeWithText("Ask Pip to add what you ate on this day.").assertIsDisplayed()
    }

    @Test fun addMenuOpensManualEntryForDay() {
        val seeded = launchApp()
        waitFor(hasText("Today") and isHeading())
        compose.onNode(hasText("Diary") and isSelectable()).performClick()
        waitFor(hasTestTag("diaryDayPill"))
        // No record on this date: nothing to add to.
        chooseDate(seeded.today.minusDays(15))
        compose.onNodeWithTag("diaryAddMenu").assertIsNotEnabled()
        val target = seeded.today.minusDays(3)
        chooseDate(target)
        waitForText("Lentil soup")
        compose.onNodeWithTag("diaryAddMenu").assertIsEnabled().performClick()
        compose.onNodeWithTag("enterNutritionForDay").performClick()
        waitForText("Recorded day")
        val pattern = android.text.format.DateFormat.getBestDateTimePattern(Locale.getDefault(), "EEEMMMd")
        compose.onNodeWithText(target.format(DateTimeFormatter.ofPattern(pattern, Locale.getDefault()))).assertIsDisplayed()
    }

    @Test fun todayRowOpensMealDetail() {
        launchApp()
        waitFor(hasTestTag("mealRow"))
        compose.onAllNodesWithTag("mealRow").onFirst().performClick()
        waitFor(hasText("Meal") and isHeading())
        compose.onNodeWithContentDescription("Back").performClick()
        waitFor(hasText("Today") and isHeading())
    }
}
