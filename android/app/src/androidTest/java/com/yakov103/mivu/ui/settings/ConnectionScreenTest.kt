package com.yakov103.mivu.ui.settings

import android.content.Context
import androidx.activity.ComponentActivity
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isHeading
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.core.app.ApplicationProvider
import com.yakov103.mivu.analysis.AvailableModel
import com.yakov103.mivu.connection.AccountState
import com.yakov103.mivu.connection.ConnectionNotice
import com.yakov103.mivu.connection.ConnectionState
import com.yakov103.mivu.diary.Bootstrap
import com.yakov103.mivu.diary.DiaryRepository
import com.yakov103.mivu.ui.MivuApp
import com.yakov103.mivu.ui.theme.MivuTheme
import java.io.File
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test

/** Synthetic states and recording lambdas only: nothing here reaches a real ChatGPT account. */
class ConnectionScreenTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private val context: Context = ApplicationProvider.getApplicationContext()
    private var repository: DiaryRepository? = null
    private val calls = mutableListOf<String>()

    private val models = listOf(AvailableModel("sample-large", "Sample Model Large"), AvailableModel("sample-small", "Sample Model Small"))
    private val connected = ConnectionState(AccountState.connected, "reg-1", models, "sample-large", consented = true)

    @Before @After fun wipe() {
        (repository?.bootstrapState?.value as? Bootstrap.Ready)?.let { repository!!.database(it.profileID).close() }
        File(context.filesDir, "profiles").deleteRecursively()
        DiaryRepository.preferences(context).edit().clear().commit()
    }

    private fun connection(state: ConnectionState, fontScale: Float? = null) = compose.setContent {
        val density = LocalDensity.current
        CompositionLocalProvider(LocalDensity provides Density(density.density, fontScale ?: density.fontScale)) {
            MivuTheme {
                ConnectionScreen(state, onAgree = { calls += "agree" }, onConnect = { calls += "connect" }, onCancel = { calls += "cancel" },
                    onSelectModel = { calls += "select $it" }, onDisconnect = { calls += "disconnect" }, onBack = { calls += "back" })
            }
        }
    }

    private val consentBody = "To estimate nutrition and answer Coach, Mivu sends OpenAI, through your ChatGPT account, what you record: " +
        "meals, photos, messages, weights, workouts, goals and profile details. Your diary stays on this phone, and you can " +
        "disconnect any time in Settings."

    @Test fun profileButtonOpensSettingsAndCoachAiRow() {
        val repository = DiaryRepository(context).also { repository = it }
        compose.setContent { MivuTheme { MivuApp(repository) } }
        compose.waitUntil(10_000) { compose.onAllNodes(hasText("Today") and isHeading()).fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithTag("profileSettings").performClick()
        compose.onNode(hasText("Settings") and isHeading()).assertIsDisplayed()
        compose.onNodeWithText("Coach AI").performClick()
        compose.onNode(hasText("Coach AI") and isHeading()).assertIsDisplayed()
        compose.onNodeWithText("Continue with ChatGPT").assertIsDisplayed()
    }

    @Test fun settingsRowShowsConnectionValue() {
        var state by mutableStateOf(ConnectionState())
        compose.setContent { MivuTheme { SettingsScreen(state, onOpenConnection = { calls += "open" }, onBack = {}) } }
        compose.onNodeWithText("Connect ChatGPT").assertIsDisplayed()
        compose.onNodeWithText("Privacy Policy").assertIsDisplayed()
        compose.onNodeWithText("Calorie and nutrition figures are estimates, not medical advice. Check with a doctor or registered " +
            "dietitian before big changes to how you eat.").assertIsDisplayed()
        state = connected
        compose.onNodeWithText("ChatGPT").assertIsDisplayed()
        compose.onNodeWithText("Coach AI").performClick()
        assertEquals(listOf("open"), calls)
    }

    @Test fun consentShownBeforeFirstConnect() {
        connection(ConnectionState())
        compose.onNodeWithText("Continue with ChatGPT").performClick()
        compose.onNodeWithText("Share with OpenAI?").assertIsDisplayed()
        compose.onNodeWithText(consentBody).assertIsDisplayed()
        compose.onNodeWithText("Agree and Continue").assertIsDisplayed()
        compose.onNodeWithText("Not Now").assertIsDisplayed()
        assertEquals(emptyList<String>(), calls)
    }

    @Test fun agreeRecordsConsentThenConnects() {
        connection(ConnectionState())
        compose.onNodeWithText("Continue with ChatGPT").performClick()
        compose.onNodeWithText("Agree and Continue").performClick()
        assertEquals(listOf("agree", "connect"), calls)
        assertEquals(0, compose.onAllNodesWithText("Share with OpenAI?").fetchSemanticsNodes().size)
    }

    @Test fun notNowChangesNothing() {
        connection(ConnectionState())
        compose.onNodeWithText("Continue with ChatGPT").performClick()
        compose.onNodeWithText("Not Now").performClick()
        assertEquals(emptyList<String>(), calls)
        assertEquals(0, compose.onAllNodesWithText("Share with OpenAI?").fetchSemanticsNodes().size)
    }

    @Test fun consentedConnectSkipsDialog() {
        connection(ConnectionState(consented = true))
        compose.onNodeWithText("Continue with ChatGPT").performClick()
        assertEquals(listOf("connect"), calls)
        assertEquals(0, compose.onAllNodesWithText("Share with OpenAI?").fetchSemanticsNodes().size)
    }

    @Test fun connectedShowsModelPickerAndDisconnect() {
        connection(connected)
        compose.onNodeWithText("ChatGPT connected").assertIsDisplayed()
        compose.onNodeWithText("Sample Model Large").performClick()
        compose.onNodeWithText("Sample Model Small").performClick()
        compose.onNodeWithText("Disconnect ChatGPT").performScrollTo().performClick()
        assertEquals(listOf("select sample-small", "disconnect"), calls)
    }

    @Test fun modelPickerHiddenWithoutModels() {
        connection(connected.copy(models = emptyList(), selectedModel = ""))
        assertEquals(0, compose.onAllNodesWithText("Account model").fetchSemanticsNodes().size)
        compose.onNodeWithText("Disconnect ChatGPT").assertIsDisplayed()
    }

    @Test fun connectingShowsCancel() {
        connection(ConnectionState(isConnecting = true, consented = true))
        compose.onNodeWithText("Connecting").assertIsDisplayed()
        assertEquals(0, compose.onAllNodesWithText("Continue with ChatGPT").fetchSemanticsNodes().size)
        compose.onNodeWithText("Cancel connection").performClick()
        assertEquals(listOf("cancel"), calls)
    }

    @Test fun noticeIsAnnounced() {
        connection(ConnectionState(notice = ConnectionNotice.offline))
        compose.onNode(hasText(ConnectionNotice.offline.text) and
            SemanticsMatcher.expectValue(SemanticsProperties.LiveRegion, LiveRegionMode.Polite), useUnmergedTree = true).assertIsDisplayed()
    }

    @Test fun buttonTitlesFollowState() {
        var state by mutableStateOf(ConnectionState())
        compose.setContent { MivuTheme { ChatGPTConnectButton(state, onAgree = {}, onConnect = {}) } }
        compose.onNodeWithText("Continue with ChatGPT").assertIsDisplayed()
        state = ConnectionState(AccountState.planPermissionMissing, "reg-1")
        compose.onNodeWithText("Enable ChatGPT plan usage").assertIsDisplayed()
        state = connected
        compose.onNodeWithText("Reauthorize ChatGPT").assertIsDisplayed()
        state = connected.copy(isDisconnecting = true)
        compose.onNodeWithText("Reauthorize ChatGPT").assertIsNotEnabled()
    }

    @Test fun targetsAtLeast48dpAtFontScale2() {
        connection(connected, fontScale = 2f)
        // Touch bounds: an icon button draws 40 dp inside its 48 dp target.
        fun SemanticsNodeInteraction.assertTarget() = with(compose.density) {
            val bounds = fetchSemanticsNode().touchBoundsInRoot
            assertTrue("$bounds", bounds.height >= 48.dp.toPx() - 1 && bounds.width >= 48.dp.toPx() - 1)
        }
        compose.onNodeWithContentDescription("Navigate up").assertTarget()
        listOf("Sample Model Large", "Reauthorize ChatGPT", "Disconnect ChatGPT", "Manage usage").forEach {
            compose.onNode(hasText(it) and hasClickAction()).performScrollTo().assertTarget()
        }
    }
}
