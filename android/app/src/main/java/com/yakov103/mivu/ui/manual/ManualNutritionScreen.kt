package com.yakov103.mivu.ui.manual

import android.text.format.DateFormat
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.window.DialogWindowProvider
import androidx.core.view.WindowCompat
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
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
import com.yakov103.mivu.ui.theme.MivuTheme
import com.yakov103.mivu.ui.today.isLargeText
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import androidx.compose.ui.platform.LocalConfiguration
import java.util.UUID

/** iOS `ManualNutritionView` as an M3 full-screen dialog: Close and Save in the top bar, outlined fields, "Discard changes?" on back. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ManualNutritionScreen(model: ManualNutritionViewModel, onClose: () -> Unit, onSaved: (UUID) -> Unit) {
    val draft = model.draft
    var showDiscard by rememberSaveable { mutableStateOf(false) }
    val focus = LocalFocusManager.current
    val canSave = !model.saving && runCatching { draft.item(UUID.randomUUID()) }.isSuccess
    val close = { focus.clearFocus(); if (draft.isDirty) showDiscard = true else onClose() }

    LaunchedEffect(model.savedMealID) { model.savedMealID?.let(onSaved) }
    BackHandler { if (!model.saving) close() }
    // The dialog's own window draws behind the system bars: give them the app's light or dark icons.
    val view = LocalView.current
    val lightBars = MaterialTheme.colorScheme.background.luminance() > 0.5f
    SideEffect {
        (view.parent as? DialogWindowProvider)?.window?.let {
            WindowCompat.getInsetsController(it, view).run { isAppearanceLightStatusBars = lightBars; isAppearanceLightNavigationBars = lightBars }
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(if (model.appending) "Add food manually" else "Enter nutrition", Modifier.semantics { heading() }) },
                navigationIcon = {
                    IconButton(close, Modifier.testTag("cancelManualNutrition"), enabled = !model.saving) {
                        Icon(painterResource(R.drawable.ic_close), contentDescription = "Cancel")
                    }
                },
                actions = {
                    Button({ focus.clearFocus(); model.save() }, Modifier.padding(end = 8.dp).testTag("saveManualNutrition"), enabled = canSave) {
                        Text("Save")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background),
            )
        },
        containerColor = MaterialTheme.colorScheme.background,
    ) { padding ->
        Column(
            Modifier.fillMaxSize().padding(padding).consumeWindowInsets(padding).imePadding()
                .verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
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

    if (showDiscard) {
        AlertDialog(
            onDismissRequest = { showDiscard = false },
            title = { Text("Discard changes?") },
            text = { Text("Your unsaved food and nutrition will be discarded.") },
            confirmButton = {
                TextButton({ showDiscard = false; onClose() }) { Text("Discard changes", color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton({ showDiscard = false }) { Text("Keep editing") } },
        )
    }
}

private val Decimal = KeyboardOptions(keyboardType = KeyboardType.Decimal, imeAction = ImeAction.Next)

@Composable
private fun SectionTitle(text: String, modifier: Modifier = Modifier) {
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
    val locale = LocalConfiguration.current.locales[0]
    val date = runCatching {
        LocalDate.parse(localDate).format(DateTimeFormatter.ofPattern(DateFormat.getBestDateTimePattern(locale, "EEEMMMd"), locale))
    }.getOrDefault(localDate)
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
