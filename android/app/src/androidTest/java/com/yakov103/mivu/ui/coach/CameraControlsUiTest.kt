package com.yakov103.mivu.ui.coach

import androidx.activity.ComponentActivity
import androidx.camera.core.ImageCapture
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertIsNotSelected
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipe
import androidx.compose.ui.unit.Density
import com.yakov103.mivu.ui.theme.MivuTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

/** The flash button and lens bar on their own, with synthetic lenses: the emulator camera has one lens and no flash. */
class CameraControlsUiTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()

    private fun host(fontScale: Float? = null, content: @androidx.compose.runtime.Composable () -> Unit) = compose.setContent {
        val density = LocalDensity.current
        CompositionLocalProvider(LocalDensity provides Density(density.density, fontScale ?: density.fontScale)) {
            MivuTheme { content() }
        }
    }

    @Test fun flashButtonCyclesAndSpeaksMode() {
        val changes = mutableListOf<Int>()
        host {
            var mode by remember { mutableIntStateOf(ImageCapture.FLASH_MODE_AUTO) }
            CameraFlashButton(mode) { mode = it; changes += it }
        }
        val flash = compose.onNodeWithContentDescription("Flash")
        flash.assert(SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, "Auto"))
        flash.performClick()
        flash.assert(SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, "On"))
        flash.performClick()
        flash.assert(SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, "Off"))
        assertEquals(listOf(ImageCapture.FLASH_MODE_ON, ImageCapture.FLASH_MODE_OFF), changes)
    }

    @Test fun flashChoiceIsRemembered() {
        val context = compose.activity
        val before = savedFlash(context)
        try {
            saveFlash(context, ImageCapture.FLASH_MODE_OFF)
            assertEquals(ImageCapture.FLASH_MODE_OFF, savedFlash(context))
        } finally { saveFlash(context, before) }
    }

    @Test fun lensButtonsShowLiveZoomAndPickALens() {
        val picked = mutableListOf<Float>()
        host { CameraLensBar(zoom = 1.4f, lenses = listOf(0.5f, 1f, 3f), onZoom = { picked += it }, onZoomBy = {}) }
        compose.onNodeWithContentDescription("0.5 times zoom").assertIsNotSelected()
        compose.onNodeWithContentDescription("1 times zoom").assertIsSelected().assertTextEquals("1.4×")
        compose.onNodeWithContentDescription("3 times zoom").assertIsNotSelected().performClick()
        assertEquals(listOf(3f), picked)
    }

    @Test fun lensBarHiddenForOneLens() {
        host { CameraLensBar(zoom = 1f, lenses = emptyList(), onZoom = {}, onZoomBy = {}) }
        assertEquals(0, compose.onAllNodesWithContentDescription("1 times zoom").fetchSemanticsNodes().size)
    }

    @Test fun slidingAlongTheLensesZoomsOut() {
        var zoom = 2f
        host { CameraLensBar(zoom = 2f, lenses = listOf(0.5f, 1f, 3f), onZoom = {}, onZoomBy = { zoom *= it }) }
        compose.onNodeWithTag(LENS_BAR_TAG).performTouchInput {
            val dp = density
            swipe(Offset(4 * dp, centerY), Offset(4 * dp + DIAL_DP_PER_DOUBLING * dp, centerY), durationMillis = 400)
        }
        compose.waitForIdle()
        // Slid one doubling to the right: zoom halves, less the touch slop before the dial wakes.
        assertTrue("zoom was $zoom", zoom in 1f..1.2f)
    }

    @Test fun lensBarFitsAtFontScale2() {
        host(fontScale = 2f) { CameraLensBar(zoom = 1.4f, lenses = listOf(0.5f, 1f, 3f), onZoom = {}, onZoomBy = {}) }
        for ((lens, text) in listOf("0.5" to "0.5", "1" to "1.4×", "3" to "3")) {
            val outer = compose.onNode(hasContentDescription("$lens times zoom")).fetchSemanticsNode().boundsInRoot
            val label = compose.onNode(hasText(text), useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
            assertTrue("$lens label $label outside $outer", outer.contains(label.topLeft) && outer.contains(label.bottomRight - Offset(0.5f, 0.5f)))
            assertTrue("$lens button under 48 dp", outer.height >= 48 * compose.density.density - 0.5f)
        }
    }
}
