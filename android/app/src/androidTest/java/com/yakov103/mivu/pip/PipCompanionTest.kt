package com.yakov103.mivu.pip

import androidx.activity.ComponentActivity
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.click
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.longClick
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.unit.dp
import androidx.test.platform.app.InstrumentationRegistry
import com.yakov103.mivu.pip.MotionPolicy.Playback
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import kotlin.random.Random

class PipCompanionTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private val assets = runBlocking { PipAssets.load(InstrumentationRegistry.getInstrumentation().targetContext) }
    private var playback by mutableStateOf(Playback.StaticPose)
    private val touches = mutableListOf<CompanionTouch>()
    private lateinit var runtime: CompanionRuntime

    private fun show() {
        compose.mainClock.autoAdvance = false // an animated Pip never idles
        compose.setContent {
            val scope = rememberCoroutineScope()
            val rt = androidx.compose.runtime.remember {
                CompanionRuntime(assets.second, assets.first, scope, { System.nanoTime() / 1_000_000 }, Random(1)).also { runtime = it }
            }
            PipCompanion(CompanionOutput(CompanionPose.Resting, playback, null), CompanionSurface.Today, 186.dp, rt, { touches += it })
        }
        compose.mainClock.advanceTimeBy(100)
    }

    @Test fun pipIsHiddenFromAccessibility() {
        playback = Playback.Animated
        show()
        val node = compose.onNodeWithTag("pipCompanion").fetchSemanticsNode()
        assertFalse(SemanticsProperties.ContentDescription in node.config)
        assertFalse(SemanticsActions.OnClick in node.config)
        assertFalse(SemanticsActions.OnLongClick in node.config)
        assertTrue(node.children.isEmpty())
    }

    @Test fun staticPlaybackRunsNoFrames() {
        show()
        compose.mainClock.advanceTimeBy(2_000)
        assertEquals(0L, runtime.frames)
        assertEquals(0, runtime.activeJobs)
        playback = Playback.Animated
        compose.mainClock.advanceTimeBy(2_000)
        assertTrue(runtime.frames > 0)
        playback = Playback.StaticPose
        compose.mainClock.advanceTimeBy(100)
        val frames = runtime.frames
        compose.mainClock.advanceTimeBy(2_000)
        assertEquals(frames, runtime.frames)
        assertEquals(0, runtime.activeJobs)
    }

    @Test fun tapPlaysOnlyWhenAnimated() {
        show()
        compose.onNodeWithTag("pipCompanion").performTouchInput { click() }
        compose.mainClock.advanceTimeBy(500)
        assertEquals(emptyList<CompanionTouch>(), touches)
        playback = Playback.Animated
        compose.mainClock.advanceTimeBy(100)
        compose.onNodeWithTag("pipCompanion").performTouchInput { click() }
        compose.mainClock.advanceTimeBy(500)
        assertEquals(listOf(CompanionTouch.Tap), touches)
        compose.onNodeWithTag("pipCompanion").performTouchInput { longClick() }
        compose.mainClock.advanceTimeBy(1_000)
        assertEquals(listOf(CompanionTouch.Tap, CompanionTouch.Pat), touches)
    }
}
