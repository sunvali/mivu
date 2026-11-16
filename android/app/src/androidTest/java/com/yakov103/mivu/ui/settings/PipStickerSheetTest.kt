package com.yakov103.mivu.ui.settings

import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertContentDescriptionEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import com.yakov103.mivu.connection.ConnectionState
import com.yakov103.mivu.stickers.PipStickers
import com.yakov103.mivu.ui.theme.MivuTheme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

/** Emulator has no WhatsApp, so the missing-app path is what runs. */
class PipStickerSheetTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()

    private fun stickerNodes() = compose.onAllNodes(SemanticsMatcher("pipSticker tag") {
        (it.config.getOrNull(SemanticsProperties.TestTag) ?: "").startsWith("pipSticker-")
    })

    @Test fun sheetShowsStickersAndHandlesMissingWhatsApp() {
        compose.setContent { MivuTheme { SettingsScreen(ConnectionState(), onOpenConnection = {}, onBack = {}) } }
        compose.onNodeWithTag("pipStickers").performScrollTo().performClick()
        compose.waitForIdle()
        assertEquals(12, stickerNodes().fetchSemanticsNodes().size)
        PipStickers.all.forEach { compose.onNodeWithTag("pipSticker-" + it.id).assertContentDescriptionEquals(it.accessibilityText) }
        compose.onNodeWithTag("addPipMovesToWhatsApp").assertIsDisplayed()
        compose.onNodeWithTag("addPipToWhatsApp").assertIsDisplayed().performClick()
        compose.onNodeWithTag("whatsAppMissing").assertIsDisplayed()
        compose.onNodeWithText("Get WhatsApp").assertIsDisplayed()
        compose.onNodeWithText("Cancel").assertIsDisplayed()
    }

    @Test fun reducedMotionShowsStillStickers() {
        compose.setContent { MivuTheme { PipStickerSheet(onDismiss = {}, animate = false) } }
        compose.waitForIdle()
        compose.onNodeWithTag("pipSticker-hi").assert(SemanticsMatcher.keyNotDefined(SemanticsProperties.StateDescription))
    }

    @Test fun animatedStickersAnnounceMotion() {
        compose.setContent { MivuTheme { PipStickerSheet(onDismiss = {}, animate = true) } }
        compose.waitForIdle()
        compose.onNodeWithTag("pipSticker-hi").assert(SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, "animated"))
    }
}
