package com.yakov103.mivu.ui.coach

import android.Manifest
import android.content.Context
import android.os.Bundle
import android.speech.SpeechRecognizer
import androidx.activity.ComponentActivity
import androidx.compose.runtime.remember
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.SavedStateHandle
import androidx.test.core.app.ApplicationProvider
import androidx.test.platform.app.InstrumentationRegistry
import com.yakov103.mivu.coach.CoachActivity
import com.yakov103.mivu.diary.DiaryRepository
import com.yakov103.mivu.diary.startDay
import com.yakov103.mivu.ui.coach.CoachVoiceInput.Phase
import com.yakov103.mivu.ui.theme.MivuTheme
import com.yakov103.mivu.ui.today.TodayFixture
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.flow.MutableStateFlow
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test

/** A fake recognizer that only counts releases; the test plays the platform by driving the listener. Synthetic words only. */
class CoachVoiceTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private val context: Context = ApplicationProvider.getApplicationContext()
    private lateinit var repository: DiaryRepository
    private lateinit var profileID: UUID
    private lateinit var model: CoachViewModel
    private lateinit var voice: CoachVoiceInput
    private var released = 0

    @Before fun open() {
        InstrumentationRegistry.getInstrumentation().uiAutomation.grantRuntimePermission(context.packageName, Manifest.permission.RECORD_AUDIO)
        TodayFixture.wipe(context)
        profileID = TodayFixture.diary(context)
        repository = DiaryRepository(context)
        repository.database(profileID).let { it.startDay(Instant.now(), it.head().revision) }
    }

    @After fun close() {
        repository.database(profileID).close()
        TodayFixture.wipe(context)
    }

    private fun launch(available: Boolean = true) {
        model = CoachViewModel(repository, profileID, drain = {}, isConnected = { false },
            activity = MutableStateFlow<Pair<UUID, CoachActivity>?>(null), saved = SavedStateHandle(), prepare = { error("no photos") })
        voice = CoachVoiceInput(context, available) { _, _ -> { released++ } }
        compose.setContent { MivuTheme { CoachComposer(model, showStarters = false, remember { FocusRequester() }, onOpenCamera = {}, hasCamera = true, voice = voice) } }
    }

    private fun listen() {
        compose.onNodeWithContentDescription("Speak your meal").performClick()
        compose.runOnUiThread { voice.listener.onReadyForSpeech(Bundle()) }
        compose.waitForIdle()
    }

    private fun words(text: String, final: Boolean = false) = compose.runOnUiThread {
        val bundle = Bundle().apply { putStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION, arrayListOf(text)) }
        if (final) voice.listener.onResults(bundle) else voice.listener.onPartialResults(bundle)
    }

    @Test fun partialResultsStreamIntoDraft() {
        launch()
        listen()
        words("Two eggs")
        compose.waitUntil(5_000) { model.draft.value.text == "Two eggs" }
        words("Two eggs on toast")
        compose.waitUntil(5_000) { model.draft.value.text == "Two eggs on toast" }
        compose.onNodeWithContentDescription("Stop listening").assertIsDisplayed()
        words("Two eggs on toast and a black coffee", final = true)
        compose.waitUntil(5_000) { voice.phase.value == Phase.Idle }
        assertEquals("Two eggs on toast and a black coffee", model.draft.value.text)
        assertEquals(1, released)
    }

    @Test fun errorKeepsTextAndShowsNote() {
        launch()
        listen()
        words("Synthetic soup")
        compose.runOnUiThread { voice.listener.onError(SpeechRecognizer.ERROR_NETWORK) }
        compose.onNodeWithTag("coachVoiceNote").assertIsDisplayed()
        assertEquals("Voice input stopped. Your text is kept.", voice.note.value)
        assertEquals("Synthetic soup", model.draft.value.text)
        assertEquals(1, released)
        // A busy recognizer cannot start again until released; the same note, nothing lost.
        compose.runOnUiThread { voice.start("Synthetic soup") {}; voice.listener.onError(SpeechRecognizer.ERROR_RECOGNIZER_BUSY) }
        assertEquals(Phase.Idle, voice.phase.value)
        compose.runOnUiThread { voice.start("") {}; voice.listener.onError(SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS) }
        assertEquals("Allow microphone access in Settings to log by voice.", voice.note.value)
    }

    @Test fun unavailableShowsMessage() {
        launch(available = false)
        compose.onNodeWithContentDescription("Speak your meal").assertIsNotEnabled()
        compose.onNodeWithTag("coachVoiceNote").assertIsDisplayed()
        assertEquals("Voice input isn't available on this phone. Type, or use the keyboard microphone.", voice.note.value)
        assertEquals(0, released)
    }

    @Test fun stopButtonHasSpokenLabel() {
        launch()
        listen()
        compose.onNodeWithContentDescription("Stop listening").assertIsDisplayed().performClick()
        compose.onNodeWithContentDescription("Speak your meal").assertIsDisplayed()
        assertEquals(1, released)
    }

    @Test fun pausingStopsListening() {
        launch()
        listen()
        words("Synthetic rice")
        compose.activityRule.scenario.moveToState(Lifecycle.State.STARTED)
        compose.waitUntil(5_000) { voice.phase.value == Phase.Idle }
        assertEquals(1, released)
        assertEquals("Synthetic rice", model.draft.value.text)
    }

    /** The default recognizer starts and releases on any supported API level (no on-device-only calls). */
    @Test fun defaultRecognizerStartsAndReleases() {
        assumeTrue(SpeechRecognizer.isRecognitionAvailable(context))
        val real = CoachVoiceInput(context)
        compose.runOnUiThread { real.start("") {} }
        assertEquals(Phase.Preparing, real.phase.value)
        assertNull(real.note.value)
        compose.runOnUiThread { real.stop() }
        assertEquals(Phase.Idle, real.phase.value)
    }
}
