package com.yakov103.mivu.ui.progress

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.yakov103.mivu.ui.CaptureDialog
import com.yakov103.mivu.ui.manual.dayDate

/** iOS `MorningWeightEditorView` ("Add weight manually") and `WeightCorrectionView` ("Edit weight") as an M3 full-screen dialog. */
@Composable
fun WeightEditorScreen(model: WeightEditorViewModel, onClose: () -> Unit) {
    LaunchedEffect(model.saved) { if (model.saved) onClose() }
    val correcting = model.correcting
    CaptureDialog(
        title = if (correcting) "Edit weight" else "Add weight manually",
        closeTag = "cancelWeight", saveTag = "saveWeight",
        canSave = model.valid && model.loaded, saving = model.saving, dirty = model.dirty,
        discardTitle = if (correcting) "Discard this weight correction?" else "Discard this weight entry?", discardMessage = null,
        onClose = onClose, onSave = model::save, textSave = true,
    ) {
        EditorSection(if (correcting) "Morning weight · ${model.localDate ?: ""}" else "Morning weight")
        if (!correcting) model.localDate?.let { EditorNote("Waking day: ${dayDate(it)}") }
        val showError = model.value.isNotBlank() && !model.valid
        EditorField(model.value, { model.value = it }, if (correcting) "Weight in ${model.unit}" else "Weight (${model.unit})", "weightInput",
            enabled = model.loaded && !model.saving, keyboard = KeyboardType.Decimal, last = true,
            error = if (!showError) null else if (correcting) "Enter a number greater than 0 and no more than 1,000 ${model.unit}."
                else "Enter a weight greater than 0 and no more than 1,000 ${model.unit}.")
        EditorNote(when {
            correcting -> "This corrects the saved measurement for this waking day."
            model.dayID == null -> "Optional. Saving starts or reuses today's waking day."
            else -> "Saving updates only this selected waking day. Other day labels and your active day are preserved."
        })
        model.loadError?.let { LoadError(it, "Retry loading weight", model::load) }
    }
    model.saveError?.let { SaveFailed("Could not save weight", it) { model.saveError = null } }
}

/** A section label, as the mockup's primary-coloured group titles. */
@Composable
internal fun EditorSection(text: String, modifier: Modifier = Modifier) {
    Text(text, modifier.padding(start = 4.dp, end = 4.dp, top = 8.dp).semantics { heading() }, style = MaterialTheme.typography.titleSmall,
        fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.primary)
}

@Composable
internal fun EditorNote(text: String, modifier: Modifier = Modifier) {
    Text(text, modifier.padding(horizontal = 4.dp), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
}

/** An outlined number field: the iOS validation line shows as its error supporting text. */
@Composable
internal fun EditorField(
    value: String, onChange: (String) -> Unit, label: String, tag: String, modifier: Modifier = Modifier.fillMaxWidth(),
    enabled: Boolean = true, error: String? = null, keyboard: KeyboardType = KeyboardType.Decimal, last: Boolean = false,
) {
    OutlinedTextField(
        value, onChange, modifier.heightIn(min = 48.dp).testTag(tag), enabled = enabled, singleLine = true,
        label = { Text(label) },
        isError = error != null,
        supportingText = error?.let { { Text(it, Modifier.semantics { liveRegion = LiveRegionMode.Polite }) } },
        keyboardOptions = KeyboardOptions(keyboardType = keyboard, imeAction = if (last) ImeAction.Done else ImeAction.Next),
    )
}

@Composable
internal fun LoadError(message: String, retry: String, onRetry: () -> Unit) {
    Text(message, Modifier.padding(4.dp).semantics { liveRegion = LiveRegionMode.Polite }, style = MaterialTheme.typography.bodyMedium,
        color = MaterialTheme.colorScheme.error)
    TextButton(onRetry, Modifier.heightIn(min = 48.dp)) { Text(retry) }
}

/** iOS's "Could not save …" alert: OK closes it and the draft stays. */
@Composable
internal fun SaveFailed(title: String, message: String, onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = { Text(message) },
        confirmButton = { TextButton(onDismiss, Modifier.heightIn(min = 48.dp).testTag("saveFailedOK")) { Text("OK") } },
    )
}
