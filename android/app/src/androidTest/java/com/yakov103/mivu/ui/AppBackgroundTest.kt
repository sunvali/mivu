package com.yakov103.mivu.ui

import android.content.Context
import androidx.activity.ComponentActivity
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isSelectable
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.performClick
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.ViewModelProvider
import androidx.test.core.app.ApplicationProvider
import com.yakov103.mivu.diary.Bootstrap
import com.yakov103.mivu.diary.DiaryRepository
import com.yakov103.mivu.pip.CompanionLastActive
import com.yakov103.mivu.pip.CompanionPose
import com.yakov103.mivu.pip.MotionPolicy.Playback
import com.yakov103.mivu.ui.theme.MivuTheme
import com.yakov103.mivu.ui.today.TodayFixture
import com.yakov103.mivu.ui.today.TodayViewModel
import java.util.UUID
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test

/** As iOS, every trip to the background resets Pip on Today and Coach and records last-active, whichever tab shows. */
class AppBackgroundTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private val context: Context = ApplicationProvider.getApplicationContext()
    private var repository: DiaryRepository? = null
    private lateinit var profileID: UUID

    @Before fun wipe() = TodayFixture.wipe(context)

    @After fun close() {
        (repository?.bootstrapState?.value as? Bootstrap.Ready)?.let { repository!!.database(it.profileID).close() }
        TodayFixture.wipe(context)
    }

    private fun launch() {
        profileID = TodayFixture.seed(context, photo = false)
        val repository = DiaryRepository(context).also { repository = it }
        compose.setContent { MivuTheme { MivuApp(repository) } }
        compose.waitUntil(10_000) { compose.onAllNodes(hasText("Coach") and isSelectable()).fetchSemanticsNodes().isNotEmpty() }
    }

    private fun today(): TodayViewModel {
        var model: TodayViewModel? = null
        compose.runOnUiThread { model = ViewModelProvider(compose.activity)["today-$profileID", TodayViewModel::class.java] }
        return model!!
    }

    private fun tab(label: String) = compose.onNode(hasText(label) and isSelectable()).performClick()

    /** Stops and restarts the activity, as leaving the app and coming back. */
    private fun backgroundAndBack() {
        compose.activityRule.scenario.moveToState(Lifecycle.State.CREATED)
        compose.activityRule.scenario.moveToState(Lifecycle.State.RESUMED)
    }

    @Test fun leavingFromCoachGreetsAgainOnToday() {
        launch()
        val today = today()
        compose.waitUntil(10_000) { today.companion.value.pose == CompanionPose.Greeting }
        compose.waitUntil(10_000) { today.companion.value.pose == CompanionPose.Resting }
        tab("Coach")
        compose.waitUntil(10_000) { compose.onAllNodesWithTag("coachTimeline").fetchSemanticsNodes().isNotEmpty() }
        backgroundAndBack()
        tab("Today")
        compose.waitUntil(10_000) { today.companion.value.pose == CompanionPose.Greeting }
    }

    @Test fun leavingFromCoachRecordsLastActiveSoTheNextStartGreets() {
        val lastActive = CompanionLastActive(DiaryRepository.preferences(context))
        launch()
        // Last used yesterday ("Monday"); today ("Tuesday") the person opens Coach and leaves from there.
        lastActive.record(profileID, System.currentTimeMillis() - 86_400_000)
        tab("Coach")
        val before = System.currentTimeMillis()
        compose.activityRule.scenario.moveToState(Lifecycle.State.CREATED)
        val recorded = lastActive.at(profileID)
        assertTrue("leaving from Coach records last-active: $recorded", recorded != null && recorded >= before)
        // A cold start later today greets instead of welcoming back.
        var fresh: TodayViewModel? = null
        compose.runOnUiThread {
            fresh = TodayViewModel(repository!!, profileID, sampleMode = false).apply { reportPlayback(Playback.Animated) }
        }
        assertEquals(CompanionPose.Greeting, fresh!!.companion.value.pose)
    }
}
