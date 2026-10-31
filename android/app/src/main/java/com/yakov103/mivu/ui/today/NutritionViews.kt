package com.yakov103.mivu.ui.today

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.GenericShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin

/**
 * iOS switches Today to its stacked layout at accessibility text sizes (AX1, about 1.6x). Android's font scale stops
 * at 2.0, and the side-by-side hero already crowds at 1.3x on a 360 dp phone, so the stacked layout starts there.
 */
@Composable
fun isLargeText(): Boolean = LocalDensity.current.fontScale >= 1.3f

/** Tabular figures, as iOS `.monospacedDigit()`. */
fun TextStyle.tabular() = copy(fontFeatureSettings = "tnum")

/** A 12-lobed scalloped circle: the Material 3 Expressive "cookie" shape behind Pip. */
val CookieShape = GenericShape { size, _ ->
    val r = min(size.width, size.height) / 2
    val cx = size.width / 2
    val cy = size.height / 2
    for (i in 0..240) {
        val a = 2 * PI * i / 240
        val radius = r * (0.92f + 0.08f * cos(12 * a).toFloat())
        val x = cx + radius * cos(a).toFloat()
        val y = cy + radius * sin(a).toFloat()
        if (i == 0) moveTo(x, y) else lineTo(x, y)
    }
    close()
}

/**
 * iOS DiaryMetric as a direction-B chip: a coloured dot, the macro name and its "NN g" value ("—" when unknown).
 * [inline] puts the value at the end of one row, for the stacked large-text layout.
 */
@Composable
fun MacroChip(title: String, value: String?, color: Color, modifier: Modifier = Modifier, inline: Boolean = false) {
    Surface(modifier.semantics(mergeDescendants = true) {}, shape = RoundedCornerShape(16.dp), color = MaterialTheme.colorScheme.surface) {
        val label = @Composable {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Box(Modifier.size(8.dp).background(color, CircleShape))
                Text(title, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        val number = @Composable { Text(value ?: "—", style = MaterialTheme.typography.titleMedium.tabular(), fontWeight = FontWeight.SemiBold) }
        if (inline) {
            Row(Modifier.padding(horizontal = 12.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                label(); Spacer(Modifier.weight(1f)); number()
            }
        } else {
            Column(Modifier.padding(horizontal = 12.dp, vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) { label(); number() }
        }
    }
}
