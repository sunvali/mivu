package com.yakov103.mivu.ui.progress

import android.content.Context
import androidx.activity.ComponentActivity
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertTextContains
import androidx.compose.ui.test.hasScrollToKeyAction
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isHeading
import androidx.compose.ui.test.isSelectable
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performScrollToKey
import androidx.compose.ui.test.performTextReplacement
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.core.app.ApplicationProvider
import com.yakov103.mivu.diary.Bootstrap
import com.yakov103.mivu.diary.DayCutoff
import com.yakov103.mivu.diary.DiaryRepository
import com.yakov103.mivu.diary.GoalRecord
import com.yakov103.mivu.diary.NutritionValues
import com.yakov103.mivu.diary.WorkoutBurnSource
import com.yakov103.mivu.diary.WorkoutExercise
import com.yakov103.mivu.diary.WorkoutKind
import com.yakov103.mivu.diary.WorkoutSet
import com.yakov103.mivu.diary.setGoals
import com.yakov103.mivu.diary.startDay
import com.yakov103.mivu.ui.MivuApp
import com.yakov103.mivu.ui.diary.DiaryFixture
import com.yakov103.mivu.ui.theme.MivuTheme
import com.yakov103.mivu.ui.today.TodayFixture
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import java.util.UUID
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test

/** The weight, workout and goal editors on synthetic diaries: their entry points, saves, validation and stale protection. */
class EditorsTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private val context: Context = ApplicationProvider.getApplicationContext()
    private var repository: DiaryRepository? = null
    private var profileID: UUID? = null
    private var closed = false

    private val cutoff = DayCutoff.hour

    // The waking day equals the calendar date at any hour, so Today's day and the goal editor's date agree after midnight.
    @Before fun wipe() {
        DayCutoff.hour = 0
        TodayFixture.wipe(context)
    }

    @After fun close() {
        DayCutoff.hour = cutoff
        profileID?.let { repository?.database(it)?.close() }
        (repository?.bootstrapState?.value as? Bootstrap.Ready)?.let { repository!!.database(it.profileID).close() }
        TodayFixture.wipe(context)
    }

    private fun repo() = repository ?: DiaryRepository(context).also { repository = it }
    private fun db() = repo().database(profileID!!)

    /** The whole app on a fresh repository: the seeding one closed its database. */
    private fun launchApp() {
        val app = DiaryRepository(context).also { repository = it }
        compose.setContent { MivuTheme { MivuApp(app) } }
    }

    /** Each tag's touch target is at least 48 dp tall (an M3 icon button draws 40 dp inside its 48 dp target). */
    private fun tall(bar: List<String>, content: List<String>) {
        val minimum = with(compose.density) { 47.5.dp.toPx() }
        fun check(tag: String) {
            val height = compose.onNodeWithTag(tag).fetchSemanticsNode().touchBoundsInRoot.height
            assertTrue("$tag target $height px", height >= minimum)
        }
        bar.forEach(::check) // the top bar is outside the scrolling column
        content.forEach { compose.onNodeWithTag(it).performScrollTo(); check(it) }
    }

    /** One editor on its own; [content] gets a close callback that records it. */
    private fun host(fontScale: Float? = null, content: @androidx.compose.runtime.Composable (() -> Unit) -> Unit) = compose.setContent {
        val density = LocalDensity.current
        CompositionLocalProvider(LocalDensity provides Density(density.density, fontScale ?: density.fontScale)) {
            MivuTheme { content { closed = true } }
        }
    }

    private fun waitFor(matcher: SemanticsMatcher) =
        compose.waitUntil(10_000) { compose.onAllNodes(matcher, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty() }
    private fun waitForText(text: String, substring: Boolean = false) = waitFor(hasText(text, substring = substring))
    private fun type(tag: String, text: String) = compose.onNodeWithTag(tag).performScrollTo().performTextReplacement(text)
    private fun enabled(tag: String) = SemanticsMatcher.keyNotDefined(SemanticsProperties.Disabled) and hasTestTag(tag)

    private fun seedDiary(): DiaryFixture.Seeded = DiaryFixture.seed(context).also { profileID = it.profileID }
    private fun dayID(date: LocalDate) = db().read { tx -> tx.days().first { it.localDate == date.toString() }.id }

    @Test fun todayWeightRowOpensAddWeightAndSaves() {
        profileID = TodayFixture.seed(context, photo = false)
        val activeDay = db().head().activeDayID
        db().close()
        launchApp()
        waitFor(hasTestTag("mealRow"))
        compose.onNode(hasScrollToKeyAction()).performScrollToKey("weight")
        compose.onNodeWithTag("logWeight").assertTextContains("Log weight", substring = true).performClick()
        waitFor(hasText("Add weight manually") and isHeading())
        type("weightInput", "72.5")
        compose.onNodeWithTag("saveWeight").performClick()
        compose.onNode(hasScrollToKeyAction()).performScrollToKey("weight")
        waitForText("72.5 kg")
        val db = repo().database(profileID!!)
        assertEquals(activeDay, db.head().activeDayID) // reused today's waking day
        assertEquals(72.5, db.read { it.dayWeight(activeDay!!) }!!.value, 0.0)
    }

    @Test fun diaryDayMenuAddsWeightToThatDay() {
        val seeded = seedDiary()
        val yesterday = dayID(seeded.today.minusDays(1))
        val before = db().read { tx -> tx.days().associate { it.id to it.localDate } }
        val active = db().head().activeDayID
        db().close()
        launchApp()
        waitFor(hasText("Today") and isHeading())
        compose.onNode(hasText("Diary") and isSelectable()).performClick()
        waitFor(hasTestTag("diaryDayPill"))
        compose.onNode(hasTestTag("diaryDayPill") and SemanticsMatcher.expectValue(SemanticsProperties.StateDescription,
            seeded.today.minusDays(1).toString())).performClick()
        waitForText("Oat porridge")
        compose.onNodeWithTag("diaryAddMenu").performClick()
        compose.onNodeWithTag("logWeightForDay").performClick()
        waitForText("Saving updates only this selected waking day", substring = true)
        type("weightInput", "71,8")
        compose.onNodeWithTag("saveWeight").performClick()
        waitForText("Morning weight 71.8 kg", substring = true)
        val db = repo().database(profileID!!)
        assertEquals(71.8, db.read { it.dayWeight(yesterday) }!!.value, 0.0)
        assertEquals(72.4, db.read { it.dayWeight(active!!) }!!.value, 0.0)
        assertEquals(before, db.read { tx -> tx.days().associate { it.id to it.localDate } }) // other day labels unchanged
        assertEquals(active, db.head().activeDayID)
    }

    @Test fun editWeightUpdatesTheSameEntry() {
        seedDiary()
        val weight = db().read { it.dayWeight(db().head().activeDayID!!) }!!
        val model = WeightEditorViewModel(repo(), profileID!!, dayID = null, weightID = weight.id)
        host { close -> WeightEditorScreen(model, close) }
        waitFor(hasText("Edit weight") and isHeading())
        compose.waitUntil(10_000) { model.loaded }
        compose.onNodeWithTag("weightInput").assertTextContains("72.4")
        type("weightInput", "72.1")
        compose.onNodeWithTag("saveWeight").performClick()
        compose.waitUntil(10_000) { closed }
        val saved = db().read { it.dayWeight(weight.dayID!!) }!!
        assertEquals(weight.id, saved.id)
        assertEquals(72.1, saved.value, 0.0)
        assertEquals(weight.revision + 1, saved.revision)
    }

    @Test fun outOfRangeWeightShowsTheIosLine() {
        profileID = TodayFixture.diary(context)
        host { close -> WeightEditorScreen(WeightEditorViewModel(repo(), profileID!!, null, null), close) }
        type("weightInput", "1200")
        compose.onNodeWithText("Enter a weight greater than 0 and no more than 1,000 kg.").assertIsDisplayed()
        compose.onNodeWithTag("saveWeight").assertIsNotEnabled()
        type("weightInput", "80")
        compose.onNodeWithTag("saveWeight").assertIsEnabled()
    }

    @Test fun workoutSavesWithExercisesAndSets() {
        val seeded = seedDiary()
        val date = seeded.today.minusDays(1)
        val day = dayID(date)
        val model = WorkoutEditorViewModel(repo(), profileID!!, date.toString(), day, null)
        host { close -> WorkoutEditorScreen(model, close) }
        compose.onNodeWithTag("workoutCardio").performClick()
        type("workoutDuration", "40")
        type("workoutExercise", "Squat")
        type("workoutRepetitions", "5")
        type("workoutLoad", "100")
        compose.onNodeWithTag("addWorkoutSet").performScrollTo().performClick()
        type("workoutRepetitions1", "8")
        type("workoutBurn", "250")
        compose.onNodeWithTag("saveWorkout").performClick()
        compose.waitUntil(10_000) { closed }
        val saved = db().read { it.dayWorkouts(day) }.single { it.durationMinutes == 40 }
        assertEquals(WorkoutKind.cardio, saved.kind)
        assertEquals(listOf(WorkoutExercise("Squat", listOf(WorkoutSet(5, 100.0), WorkoutSet(8, null)))), saved.exercises)
        assertEquals(250.0, saved.estimatedBurnKcal!!, 0.0)
        assertEquals(WorkoutBurnSource.userEstimate, saved.burnSource)
    }

    @Test fun workoutDetailDeletesAfterConfirm() {
        val seeded = seedDiary()
        val date = seeded.today.minusDays(1)
        val day = dayID(date)
        db().close()
        launchApp()
        waitFor(hasText("Today") and isHeading())
        compose.onNode(hasText("Diary") and isSelectable()).performClick()
        waitFor(hasTestTag("diaryDayPill"))
        compose.onNode(hasTestTag("diaryDayPill") and SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, date.toString()))
            .performClick()
        waitFor(hasTestTag("historyWorkout"))
        compose.onNodeWithTag("historyWorkout").performScrollTo().performClick()
        waitForText("45 minutes")
        compose.onNodeWithTag("deleteWorkout").performScrollTo().performClick()
        compose.onNodeWithText("Delete strength workout on $date?").assertIsDisplayed()
        compose.onNodeWithTag("confirmDeleteWorkout").performClick()
        waitFor(hasTestTag("diaryDayPill"))
        compose.waitUntil(10_000) { repo().database(profileID!!).read { it.dayWorkouts(day) }.isEmpty() }
        compose.waitUntil(10_000) { compose.onAllNodes(hasTestTag("historyWorkout")).fetchSemanticsNodes().isEmpty() }
    }

    @Test fun setAGoalAppearsWithoutATargetAndSaves() {
        profileID = TodayFixture.diary(context)
        db().startDay(Instant.now().truncatedTo(ChronoUnit.SECONDS), db().head().revision)
        db().close()
        launchApp()
        waitFor(hasTestTag("todayGoalSummary"))
        compose.onNodeWithTag("todayGoalSummary").assertTextContains("Set a goal").performClick()
        waitFor(hasText("Goals") and isHeading())
        waitFor(enabled("goalKcal"))
        type("goalKcal", "2100")
        compose.onNodeWithTag("saveGoals").performClick()
        waitForText("2,100 kcal goal")
    }

    @Test fun staleGoalSaveKeepsTheDraft() {
        profileID = TodayFixture.diary(context)
        val today = LocalDate.of(2026, 10, 24)
        val model = GoalEditorViewModel(repo(), profileID!!) { today }
        host { close -> GoalEditorScreen(model, close) }
        compose.waitUntil(10_000) { model.goalLoaded }
        type("goalKcal", "1800")
        type("goalProtein", "130")
        // Coach sets a goal for the same date while the editor is open.
        db().setGoals(GoalRecord(UUID.randomUUID(), today.toString(), ZoneId.systemDefault().id, 0, NutritionValues(kcal = 2400.0), null, false), null)
        compose.onNodeWithTag("saveGoals").performClick()
        waitForText("Could not save goals")
        compose.onNodeWithTag("saveFailedOK").performClick()
        compose.onNodeWithTag("goalKcal").assertTextContains("1800")
        compose.onNodeWithTag("goalProtein").assertTextContains("130")
        assertEquals(2400.0, db().read { tx -> tx.goals().single() }.targets.kcal!!, 0.0) // Coach's goal is not overwritten
        assertTrue(!closed)
    }

    @Test fun closeWithEditsAsksToDiscard() {
        profileID = TodayFixture.diary(context)
        host { close -> WeightEditorScreen(WeightEditorViewModel(repo(), profileID!!, null, null), close) }
        type("weightInput", "70")
        compose.onNodeWithTag("cancelWeight").performClick()
        compose.onNodeWithText("Discard this weight entry?").assertIsDisplayed()
        compose.onNodeWithText("Keep editing").performClick()
        compose.onNodeWithTag("weightInput").assertTextContains("70")
        compose.onNodeWithTag("cancelWeight").performClick()
        compose.onNodeWithText("Discard changes").performClick()
        compose.waitUntil(5_000) { closed }
        assertNull(db().read { tx -> tx.days().firstOrNull() })
    }

    @Test fun editorTargetsAtLeast48dpAtFontScale2() {
        profileID = TodayFixture.diary(context)
        val goals = GoalEditorViewModel(repo(), profileID!!)
        val workout = WorkoutEditorViewModel(repo(), profileID!!, "2026-10-24", null, null)
        var showWorkout by mutableStateOf(false)
        host(fontScale = 2f) { close -> if (showWorkout) WorkoutEditorScreen(workout, close) else GoalEditorScreen(goals, close) }
        compose.waitUntil(10_000) { goals.goalLoaded }
        tall(listOf("cancelGoals", "saveGoals"), listOf("goalDate", "goalKcal", "goalWeight", "exerciseCreditEnabled"))
        showWorkout = true
        compose.waitForIdle()
        tall(listOf("cancelWorkout", "saveWorkout"),
            listOf("workoutStrength", "workoutCardio", "workoutOther", "workoutDuration", "addWorkoutSet", "addWorkoutExercise"))
    }
}
