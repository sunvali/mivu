package com.yakov103.mivu.ui.progress

import android.text.format.DateFormat
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.selection.toggleable
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.yakov103.mivu.R
import com.yakov103.mivu.diary.GoalRecord
import com.yakov103.mivu.ui.CaptureDialog
import com.yakov103.mivu.ui.today.isLargeText
import java.text.NumberFormat
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.Locale

/** iOS `GoalEditorView` as an M3 full-screen dialog: the effective date, the daily targets, a weight goal and exercise credit. */
@Composable
fun GoalEditorScreen(model: GoalEditorViewModel, onClose: () -> Unit) {
    LaunchedEffect(model.saved) { if (model.saved) onClose() }
    var picking by rememberSaveable { mutableStateOf(false) }
    val values = model.values
    val editable = model.goalLoaded && !model.saving
    CaptureDialog(
        title = "Goals", closeTag = "cancelGoals", saveTag = "saveGoals",
        canSave = values.valid && model.goalLoaded && !model.loading, saving = model.saving, dirty = model.dirty,
        discardTitle = "Discard changes to goals?", discardMessage = null,
        onClose = onClose, onSave = model::save, textSave = true,
    ) {
        EditorSection("Effective date")
        EffectiveDate(values.localDate, enabled = !model.saving) { picking = true }
        EditorNote(if (model.loading) "Loading saved goals…" else "Goals are your settings. Earlier dates keep their own records.")
        model.loadError?.let { LoadError(it, "Retry loading goals", model::loadGoal) }
        History(model)

        EditorSection("Daily targets", Modifier.padding(top = 8.dp))
        val field = @Composable { text: String, label: String, tag: String, modifier: Modifier, set: (String) -> Unit ->
            EditorField(text, set, label, tag, modifier, enabled = editable,
                error = "Enter a positive number, or leave this blank.".takeIf { !validOptional(text) })
        }
        FieldPair(
            { field(values.kcal, "Energy (kcal)", "goalKcal", it) { v -> model.values = model.values.copy(kcal = v) } },
            { field(values.carbs, "Carbs (g)", "goalCarbs", it) { v -> model.values = model.values.copy(carbs = v) } },
        )
        FieldPair(
            { field(values.protein, "Protein (g)", "goalProtein", it) { v -> model.values = model.values.copy(protein = v) } },
            { field(values.fat, "Fat (g)", "goalFat", it) { v -> model.values = model.values.copy(fat = v) } },
        )
        EditorNote("Leave a nutrient blank if you have no target for it.")

        EditorSection("Optional weight goal", Modifier.padding(top = 8.dp))
        field(values.weight, "Weight (kg)", "goalWeight", Modifier.fillMaxWidth()) { v -> model.values = model.values.copy(weight = v) }

        EditorSection("Exercise", Modifier.padding(top = 8.dp))
        Row(
            Modifier.fillMaxWidth().heightIn(min = 48.dp).testTag("exerciseCreditEnabled")
                .toggleable(values.exerciseCredit, enabled = editable, role = Role.Switch) { model.values = model.values.copy(exerciseCredit = it) }
                .padding(horizontal = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text("Include estimated workout energy in an adjusted remaining figure", Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
            Switch(values.exerciseCredit, onCheckedChange = null, enabled = editable)
        }
        EditorNote("Recorded food, remaining from recorded food, and estimated burn are always shown separately.")
    }

    if (picking) PickDate(values.localDate, onDismiss = { picking = false }) { picking = false; model.requestDate(it) }
    model.pendingDate?.let { date ->
        AlertDialog(
            onDismissRequest = { model.pendingDate = null },
            title = { Text("Change the effective date?") },
            text = { Text("Your entered targets have not been saved. Changing the date loads the saved settings for the selected date.") },
            confirmButton = {
                TextButton({ model.loadDate(date) }, Modifier.heightIn(min = 48.dp)) {
                    Text("Discard draft and change date", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = { TextButton({ model.pendingDate = null }, Modifier.heightIn(min = 48.dp)) { Text("Keep editing") } },
        )
    }
    model.saveError?.let { SaveFailed("Could not save goals", it) { model.saveError = null } }
}

/** Two fields across, as the mockup; one per row at large text so labels keep their width. */
@Composable
private fun FieldPair(first: @Composable (Modifier) -> Unit, second: @Composable (Modifier) -> Unit) {
    if (isLargeText()) { first(Modifier.fillMaxWidth()); second(Modifier.fillMaxWidth()) }
    else Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) { first(Modifier.weight(1f)); second(Modifier.weight(1f)) }
}

/** A read-only field that opens the date picker; spoken as one button with its date. */
@Composable
private fun EffectiveDate(localDate: String, enabled: Boolean, onPick: () -> Unit) {
    val locale = LocalConfiguration.current.locales[0]
    val text = runCatching {
        LocalDate.parse(localDate).format(DateTimeFormatter.ofPattern(DateFormat.getBestDateTimePattern(locale, "yMMMd"), locale))
    }.getOrDefault(localDate)
    Box(Modifier.fillMaxWidth()) {
        OutlinedTextField(text, {}, Modifier.fillMaxWidth(), readOnly = true, enabled = enabled, singleLine = true,
            label = { Text("Starting on") },
            trailingIcon = { Icon(painterResource(R.drawable.ic_calendar), contentDescription = null) })
        Box(Modifier.matchParentSize().testTag("goalDate").clickable(enabled = enabled, onClick = onPick).clearAndSetSemantics {
            contentDescription = "Starting on, $text"
            role = Role.Button
            if (enabled) onClick("Choose date") { onPick(); true }
        })
    }
}

@Composable
private fun History(model: GoalEditorViewModel) {
    var open by rememberSaveable { mutableStateOf(false) }
    TextButton({ open = !open }, Modifier.heightIn(min = 48.dp).testTag("goalHistory")) {
        Text("Goal history")
        Icon(painterResource(R.drawable.ic_arrow_drop_down), contentDescription = null)
    }
    if (!open) return
    val page = model.history
    when {
        model.historyError != null -> LoadError(model.historyError!!, "Retry loading history") { model.pageHistory(model.historyBefore) }
        page == null -> EditorNote("Loading goals…")
        page.values.isEmpty() -> EditorNote("No goals set")
        else -> Column {
            page.values.sortedByDescending { it.effectiveLocalDate }.forEach { goal ->
                val selected = goal.effectiveLocalDate == model.values.localDate
                ListItem(
                    headlineContent = { Text("Effective ${goal.effectiveLocalDate}") },
                    supportingContent = { Text(goalHistorySummary(goal)) },
                    trailingContent = if (selected) ({ Icon(painterResource(R.drawable.ic_check), contentDescription = "Selected") }) else null,
                    modifier = Modifier.heightIn(min = 48.dp).testTag("goalPeriod").semantics { this.selected = selected }
                        .clickable(enabled = !model.saving) { model.requestDate(goal.effectiveLocalDate) },
                    colors = ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.background),
                )
            }
        }
    }
    if (page?.hasMore == true) TextButton({ model.pageHistory(page.cursor) }, Modifier.heightIn(min = 48.dp)) { Text("Older goals") }
    if (model.historyBefore != null) TextButton({ model.pageHistory(null) }, Modifier.heightIn(min = 48.dp)) { Text("Latest goals") }
}

/** iOS `goalHistorySummary`. */
internal fun goalHistorySummary(goal: GoalRecord): String {
    val number = NumberFormat.getNumberInstance(Locale.US).apply { maximumFractionDigits = 1 }
    val parts = listOf(
        Triple("Energy", goal.targets.kcal, "kcal"), Triple("Carbs", goal.targets.carbs, "g"),
        Triple("Protein", goal.targets.protein, "g"), Triple("Fat", goal.targets.fat, "g"), Triple("Weight goal", goal.goalWeightKg, "kg"),
    ).mapNotNull { (name, value, unit) -> value?.let { "$name ${number.format(it)} $unit" } } +
        listOfNotNull("Exercise adjustment enabled".takeIf { goal.exerciseCreditEnabled })
    return parts.joinToString(" · ").ifEmpty { "No targets set" }
}

/** The M3 date picker; its dates are UTC midnights. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PickDate(localDate: String, onDismiss: () -> Unit, onChoose: (String) -> Unit) {
    val initial = runCatching { LocalDate.parse(localDate) }.getOrDefault(LocalDate.now())
    val picker = rememberDatePickerState(initialSelectedDateMillis = initial.atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli())
    DatePickerDialog(
        onDismissRequest = onDismiss,
        confirmButton = {
            TextButton(
                { picker.selectedDateMillis?.let { onChoose(Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate().toString()) } },
                Modifier.testTag("applyGoalDate"), enabled = picker.selectedDateMillis != null,
            ) { Text("OK") }
        },
        dismissButton = { TextButton(onDismiss) { Text("Cancel") } },
    ) { DatePicker(picker) }
}
