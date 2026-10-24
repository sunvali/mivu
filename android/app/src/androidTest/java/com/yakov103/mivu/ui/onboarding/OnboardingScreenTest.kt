package com.yakov103.mivu.ui.onboarding

import android.content.Context
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertTextContains
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isHeading
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTextReplacement
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.lifecycle.SavedStateHandle
import androidx.test.core.app.ApplicationProvider
import com.yakov103.mivu.analysis.AvailableModel
import com.yakov103.mivu.coach.CoachInferenceInput
import com.yakov103.mivu.coach.CoachInferenceResult
import com.yakov103.mivu.connection.AccountState
import com.yakov103.mivu.connection.ConnectionState
import com.yakov103.mivu.diary.Bootstrap
import com.yakov103.mivu.diary.DiaryRepository
import com.yakov103.mivu.diary.GoalRecord
import com.yakov103.mivu.diary.NutritionValues
import com.yakov103.mivu.diary.ProfileAbout
import com.yakov103.mivu.diary.goal
import com.yakov103.mivu.diary.recordWeight
import com.yakov103.mivu.diary.setGoals
import com.yakov103.mivu.diary.updateProfile
import com.yakov103.mivu.onboarding.OnboardingAnswers
import com.yakov103.mivu.pip.CompanionPose
import com.yakov103.mivu.ui.MivuApp
import com.yakov103.mivu.ui.theme.MivuTheme
import com.yakov103.mivu.ui.today.TodayFixture
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.serialization.json.JsonObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test

/** Synthetic diaries and scripted inference only; no ChatGPT account is used. */
class OnboardingScreenTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private val context: Context = ApplicationProvider.getApplicationContext()
    private var repository: DiaryRepository? = null
    private lateinit var model: OnboardingViewModel
    private var finished = false

    private val connected = ConnectionState(AccountState.connected, "synthetic-registration", listOf(AvailableModel("synthetic-model", "Synthetic")),
        "synthetic-model", consented = true)
    private val good = """{"kcal":1800,"protein":120,"carbs":200,"fat":60,"explanation":"A steady deficit keeps you full."}"""

    @Before fun wipe() = TodayFixture.wipe(context)

    @After fun close() {
        (repository?.bootstrapState?.value as? Bootstrap.Ready)?.let { repository!!.database(it.profileID).close() }
        TodayFixture.wipe(context)
    }

    private fun reply(text: String) = CoachInferenceResult("synthetic-model", text, emptyList(), emptyList())

    /** The setup screen alone over a new synthetic diary, with [state] and scripted [infer]. */
    private fun host(
        state: ConnectionState = ConnectionState(),
        fontScale: Float? = null,
        infer: suspend (List<CoachInferenceInput>, JsonObject?) -> CoachInferenceResult = { _, _ -> error("no inference expected") },
    ): UUID {
        val id = TodayFixture.diary(context)
        val repo = DiaryRepository(context).also { repository = it }
        model = OnboardingViewModel(repo, id, MutableStateFlow(state), { infer }, SavedStateHandle())
        compose.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, fontScale ?: density.fontScale)) {
                MivuTheme { OnboardingScreen(model, onAgree = {}, onConnect = {}, onFinish = { finished = true }) }
            }
        }
        return id
    }

    // Set as MainActivity does, so a recreated composition matches the saved one key for key.
    private val app = { activity: ComponentActivity -> activity.setContent { MivuTheme { MivuApp(repository!!, setupNewDiary = true) } } }

    private fun launchApp() {
        repository = DiaryRepository(context)
        compose.activityRule.scenario.onActivity(app)
    }

    private fun exists(matcher: SemanticsMatcher) = compose.onAllNodes(matcher).fetchSemanticsNodes().isNotEmpty()
    private fun waitFor(matcher: SemanticsMatcher) = compose.waitUntil(10_000) { exists(matcher) }
    private fun waitForText(text: String) = waitFor(hasText(text, substring = true))
    private fun heading(text: String) = hasText(text) and isHeading()

    private fun next() = compose.onNodeWithTag("onboardingNext").performClick()

    /** Hello through Your goal with synthetic answers; ends on How do you eat. */
    private fun answer(heightCm: String = "170", weightKg: String = "74", targetKg: String = "68") {
        waitFor(heading("Hi, I'm Pip"))
        next()
        waitFor(heading("About you"))
        compose.onNodeWithTag("onboardingHeight").performTextReplacement(heightCm)
        compose.onNodeWithTag("onboardingWeight").performTextReplacement(weightKg)
        compose.onNodeWithTag("onboardingBirthYear").performTextReplacement("1990")
        next()
        waitFor(heading("Your goal"))
        compose.onNodeWithTag("onboardingTarget").performTextReplacement(targetKg)
    }

    private fun toResults(viaConnect: Boolean) {
        answer()
        next()
        waitFor(heading("How do you eat?"))
        next()
        if (viaConnect) {
            waitFor(heading("Let ChatGPT tune it"))
            compose.onNodeWithTag("onboardingSkipConnect").performClick()
        }
        waitFor(heading("Your daily targets"))
    }

    private fun estimate() = OnboardingAnswers(ProfileAbout(170.0, 1990, ProfileAbout.Sex.unspecified, ProfileAbout.Pace.steady, emptyList(), ""),
        74.0, 68.0).estimate()

    private fun whole(value: Double?) = value!!.toLong().toString()

    @Test fun newDiaryOpensSetupOnce() {
        launchApp()
        waitFor(heading("Hi, I'm Pip"))
        compose.onNodeWithTag("onboardingLater").performClick()
        waitFor(heading("Today"))
        compose.activityRule.scenario.recreate()
        compose.activityRule.scenario.onActivity(app)
        waitFor(heading("Today"))
        compose.waitForIdle()
        assertTrue(!exists(heading("Hi, I'm Pip")))
    }

    @Test fun existingDiaryNeverOpensSetup() {
        TodayFixture.diary(context)
        launchApp()
        waitFor(heading("Today"))
        compose.waitForIdle()
        assertTrue(!exists(heading("Hi, I'm Pip")))
    }

    @Test fun laterOpensTodayWithNoTargets() {
        launchApp()
        waitFor(heading("Hi, I'm Pip"))
        compose.onNodeWithTag("onboardingLater").performClick()
        waitFor(heading("Today"))
        val db = repository!!.database((repository!!.bootstrapState.value as Bootstrap.Ready).profileID)
        assertNull(db.goal(LocalDate.now().toString()))
        assertNull(db.head().profile.about)
    }

    @Test fun unhealthyTargetBlocksContinue() {
        host()
        answer(heightCm = "165", weightKg = "55", targetKg = "48")
        waitForText("below a healthy weight for your height")
        compose.onNodeWithTag("onboardingNext").assertIsNotEnabled()
        compose.onNodeWithTag("onboardingTarget").performTextReplacement("52")
        waitForText("How quickly would you like to lose it?")
        compose.onNodeWithTag("onboardingNext").assertIsEnabled()
    }

    @Test fun disconnectedOffersTheEstimateInstead() {
        host()
        toResults(viaConnect = true)
        compose.onNodeWithText("Estimate").assertIsDisplayed()
        compose.onNodeWithTag("onboardingKcal").assertTextContains(whole(estimate().kcal))
    }

    @Test fun connectedSkipsTheConnectStep() {
        host(connected) { _, _ -> reply(good) }
        toResults(viaConnect = false)
        assertTrue(!exists(heading("Let ChatGPT tune it")))
        compose.onNodeWithTag("onboardingBack").performClick()
        waitFor(heading("How do you eat?"))
    }

    @Test fun goodReplyShowsTunedTargets() {
        val gate = CompletableDeferred<Unit>()
        var sent: List<CoachInferenceInput>? = null
        var tools: JsonObject? = JsonObject(emptyMap())
        host(connected) { input, t -> sent = input; tools = t; gate.await(); reply(good) }
        toResults(viaConnect = false)
        waitForText("ChatGPT is tuning your targets…")
        assertEquals(CompanionPose.Thinking, model.reaction?.pose)
        gate.complete(Unit)
        waitForText("Tuned by ChatGPT")
        compose.onNodeWithTag("onboardingKcal").assertTextContains("1800")
        compose.onNodeWithTag("onboardingProtein").assertTextContains("120")
        compose.onNodeWithText("A steady deficit keeps you full.").assertIsDisplayed()
        assertEquals(CompanionPose.Saved, model.reaction?.pose)
        assertEquals(2, sent?.size)
        assertNull(tools)
    }

    @Test fun badReplyKeepsTheEstimate() {
        host(connected) { _, _ -> reply("""{"kcal":900,"protein":60,"carbs":90,"fat":30,"explanation":"Low."}""") }
        toResults(viaConnect = false)
        waitForText("ChatGPT couldn't answer just now.")
        compose.onNodeWithText("Estimate").assertIsDisplayed()
        compose.onNodeWithTag("onboardingKcal").assertTextContains(whole(estimate().kcal))
        assertEquals(CompanionPose.Recovery, model.reaction?.pose)
    }

    @Test fun failedRequestOffersRetry() {
        var calls = 0
        host(connected) { _, _ -> if (calls++ == 0) throw java.io.IOException("synthetic offline") else reply(good) }
        toResults(viaConnect = false)
        waitForText("ChatGPT couldn't answer just now.")
        compose.onNodeWithText("Try again").performClick()
        waitForText("Tuned by ChatGPT")
        compose.onNodeWithTag("onboardingKcal").assertTextContains("1800")
        assertEquals(2, calls)
    }

    @Test fun saveWritesProfileWeightAndTodaysGoal() {
        val id = host()
        val db = repository!!.database(id)
        val today = LocalDate.now(ZoneId.of(db.head().profile.timeZoneID)).toString()
        val existing = db.setGoals(GoalRecord(UUID.randomUUID(), today, db.head().profile.timeZoneID, 0, NutritionValues(2000.0), null, true), null)
        toResults(viaConnect = true)
        compose.onNodeWithTag("onboardingFat").performTextReplacement("61")
        next()
        compose.waitUntil(10_000) { finished }
        val about = db.head().profile.about!!
        assertEquals(170.0, about.heightCm, 0.0)
        assertEquals(1990, about.birthYear)
        val weight = db.read { tx -> tx.dayWeight(tx.head.activeDayID!!) }!!
        assertEquals(74.0, weight.value, 0.0)
        val goal = db.goal(today, exact = true)!!
        assertEquals(existing.id, goal.id)
        assertTrue(goal.exerciseCreditEnabled)
        assertEquals(68.0, goal.goalWeightKg)
        assertEquals(estimate().copy(fat = 61.0), goal.targets)
    }

    @Test fun redoFromSettingsIsPrefilled() {
        val id = TodayFixture.diary(context)
        repository = DiaryRepository(context)
        val db = repository!!.database(id)
        val profile = db.head().profile
        db.updateProfile(profile.copy(about = ProfileAbout(170.0, 1990, ProfileAbout.Sex.female, ProfileAbout.Pace.gentle, listOf("Vegan"), "")), profile)
        db.recordWeight(74.0)
        compose.activityRule.scenario.onActivity(app)
        waitFor(hasTestTag("profileSettings"))
        compose.onNodeWithTag("profileSettings").performClick()
        waitForText("Redo setup with Pip")
        compose.onNodeWithText("Redo setup with Pip").performClick()
        waitFor(heading("Hi, I'm Pip"))
        next()
        waitFor(heading("About you"))
        compose.onNodeWithTag("onboardingHeight").assertTextContains("170")
        compose.onNodeWithTag("onboardingWeight").assertTextContains("74")
        compose.onNodeWithTag("onboardingBirthYear").assertTextContains("1990")
    }

    @Test fun stepSurvivesActivityRecreation() {
        launchApp()
        waitFor(heading("Hi, I'm Pip"))
        next()
        waitFor(heading("About you"))
        compose.onNodeWithTag("onboardingHeight").performTextReplacement("170")
        compose.activityRule.scenario.recreate()
        compose.activityRule.scenario.onActivity(app)
        waitFor(heading("About you"))
        compose.onNodeWithTag("onboardingHeight").assertTextContains("170")
    }

    @Test fun targetsAtLeast48dpAtFontScale2() {
        host(fontScale = 2f)
        waitFor(heading("Hi, I'm Pip"))
        assertTargets()
        next()
        waitFor(heading("About you"))
        assertTargets()
    }

    private fun assertTargets() {
        compose.waitForIdle()
        val min = with(compose.density) { 48.dp.toPx() } - 0.5f
        compose.onAllNodes(hasClickAction() and SemanticsMatcher("not disabled") { SemanticsProperties.Disabled !in it.config })
            .fetchSemanticsNodes().forEach { node ->
                assertTrue("${node.config} is ${node.touchBoundsInRoot}", node.touchBoundsInRoot.height >= min && node.touchBoundsInRoot.width >= min)
            }
    }
}
