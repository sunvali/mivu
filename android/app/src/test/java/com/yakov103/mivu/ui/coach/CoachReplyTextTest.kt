package com.yakov103.mivu.ui.coach

import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import org.junit.Assert.assertEquals
import org.junit.Test

class CoachReplyTextTest {
    @Test fun boldItalicAndDroppedLinks() {
        val text = coachReplyText("Saved — about **430** kcal. *Nice* and _steady_, see [Today](https://example.com) or snake_case_name.")
        assertEquals("Saved — about 430 kcal. Nice and steady, see Today or snake_case_name.", text.text)
        fun styled(word: String) = text.spanStyles.single { text.text.substring(it.start, it.end) == word }.item
        assertEquals(FontWeight.Bold, styled("430").fontWeight)
        assertEquals(FontStyle.Italic, styled("Nice").fontStyle)
        assertEquals(FontStyle.Italic, styled("steady").fontStyle)
        assertEquals(3, text.spanStyles.size)
        assertEquals(emptyList<Any>(), text.getLinkAnnotations(0, text.length))
    }
}
