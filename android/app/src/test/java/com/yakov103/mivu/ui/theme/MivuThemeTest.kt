package com.yakov103.mivu.ui.theme

import androidx.compose.ui.graphics.Color
import org.junit.Assert.assertEquals
import org.junit.Test

class MivuThemeTest {
    @Test fun primaryIsTheTokenAccent() {
        assertEquals(Color(0xFF006D75), mivuColorScheme(dark = false, highContrast = false).primary)
        assertEquals(Color(0xFF63D5CD), mivuColorScheme(dark = true, highContrast = false).primary)
    }

    @Test fun highContrastUsesTheTokenVariants() {
        assertEquals(Color(0xFF00545C), mivuColorScheme(dark = false, highContrast = true).primary)
        assertEquals(Color(0xFF9CEDE6), mivuColorScheme(dark = true, highContrast = true).primary)
        assertEquals(Color(0xFF124994), mivuColors(dark = false, highContrast = true).protein)
    }
}
