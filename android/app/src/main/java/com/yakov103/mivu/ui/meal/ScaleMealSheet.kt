package com.yakov103.mivu.ui.meal

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.yakov103.mivu.ui.diary.fixed
import com.yakov103.mivu.ui.manual.ManualNutritionDraft
import com.yakov103.mivu.ui.manual.SectionTitle
import com.yakov103.mivu.ui.today.tabular

/** iOS `ScaleMealSheet`: resizes every food by one ratio (10% to 300%) so the meal reaches a calorie total. Failures show in [snackbar]. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ScaleMealSheet(currentKcal: Double, saving: Boolean, snackbar: SnackbarHostState, onDismiss: () -> Unit, onSave: (Double) -> Unit) {
    var target by rememberSaveable { mutableStateOf(currentKcal.fixed(0).filter { it.isDigit() }) }
    val value = ManualNutritionDraft.number(target)?.takeIf { it.isFinite() && it / currentKcal in 0.1..3.0 }
    ModalBottomSheet(onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        SheetColumn {
            SheetTitle("Adjust total")
            SectionTitle("New total")
            OutlinedTextField(
                target, { target = it }, Modifier.fillMaxWidth().testTag("mealTargetKcal"), singleLine = true,
                label = { Text("Total calories") }, suffix = { Text("kcal") },
                textStyle = MaterialTheme.typography.bodyLarge.tabular(),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal, imeAction = ImeAction.Done),
            )
            Text("Every food in this meal is resized by the same amount. Allowed: 10% to 300% of the current ${currentKcal.fixed(0)} kcal.",
                Modifier.padding(horizontal = 4.dp), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            SectionTitle("Preview", Modifier.padding(top = 8.dp))
            KcalFigure(value, "mealPreviewKcal", missing = "No valid total")
            if (value != null) Text("${(value / currentKcal).fixed(2)}× of the current portions", style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
            SheetActions(onDismiss) {
                Button({ value?.let(onSave) }, Modifier.heightIn(min = 48.dp).testTag("saveMealTotal"), enabled = value != null && !saving) { Text("Save") }
            }
            SnackbarHost(snackbar)
        }
    }
}

/** A sheet's scrolling body, so 200% text still reaches the actions. */
@Composable
internal fun SheetColumn(content: @Composable () -> Unit) {
    Column(Modifier.verticalScroll(rememberScrollState()).padding(start = 24.dp, end = 24.dp, bottom = 24.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)) { content() }
}

@Composable
internal fun SheetTitle(text: String) {
    Text(text, Modifier.semantics { heading() }, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
}

/** Cancel and the sheet's confirming action, at the end as M3 dialogs. */
@Composable
internal fun SheetActions(onCancel: () -> Unit, confirm: @Composable RowScope.() -> Unit) {
    Row(Modifier.fillMaxWidth().padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
        TextButton(onCancel, Modifier.heightIn(min = 48.dp)) { Text("Cancel") }
        confirm()
    }
}
