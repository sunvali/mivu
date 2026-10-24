package com.yakov103.mivu.ui.today

import android.content.Context
import androidx.activity.ComponentActivity
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.core.app.ApplicationProvider
import com.yakov103.mivu.connection.AccountState
import com.yakov103.mivu.connection.ConnectionState
import com.yakov103.mivu.diary.DiaryRepository
import com.yakov103.mivu.ui.theme.MivuTheme
import java.util.UUID
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Rule
import org.junit.Test

/** iOS TodayView plan welcome: once, after ChatGPT connects, and only while nothing covers Today. Synthetic states only. */
class PlanWelcomeTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private val context: Context = ApplicationProvider.getApplicationContext()
    private lateinit var repository: DiaryRepository
    private lateinit var profileID: UUID
    private var connection by mutableStateOf(ConnectionState(consented = true))
    private var covered by mutableStateOf(false)
    private var acknowledged = 0
    private val title = "You're using your ChatGPT plan"

    @Before fun open() {
        TodayFixture.wipe(context)
        profileID = TodayFixture.diary(context)
        repository = DiaryRepository(context)
        val model = TodayViewModel(repository, profileID, false)
        compose.setContent {
            MivuTheme {
                TodayScreen(model, onOpenMeal = null, onLogWithPip = {}, onAddManually = {}, onLogMeal = {},
                    planWelcome = connection.showsPlanWelcome && !covered,
                    onPlanWelcomeDone = { acknowledged++; connection = connection.copy(planWelcomeSeen = true) })
            }
        }
        compose.waitUntil(10_000) { compose.onAllNodes(hasText("Meals")).fetchSemanticsNodes().isNotEmpty() }
    }

    @After fun close() {
        repository.database(profileID).close()
        TodayFixture.wipe(context)
    }

    private fun shown() = compose.onAllNodes(hasText(title)).fetchSemanticsNodes().isNotEmpty()

    @Test fun shownOnceAfterConnect() {
        compose.onNodeWithText(title).assertDoesNotExist()
        connection = connection.copy(account = AccountState.connected)
        compose.waitUntil(5_000) { shown() }
        compose.onNodeWithText("Coach and meal analysis in Mivu use your ChatGPT plan and count toward its usage limits.").assertIsDisplayed()
        compose.onNodeWithText("Manage usage").assertIsDisplayed()
        compose.onNodeWithText("Got it").performClick()
        compose.waitUntil(5_000) { !shown() }
        assertEquals(1, acknowledged)
        // Reconnecting later does not show it again.
        connection = connection.copy(account = AccountState.disconnected)
        compose.waitForIdle()
        connection = connection.copy(account = AccountState.connected)
        compose.waitForIdle()
        assertEquals(false, shown())
    }

    @Test fun hiddenWhileSheetOpen() {
        covered = true
        connection = connection.copy(account = AccountState.connected)
        compose.waitForIdle()
        assertEquals(false, shown())
        assertEquals(0, acknowledged) // waiting, not dropped
        covered = false
        compose.waitUntil(5_000) { shown() }
    }
}
