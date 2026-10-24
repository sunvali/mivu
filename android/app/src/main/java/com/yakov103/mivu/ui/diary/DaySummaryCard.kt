package com.yakov103.mivu.ui.diary

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.SizeTransform
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.yakov103.mivu.R
import com.yakov103.mivu.diary.DayCompleteness
import com.yakov103.mivu.diary.DayDetail
import com.yakov103.mivu.diary.DayStatus
import com.yakov103.mivu.diary.dayStatus
import com.yakov103.mivu.diary.NutritionTotals
import com.yakov103.mivu.ui.theme.MivuTheme
import com.yakov103.mivu.ui.today.isLargeText
import com.yakov103.mivu.ui.today.tabular
import java.text.NumberFormat
import java.util.UUID

// Swift `.number.precision(.fractionLength(n))`: grouped, fixed decimals.
private fun Double.fixed(digits: Int): String =
    NumberFormat.getNumberInstance().apply { minimumFractionDigits = digits; maximumFractionDigits = digits }.format(this)

/** iOS DaySections summary: the date and status chip, recorded intake, the kcal target and the morning weight. */
@Composable
internal fun DaySummaryCard(title: String, detail: DayDetail, totals: NutritionTotals, activeDayID: UUID?, onSetSkipped: (Boolean) -> Unit,
                            modifier: Modifier = Modifier) {
    val status = dayStatus(listOf(detail.day), activeDayID, detail.meals.any { it.revision > 0 }) ?: DayStatus.Open
    Surface(modifier.fillMaxWidth().testTag("diaryDaySummary"), shape = RoundedCornerShape(28.dp), color = MivuTheme.colors.summarySurface) {
        Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            // Side by side when they fit, as iOS ViewThatFits; stacked otherwise.
            FlowRow(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalArrangement = Arrangement.spacedBy(8.dp),
                itemVerticalAlignment = Alignment.CenterVertically,
            ) {
                Text(title, Modifier.padding(end = 8.dp).semantics { heading() }, style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.Bold)
                DayStatusChip(status, detail.day.completeness == DayCompleteness.untracked, onSetSkipped)
            }
            NutritionSummary(totals.kcal, totals.protein, totals.carbs, totals.fat, totals.unknownItemCount > 0)
            val target = detail.goal?.targets?.kcal?.takeIf { it > 0 }
            val kcal = totals.kcal
            val targetLine = if (target != null && kcal != null) "${kcal.fixed(0)} of ${target.fixed(0)} kcal target" else null
            val weightLine = detail.weight?.let { "Morning weight ${NumberFormat.getNumberInstance().format(it.value)} ${it.unit}" }
            if (target != null && kcal != null) {
                LinearProgressIndicator(
                    progress = { (minOf(kcal, target) / target).toFloat() },
                    modifier = Modifier.fillMaxWidth().clearAndSetSemantics {},
                    trackColor = MaterialTheme.colorScheme.surface,
                )
            }
            listOfNotNull(targetLine, weightLine).takeIf { it.isNotEmpty() }?.let { lines ->
                Text(lines.joinToString(" · "),
                    style = MaterialTheme.typography.bodyMedium.tabular(), color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

/** iOS NutritionSummary: "Recorded intake", kcal at 48 sp in the accent, and protein, carbs and fat to one decimal. */
@Composable
private fun NutritionSummary(kcal: Double?, protein: Double?, carbs: Double?, fat: Double?, unknownNote: Boolean) {
    val large = isLargeText()
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("Recorded intake", style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
        Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            AnimatedContent(
                kcal?.fixed(0) ?: "—",
                transitionSpec = {
                    (slideInVertically { it / 2 } + fadeIn()) togetherWith (slideOutVertically { -it / 2 } + fadeOut()) using
                        SizeTransform(clip = false)
                },
                label = "kcal",
            ) { text ->
                Text(text, Modifier.testTag("nutritionEnergy"),
                    style = MaterialTheme.typography.displayMedium.tabular().copy(fontSize = 48.sp, lineHeight = 54.sp, letterSpacing = (-1).sp),
                    fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.primary)
            }
            Text("kcal", Modifier.padding(bottom = 8.dp), style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        val metrics = listOf(Triple("Protein", protein, MivuTheme.colors.protein), Triple("Carbs", carbs, MivuTheme.colors.carbs),
            Triple("Fat", fat, MivuTheme.colors.fat))
        if (large) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) { metrics.forEach { (t, v, c) -> Metric(t, v, c, inline = true) } }
        } else {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                metrics.forEach { (t, v, c) -> Metric(t, v, c, Modifier.weight(1f)) }
            }
        }
        if (unknownNote) {
            Text("Some nutrients are unknown. Recorded totals may be incomplete.", style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun Metric(title: String, grams: Double?, color: Color, modifier: Modifier = Modifier, inline: Boolean = false) {
    val bar = @Composable { Box(Modifier.size(24.dp, 3.dp).background(color, CircleShape)) }
    val name = @Composable { Text(title, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurface) }
    val value = @Composable {
        Text(grams?.let { "${it.fixed(1)} g" } ?: "—", style = MaterialTheme.typography.titleMedium.tabular(),
            fontWeight = FontWeight.SemiBold, color = color)
    }
    val merged = modifier.semantics(mergeDescendants = true) {}
    // Large text: one row per macro, the value at the end, so three macros do not fill the screen.
    if (inline) {
        Row(merged.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            bar(); Box(Modifier.weight(1f)) { name() }; value()
        }
    } else {
        Column(merged, verticalArrangement = Arrangement.spacedBy(4.dp)) { bar(); name(); value() }
    }
}

/** iOS DayStatusChip: shows open, closed or skipped; its menu skips the day or counts it again. */
@Composable
private fun DayStatusChip(status: DayStatus, isMarkedSkipped: Boolean, onSetSkipped: (Boolean) -> Unit) {
    var open by rememberSaveable { mutableStateOf(false) }
    val title = status.name
    Box {
        Surface(
            onClick = { open = true },
            modifier = Modifier.testTag("diaryDayStatusChip").clearAndSetSemantics {
                contentDescription = "Day status"
                stateDescription = title
                role = Role.DropdownList
                onClick { open = true; true }
            },
            shape = RoundedCornerShape(12.dp),
            color = MaterialTheme.colorScheme.primaryContainer,
        ) {
            Row(Modifier.heightIn(min = 48.dp).padding(start = 12.dp, end = 6.dp), verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Box(Modifier.size(8.dp).background(status.color, CircleShape))
                Text(title, style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.Medium,
                    color = MaterialTheme.colorScheme.onPrimaryContainer)
                Icon(painterResource(R.drawable.ic_arrow_drop_down), contentDescription = null, tint = MaterialTheme.colorScheme.onPrimaryContainer)
            }
        }
        DropdownMenu(open, onDismissRequest = { open = false }, shape = RoundedCornerShape(16.dp)) {
            Text("Skipped days stay out of your statistics.", Modifier.padding(horizontal = 16.dp, vertical = 8.dp).width(220.dp),
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            DropdownMenuItem(
                text = { Text(if (isMarkedSkipped) "Count This Day" else "Skip This Day") },
                onClick = { open = false; onSetSkipped(!isMarkedSkipped) },
                leadingIcon = { Icon(painterResource(if (isMarkedSkipped) R.drawable.ic_undo else R.drawable.ic_skip_next), contentDescription = null) },
            )
        }
    }
}
