package com.yakov103.mivu.ui.theme

import android.app.UiModeManager
import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext

/** Mivu colours Material has no role for. Read them with `MivuTheme.colors`. */
data class MivuColors(
    val protein: Color,
    val carbs: Color,
    val fat: Color,
    val warning: Color,
    val success: Color,
    val summarySurface: Color,
)

val LocalMivuColors = staticCompositionLocalOf { mivuColors(dark = false, highContrast = false) }

object MivuTheme {
    val colors: MivuColors @Composable get() = LocalMivuColors.current
}

// Hex values from design-system/mivu/precision-glass/tokens.json; `hc` is the highContrast variant.
private class Token(val light: Long, val dark: Long, val hcLight: Long = light, val hcDark: Long = dark) {
    fun pick(dark: Boolean, highContrast: Boolean) =
        Color(if (dark) (if (highContrast) hcDark else this.dark) else if (highContrast) hcLight else light)
}

private val canvas = Token(0xFFF5F8F8, 0xFF111516)
private val surface = Token(0xFFFFFFFF, 0xFF1D2324)
private val textPrimary = Token(0xFF142023, 0xFFF4F7F6)
private val textSecondary = Token(0xFF53646B, 0xFFB7C4C8)
private val accent = Token(0xFF006D75, 0xFF63D5CD, 0xFF00545C, 0xFF9CEDE6)
private val onAccent = Token(0xFFFFFFFF, 0xFF092126)
private val separator = Token(0xFFD5DFE1, 0xFF374346)
private val error = Token(0xFFB33143, 0xFFFF9BA6, 0xFF8C2030, 0xFFFFC2C9)
private val warning = Token(0xFF925000, 0xFFF4BC62, 0xFF713D00, 0xFFFFDBA0)
private val protein = Token(0xFF195DC2, 0xFF91BCFF, 0xFF124994, 0xFFBAD5FF)
private val carbs = warning
private val fat = Token(0xFF7740AD, 0xFFCCA5F8, 0xFF5E2E8E, 0xFFE2CAFF)
private val success = Token(0xFF237448, 0xFF80D5A4, 0xFF175A34, 0xFFB0EBC6)
private val summarySurface = Token(0xFFEAF5F3, 0xFF142D2D)

// Dark #264544 is the dark accent (#63D5CD) at 25% over the dark canvas (#111516): the tonal pair of light #CCE8E7.
private val accentContainer = Token(0xFFCCE8E7, 0xFF264544)

// Neutral container steps between canvas and separator, so no Material baseline purple tint leaks into bars.
private val containerLowest = Token(0xFFFFFFFF, 0xFF0C1011)
private val containerLow = Token(0xFFF9FBFB, 0xFF161B1C)
private val container = Token(0xFFEEF3F3, 0xFF1D2324)
private val containerHigh = Token(0xFFE8EEEE, 0xFF252C2D)
private val containerHighest = Token(0xFFE2E9EA, 0xFF2F3738)

internal fun mivuColorScheme(dark: Boolean, highContrast: Boolean): ColorScheme {
    fun Token.c() = pick(dark, highContrast)
    // Secondary and tertiary stay on the accent: Mivu has one brand hue, and macro colours live in MivuColors.
    return (if (dark) darkColorScheme() else lightColorScheme()).copy(
        primary = accent.c(), onPrimary = onAccent.c(),
        primaryContainer = accentContainer.c(), onPrimaryContainer = textPrimary.c(),
        inversePrimary = accent.pick(!dark, highContrast),
        secondary = accent.c(), onSecondary = onAccent.c(),
        secondaryContainer = accentContainer.c(), onSecondaryContainer = textPrimary.c(),
        tertiary = accent.c(), onTertiary = onAccent.c(),
        tertiaryContainer = accentContainer.c(), onTertiaryContainer = textPrimary.c(),
        background = canvas.c(), onBackground = textPrimary.c(),
        surface = surface.c(), onSurface = textPrimary.c(),
        surfaceVariant = containerHighest.c(), onSurfaceVariant = textSecondary.c(), surfaceTint = accent.c(),
        inverseSurface = textPrimary.c(), inverseOnSurface = canvas.c(),
        error = error.c(), onError = onAccent.c(),
        outline = textSecondary.c(), outlineVariant = separator.c(),
        surfaceBright = if (dark) containerHighest.c() else containerLowest.c(),
        surfaceDim = if (dark) containerLowest.c() else containerHighest.c(),
        surfaceContainerLowest = containerLowest.c(), surfaceContainerLow = containerLow.c(),
        surfaceContainer = container.c(), surfaceContainerHigh = containerHigh.c(),
        surfaceContainerHighest = containerHighest.c(),
    )
}

internal fun mivuColors(dark: Boolean, highContrast: Boolean) = MivuColors(
    protein.pick(dark, highContrast), carbs.pick(dark, highContrast), fat.pick(dark, highContrast),
    warning.pick(dark, highContrast), success.pick(dark, highContrast), summarySurface.pick(dark, highContrast),
)

/** Mivu's fixed brand palette (dynamic colour is off), light or dark with the system, high contrast from API 34. */
@Composable
fun MivuTheme(content: @Composable () -> Unit) {
    val dark = isSystemInDarkTheme()
    val highContrast = systemHighContrast()
    CompositionLocalProvider(LocalMivuColors provides mivuColors(dark, highContrast)) {
        MaterialTheme(colorScheme = mivuColorScheme(dark, highContrast), content = content)
    }
}

/** The system contrast level is above standard; API 31–33 has no such setting. */
@Composable
private fun systemHighContrast(): Boolean {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return false
    val modes = LocalContext.current.getSystemService(UiModeManager::class.java)
    var high by remember { mutableStateOf(modes.contrast > 0f) }
    DisposableEffect(modes) {
        val listener = UiModeManager.ContrastChangeListener { high = it > 0f }
        modes.addContrastChangeListener(Runnable::run, listener)
        onDispose { modes.removeContrastChangeListener(listener) }
    }
    return high
}
