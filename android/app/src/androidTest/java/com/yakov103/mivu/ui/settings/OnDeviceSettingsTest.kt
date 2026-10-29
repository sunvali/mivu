package com.yakov103.mivu.ui.settings

import androidx.activity.ComponentActivity
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.dp
import com.yakov103.mivu.connection.CoachProvider
import com.yakov103.mivu.connection.ConnectionState
import com.yakov103.mivu.connection.NanoStatus
import com.yakov103.mivu.diary.FoodItem
import com.yakov103.mivu.diary.NutritionProvenance
import com.yakov103.mivu.diary.NutritionValues
import com.yakov103.mivu.ui.meal.sourceCaption
import com.yakov103.mivu.ui.theme.MivuTheme
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

/** Synthetic connection states only: no account, no real model. */
class OnDeviceSettingsTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private val chosen = mutableListOf<CoachProvider>()
    private var downloads = 0
    private var state by mutableStateOf(ConnectionState(nano = NanoStatus.available))

    private val footer = "Runs on this phone with no account, but estimates are much less accurate. It only logs meals and changes " +
        "amounts; connect ChatGPT for accurate estimates, questions and other edits."

    private fun screen() = compose.setContent {
        MivuTheme {
            ConnectionScreen(state, onAgree = {}, onConnect = {}, onCancel = {}, onSelectModel = {}, onDisconnect = {}, onBack = {},
                onChoose = { chosen += it; state = state.copy(storedProvider = it) },
                onDownloadNano = { downloads++; state = state.copy(nanoProgress = 0.4f) })
        }
    }

    private fun exists(text: String) = compose.onAllNodesWithText(text, substring = true).fetchSemanticsNodes().isNotEmpty()

    @Test fun availableOffersBothAndChoosingShowsFooter() {
        screen()
        compose.onNodeWithText("ChatGPT (recommended)").assertIsDisplayed().assertHeightIsAtLeast(48.dp)
        compose.onNodeWithText("No account, but much lower accuracy").assertIsDisplayed()
        compose.onNodeWithText("On this phone (Gemini Nano)").assertIsDisplayed().assertHeightIsAtLeast(48.dp).performClick()
        assertEquals(listOf(CoachProvider.onDevice), chosen)
        compose.onNodeWithText(footer).assertIsDisplayed()
        compose.onNodeWithText("Continue with ChatGPT").assertDoesNotExist()
    }

    @Test fun unavailableShowsNoOnDeviceOption() {
        state = ConnectionState()
        screen()
        assertEquals(false, exists("Gemini Nano"))
        assertEquals(false, exists("No account, but much lower accuracy"))
        compose.onNodeWithText("Continue with ChatGPT").assertIsDisplayed()
    }

    @Test fun downloadableKeepsOptionDisabledAndShowsProgress() {
        state = ConnectionState(nano = NanoStatus.downloadable)
        screen()
        compose.onNodeWithText("On this phone (Gemini Nano)").assertIsNotEnabled()
        compose.onNodeWithText("Download Gemini Nano").assertIsDisplayed().assertHeightIsAtLeast(48.dp).performClick()
        assertEquals(1, downloads)
        compose.onNodeWithText("Download Gemini Nano").assertDoesNotExist()
        compose.onNode(SemanticsMatcher.keyIsDefined(SemanticsProperties.ProgressBarRangeInfo)).assertIsDisplayed()
    }

    @Test fun failedDownloadShowsErrorAndKeepsButton() {
        state = ConnectionState(nano = NanoStatus.downloadable, nanoFailed = true)
        screen()
        compose.onNodeWithText("Could not download Gemini Nano. Try again.").assertIsDisplayed()
        compose.onNodeWithText("Download Gemini Nano").assertIsDisplayed()
    }

    @Test fun preparingShowsGettingReady() {
        state = ConnectionState(nano = NanoStatus.preparing)
        screen()
        compose.onNodeWithText("Getting ready…").assertIsDisplayed()
        compose.onNodeWithText("On this phone (Gemini Nano)").assertIsNotEnabled()
    }

    @Test fun settingsRowNamesGeminiNano() {
        state = ConnectionState(nano = NanoStatus.available, storedProvider = CoachProvider.onDevice)
        compose.setContent { MivuTheme { SettingsScreen(state, onOpenConnection = {}, onBack = {}) } }
        compose.onNodeWithText("Gemini Nano").assertIsDisplayed()
    }

    @Test fun estimateLabelNamesGeminiNano() {
        val item = FoodItem(UUID.randomUUID(), "Synthetic toast", 1.0, "slice", NutritionValues(80.0, 14.0, 3.0, 1.0),
            NutritionProvenance.estimate, "ref", false, emptyMap(), estimatedBy = "gemini-nano")
        assertEquals("Estimated nutrition · Gemini Nano", item.sourceCaption)
    }
}
