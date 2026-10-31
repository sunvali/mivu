package com.yakov103.mivu.ui.today

import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.yakov103.mivu.R
import com.yakov103.mivu.diary.wakingDayTitle
import com.yakov103.mivu.ui.progress.progressNumber
import com.yakov103.mivu.ui.theme.MivuTheme
import java.text.NumberFormat
import kotlin.math.abs
import kotlinx.coroutines.launch

// Port of ios/Mivu/Diary/MorningCheckInCard.swift (mockup frames 3 and 4).

/**
 * Shown after a new waking day starts: the last day's recap and an optional weigh-in. Nothing here blocks logging; the
 * first meal of the day hides it. [compact] is Coach's short weigh-in bubble above Pip, shown only while [MorningState.asking].
 */
@Composable
fun MorningCheckInCard(
    state: MorningState,
    unit: String,
    onUnit: (String) -> Unit,
    onSave: suspend (kg: Double) -> Boolean,
    onSkip: () -> Unit,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
    compact: Boolean = false,
    onTellCoach: (() -> Unit)? = null,
) {
    var weight by rememberSaveable(state.dayID) { mutableStateOf("") }
    var saving by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val haptic = LocalHapticFeedback.current
    val focus = LocalFocusManager.current
    val entered = progressNumber(weight)?.takeIf { it > 0 }?.let { if (unit == "lb") it * KG_PER_LB else it }?.takeIf { it in 20.0..400.0 }
    val save = {
        if (entered != null && !saving) scope.launch {
            saving = true
            focus.clearFocus()
            if (onSave(entered)) { weight = ""; haptic.performHapticFeedback(HapticFeedbackType.Confirm) }
            saving = false
        }
    }
    val field = @Composable { m: Modifier ->
        WeightField(weight, { weight = it }, unit, onUnit, state.lastKg?.let { display(it, unit) }, labelled = !compact, onDone = { save() }, m)
    }
    val saveButton = @Composable { m: Modifier ->
        Button({ save() }, m.heightIn(min = 48.dp).testTag("morningWeightSave"), enabled = entered != null && !saving) {
            if (saving) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp) else Text("Save")
        }
    }
    val skip = { focus.clearFocus(); onSkip() }

    if (compact) {
        if (!state.asking) return
        Surface(modifier.fillMaxWidth(), shape = RoundedCornerShape(20.dp), color = MaterialTheme.colorScheme.surfaceContainerHigh,
            shadowElevation = 2.dp) {
            Column(Modifier.padding(start = 14.dp, end = 4.dp, top = 4.dp, bottom = 4.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("${state.greeting}. Weighed in yet?", Modifier.weight(1f).testTag("morningCheckIn"),
                        style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                    DismissButton(onDismiss)
                }
                Row(Modifier.padding(end = 10.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    field(Modifier.weight(1f))
                    saveButton(Modifier)
                }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    onTellCoach?.let { TextButton(it, Modifier.heightIn(min = 48.dp).testTag("morningTellCoach")) { Text("Tell Coach instead") } }
                    Spacer(Modifier.weight(1f))
                    TextButton(skip, Modifier.heightIn(min = 48.dp).testTag("morningWeightSkip")) { Text("Skip") }
                }
            }
        }
        return
    }

    WhiteCard(modifier) {
        Column(Modifier.padding(20.dp).animateContentSize(), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(state.greeting, Modifier.weight(1f).semantics { heading() }.testTag("morningCheckIn"),
                    style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                DismissButton(onDismiss)
            }
            state.recap?.let { recap ->
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(wakingDayTitle(recap.previous.localDate, relativeTo = state.localDate),
                        style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    val kcal = recap.previous.totals.kcal ?: 0.0
                    val whole = NumberFormat.getIntegerInstance()
                    Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text(whole.format(kcal), style = MaterialTheme.typography.headlineSmall.tabular(), fontWeight = FontWeight.Bold)
                        Text(recap.targetKcal?.let { "of ${whole.format(it)} kcal" } ?: "kcal", Modifier.padding(bottom = 3.dp),
                            style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    recap.targetKcal?.takeIf { it > 0 }?.let { target ->
                        LinearProgressIndicator(
                            progress = { minOf(kcal / target, 1.0).toFloat() },
                            modifier = Modifier.fillMaxWidth().semantics { contentDescription = "Intake toward that day's goal" },
                        )
                    }
                }
            }
            if (state.asking) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    WeightLabel("Morning weight")
                    field(Modifier.fillMaxWidth())
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        OutlinedButton(skip, Modifier.weight(1f).heightIn(min = 48.dp).testTag("morningWeightSkip")) { Text("Skip") }
                        saveButton(Modifier.weight(1f))
                    }
                }
            } else {
                state.todayWeight?.let { entry ->
                    val kg = if (entry.unit == "lb") entry.value * KG_PER_LB else entry.value
                    Row(Modifier.heightIn(min = 48.dp).semantics(mergeDescendants = true) {}, verticalAlignment = Alignment.CenterVertically) {
                        WeightLabel("${display(kg, unit)} $unit", Modifier.weight(1f))
                        // The weekly trend, not the day-to-day change: daily swings are mostly water.
                        state.trendKg?.let { trend ->
                            Text("${if (trend > 0) "+" else if (trend < 0) "−" else ""}${display(abs(trend), unit)} $unit this week",
                                style = MaterialTheme.typography.bodyMedium.tabular(), color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(painterResource(R.drawable.ic_check_circle), contentDescription = null, tint = MivuTheme.colors.success)
                    Spacer(Modifier.width(8.dp))
                    Text("You're set for today", style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium,
                        color = MivuTheme.colors.success)
                }
            }
        }
    }
}

@Composable
private fun DismissButton(onDismiss: () -> Unit) {
    IconButton(onDismiss, Modifier.testTag("morningDismiss")) {
        Icon(painterResource(R.drawable.ic_close), contentDescription = "Hide check-in", tint = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun WeightLabel(text: String, modifier: Modifier = Modifier) {
    Row(modifier, verticalAlignment = Alignment.CenterVertically) {
        Icon(painterResource(R.drawable.ic_monitor_weight), contentDescription = null, tint = MaterialTheme.colorScheme.primary)
        Spacer(Modifier.width(8.dp))
        Text(text, style = MaterialTheme.typography.bodyLarge.tabular(), fontWeight = FontWeight.Medium)
    }
}

/** The weight field with its kg/lb menu; the placeholder is the last weight in the chosen unit. */
@Composable
private fun WeightField(
    value: String, onValue: (String) -> Unit, unit: String, onUnit: (String) -> Unit, placeholder: String?, labelled: Boolean,
    onDone: () -> Unit, modifier: Modifier,
) {
    val label = "Weight in ${if (unit == "lb") "pounds" else "kilograms"}"
    var menu by remember { mutableStateOf(false) }
    OutlinedTextField(
        value, onValue,
        modifier.testTag("morningWeight").then(if (labelled) Modifier else Modifier.semantics { contentDescription = label }),
        label = if (labelled) ({ Text(label) }) else null,
        placeholder = { Text(placeholder ?: "Weight") },
        singleLine = true,
        textStyle = MaterialTheme.typography.titleLarge.tabular(),
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal, imeAction = ImeAction.Done),
        keyboardActions = KeyboardActions(onDone = { onDone() }),
        trailingIcon = {
            Box {
                // Its own button inside the field's merged node, spoken as "Unit, kg".
                TextButton({ menu = true }, Modifier.heightIn(min = 48.dp).semantics { contentDescription = "Unit, $unit" }) {
                    Row(Modifier.clearAndSetSemantics {}, verticalAlignment = Alignment.CenterVertically) {
                        Text(unit)
                        Icon(painterResource(R.drawable.ic_arrow_drop_down), contentDescription = null)
                    }
                }
                DropdownMenu(menu, { menu = false }) {
                    listOf("kg", "lb").forEach { option ->
                        DropdownMenuItem({ Text(option) }, { menu = false; onUnit(option) })
                    }
                }
            }
        },
    )
}

/** Kilograms shown in [unit], one decimal. */
private fun display(kg: Double, unit: String): String =
    NumberFormat.getNumberInstance().apply { minimumFractionDigits = 1; maximumFractionDigits = 1 }.format(if (unit == "lb") kg / KG_PER_LB else kg)
