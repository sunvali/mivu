package com.yakov103.mivu.ui.manual

import android.text.format.DateFormat
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.yakov103.mivu.R
import com.yakov103.mivu.ui.CaptureDialog
import com.yakov103.mivu.ui.theme.MivuTheme
import com.yakov103.mivu.ui.today.isLargeText
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import androidx.compose.ui.platform.LocalConfiguration
import java.util.UUID

/** iOS `ManualNutritionView` as an M3 full-screen dialog: Close and Save in the top bar, outlined fields, "Discard changes?" on back. */
@Composable
fun ManualNutritionScreen(model: ManualNutritionViewModel, onClose: () -> Unit, onSaved: (UUID) -> Unit) {
    val draft = model.draft
    val focus = LocalFocusManager.current
    LaunchedEffect(model.savedMealID) { model.savedMealID?.let(onSaved) }
    CaptureDialog(
        title = if (model.appending) "Add food manually" else "Enter nutrition",
        closeTag = "cancelManualNutrition", saveTag = "saveManualNutrition",
        canSave = runCatching { draft.item(UUID.randomUUID()) }.isSuccess, saving = model.saving, dirty = draft.isDirty,
        discardMessage = "Your unsaved food and nutrition will be discarded.",
        onClose = onClose, onSave = model::save,
    ) {
        val fieldsEnabled = !model.saving
        val pair = @Composable { first: @Composable (Modifier) -> Unit, second: @Composable (Modifier) -> Unit ->
            // Two across as the mockup; one per row at large text so labels and values keep their width.
            if (isLargeText()) { first(Modifier.fillMaxWidth()); second(Modifier.fillMaxWidth()) }
            else Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) { first(Modifier.weight(1f)); second(Modifier.weight(1f)) }
        }
        SectionTitle("Food")
        Field(draft.name, { model.update(draft.copy(name = it)) }, "Food name", "manualFoodName", Modifier.fillMaxWidth(),
            fieldsEnabled, error = "Enter a food name.".takeIf { draft.isDirty && draft.name.isBlank() },
            keyboard = KeyboardOptions(KeyboardCapitalization.Sentences, imeAction = ImeAction.Next))
        pair(
            { Field(draft.quantity, { v -> model.update(draft.copy(quantity = v)) }, "Amount", "manualAmount", it, fieldsEnabled,
                error = draft.amountError, keyboard = Decimal) },
            { Field(draft.unit, { v -> model.update(draft.copy(unit = v)) }, "Unit", "manualUnit", it, fieldsEnabled,
                error = "Enter a unit.".takeIf { draft.unit.isBlank() }, keyboard = KeyboardOptions(imeAction = ImeAction.Next)) },
        )
        SectionTitle("Nutrition for this amount", Modifier.padding(top = 16.dp))
        NutrientField(draft.kcal, { model.update(draft.copy(kcal = it)) }, "Energy (kcal)", "manualCalories", Modifier.fillMaxWidth(), draft, fieldsEnabled)
        pair(
            { NutrientField(draft.protein, { v -> model.update(draft.copy(protein = v)) }, "Protein (g)", "manualProtein", it, draft, fieldsEnabled) },
            { NutrientField(draft.carbs, { v -> model.update(draft.copy(carbs = v)) }, "Carbs (g)", "manualCarbs", it, draft, fieldsEnabled) },
        )
        NutrientField(draft.fat, { model.update(draft.copy(fat = it)) }, "Fat (g)", "manualFat", Modifier.fillMaxWidth(), draft, fieldsEnabled,
            keyboard = Decimal.copy(imeAction = ImeAction.Done), onDone = { focus.clearFocus() })
        Text("Enter at least one nutrient. Leave unknown values blank; zero means a known zero. Saved as entered manually.",
            Modifier.padding(horizontal = 4.dp), style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
        model.recordedDay?.let { RecordedDay(it, model.appending) }
        model.message?.let {
            Text(it, Modifier.padding(4.dp).semantics { liveRegion = LiveRegionMode.Polite },
                style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.error)
        }
        model.reconciledMealID?.let { id ->
            Row(
                Modifier.fillMaxWidth().heightIn(min = 48.dp).clickable(role = Role.Button) { onSaved(id) }.testTag("reconciledManualFood"),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Icon(painterResource(R.drawable.ic_check_circle), contentDescription = null, tint = MivuTheme.colors.success)
                Text("View previously saved food", style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.primary)
            }
        }
    }
}

private val Decimal = KeyboardOptions(keyboardType = KeyboardType.Decimal, imeAction = ImeAction.Next)

@Composable
internal fun SectionTitle(text: String, modifier: Modifier = Modifier) {
    Text(text, modifier.padding(horizontal = 4.dp).semantics { heading() }, style = MaterialTheme.typography.titleSmall,
        fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.onSurfaceVariant)
}

@Composable
private fun NutrientField(
    value: String, onChange: (String) -> Unit, label: String, tag: String, modifier: Modifier, draft: ManualNutritionDraft, enabled: Boolean,
    keyboard: KeyboardOptions = Decimal, onDone: () -> Unit = {},
) = Field(value, onChange, label, tag, modifier, enabled, "Unknown", draft.nutrientError(value), keyboard, onDone)

@Composable
private fun Field(
    value: String, onChange: (String) -> Unit, label: String, tag: String, modifier: Modifier, enabled: Boolean,
    placeholder: String? = null, error: String? = null, keyboard: KeyboardOptions = KeyboardOptions.Default, onDone: () -> Unit = {},
) {
    OutlinedTextField(
        value, onChange, modifier.testTag(tag), enabled = enabled, singleLine = true,
        label = { Text(label) },
        placeholder = placeholder?.let { { Text(it) } },
        isError = error != null,
        supportingText = error?.let { { Text(it) } },
        keyboardOptions = keyboard,
        keyboardActions = KeyboardActions(onDone = { onDone() }),
    )
}

@Composable
private fun RecordedDay(localDate: String, appending: Boolean) {
    val date = dayDate(localDate)
    Surface(Modifier.fillMaxWidth().padding(top = 8.dp), shape = RoundedCornerShape(16.dp), color = MaterialTheme.colorScheme.surface) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Text("Recorded day", Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
                Text(date, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Text(if (appending) "The meal’s original day and time are kept." else "Time will be unspecified.",
                style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

/** A diary day's local date as a short weekday date ("Sat, Oct 24"), or the stored label if it does not parse. */
@Composable
internal fun dayDate(localDate: String): String {
    val locale = LocalConfiguration.current.locales[0]
    return runCatching {
        LocalDate.parse(localDate).format(DateTimeFormatter.ofPattern(DateFormat.getBestDateTimePattern(locale, "EEEMMMd"), locale))
    }.getOrDefault(localDate)
}
