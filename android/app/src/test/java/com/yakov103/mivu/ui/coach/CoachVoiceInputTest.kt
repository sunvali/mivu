package com.yakov103.mivu.ui.coach

import com.yakov103.mivu.ui.coach.CoachVoiceInput.Companion.begin
import com.yakov103.mivu.ui.coach.CoachVoiceInput.Companion.level
import com.yakov103.mivu.ui.coach.CoachVoiceInput.Companion.merged
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class CoachVoiceInputTest {
    @Test fun mergedAddsOneSpace() {
        assertEquals("For breakfast I had two eggs", merged("For breakfast I had", " two eggs "))
        assertEquals("For breakfast I had two eggs", merged("For breakfast I had ", "two eggs"))
        assertEquals("two eggs", merged("", "two eggs\n"))
    }

    @Test fun mergedKeepsDraftOnEmptySpeech() {
        assertEquals("Synthetic toast ", merged("Synthetic toast ", " \n"))
        assertEquals("", merged("", ""))
    }

    @Test fun levelClamps() {
        assertEquals(0f, level(-40f))
        assertEquals(0f, level(-2f))
        assertEquals(0.5f, level(4f))
        assertEquals(1f, level(10f))
        assertEquals(1f, level(30f))
    }

    @Test fun startFailureDestroysRecognizer() {
        var destroyed = 0
        assertThrows(IllegalStateException::class.java) { begin({ throw IllegalStateException("synthetic") }, { destroyed++ }) }
        assertEquals(1, destroyed)
        begin({}, { destroyed++ })()
        assertEquals(2, destroyed)
    }
}
