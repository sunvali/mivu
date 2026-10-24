package com.yakov103.mivu.ui.composer

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts.PickMultipleVisualMedia
import androidx.activity.result.contract.ActivityResultContracts.PickVisualMedia
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import com.yakov103.mivu.R
import com.yakov103.mivu.ui.CaptureDialog
import com.yakov103.mivu.ui.manual.SectionTitle
import com.yakov103.mivu.ui.manual.dayDate
import com.yakov103.mivu.ui.theme.MivuTheme
import com.yakov103.mivu.ui.today.SampleBanner
import com.yakov103.mivu.ui.today.decode
import java.io.File
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * iOS `MealComposerView` ("Log meal") in sample mode: a note, photos from the system photo picker, the waking day and the
 * review toggle. [manualSavedID] is set when "Enter nutrition manually" saved a food: an empty draft then closes with it.
 */
@Composable
fun MealComposerScreen(
    model: MealComposerViewModel,
    manualSavedID: UUID?,
    onClose: () -> Unit,
    onSaved: (UUID) -> Unit,
    onEnterManually: () -> Unit,
) {
    LaunchedEffect(model.savedMealID) { model.savedMealID?.let(onSaved) }
    LaunchedEffect(manualSavedID) { if (manualSavedID != null && !model.dirty) onSaved(manualSavedID) }
    val picker = rememberLauncherForActivityResult(PickMultipleVisualMedia(MealComposerViewModel.MAX_PHOTOS), model::import)
    val enabled = !model.saving

    CaptureDialog(
        title = "Log meal", closeTag = "cancelMeal", saveTag = "sendMeal",
        canSave = model.canSave, saving = model.saving, dirty = model.dirty,
        discardMessage = "Your unsaved note and photos will be discarded.",
        onClose = onClose, onSave = model::save,
    ) {
        SampleBanner()
        SectionTitle("Meal details", Modifier.padding(top = 8.dp))
        OutlinedTextField(
            model.text, model::updateText, Modifier.fillMaxWidth().testTag("mealText"), enabled = enabled,
            placeholder = { Text("Write what you ate or what changed") },
            supportingText = { Text("Add a note, a photo, or both.") },
            minLines = 4, maxLines = 10,
            keyboardOptions = KeyboardOptions(KeyboardCapitalization.Sentences),
        )

        SectionTitle("Photos", Modifier.padding(top = 8.dp))
        FilledTonalButton(
            { picker.launch(PickVisualMediaRequest(PickVisualMedia.ImageOnly)) },
            Modifier.heightIn(min = 48.dp).testTag("pickPhotos"),
            enabled = enabled && !model.importing && model.photos.size < MealComposerViewModel.MAX_PHOTOS,
        ) {
            Icon(painterResource(R.drawable.ic_photo_library), contentDescription = null, Modifier.size(20.dp))
            Text("Photo library", Modifier.padding(start = 8.dp))
        }
        Text("${model.photos.size} of ${MealComposerViewModel.MAX_PHOTOS} photos", style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
        if (model.importing) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                Text("Importing photo", style = MaterialTheme.typography.bodyMedium)
            }
        }
        if (model.photos.isNotEmpty()) {
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                model.photos.forEachIndexed { index, path ->
                    PhotoTile(path, index + 1, enabled) { model.removePhoto(path) }
                }
            }
        }

        SectionTitle("Waking day", Modifier.padding(top = 16.dp))
        Card {
            val day = model.wakingDay
            Row(Modifier.fillMaxWidth().heightIn(min = 56.dp).padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                if (day != null) {
                    Text("Waking day", Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
                    Text(dayDate(day), style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
                } else {
                    Icon(painterResource(R.drawable.ic_wb_twilight), contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text("A waking day will be started when you save.", style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            HorizontalDivider(Modifier.padding(start = 16.dp), color = MaterialTheme.colorScheme.outlineVariant)
            Row(
                Modifier.fillMaxWidth().heightIn(min = 56.dp)
                    .toggleable(model.reviewFirst, enabled = enabled, role = Role.Switch, onValueChange = model::updateReviewFirst)
                    .padding(horizontal = 16.dp).testTag("reviewFirst"),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Text("Review before saving totals", Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
                Switch(model.reviewFirst, onCheckedChange = null, enabled = enabled)
            }
        }
        Footnote("Saved on this phone before analysis. Pending or unreviewed results do not count in totals. We’ll ask if the waking day needs confirming.")

        Card(Modifier.padding(top = 16.dp)) {
            Row(
                Modifier.fillMaxWidth().heightIn(min = 56.dp).clickable(enabled, role = Role.Button, onClick = onEnterManually)
                    .padding(horizontal = 16.dp).testTag("enterNutritionManually"),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Icon(painterResource(R.drawable.ic_numbers), contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                Text("Enter nutrition manually", style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.primary)
            }
        }
        Footnote("Save known nutrition directly, including when offline.")

        if (manualSavedID != null && model.dirty) {
            Row(Modifier.padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Icon(painterResource(R.drawable.ic_check_circle), contentDescription = null, tint = MivuTheme.colors.success)
                Text("Food saved. Your note and photos are still here and have not been sent.",
                    style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        model.message?.let {
            Text(it, Modifier.padding(4.dp).semantics { liveRegion = LiveRegionMode.Polite },
                style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.error)
        }
    }

    val failed = model.importFailures
    val skipped = model.importSkipped
    if (failed.isNotEmpty() || skipped.isNotEmpty()) {
        val dismiss = { model.importFailures = emptyList(); model.importSkipped = emptyList() }
        fun photos(positions: List<Int>) = positions.joinToString { "Photo $it" }
        AlertDialog(
            onDismissRequest = dismiss,
            title = { Text(if (failed.isEmpty()) "Up to 8 photos per meal" else "Could not import selected photos") },
            text = {
                Text(listOfNotNull(
                    failed.takeIf { it.isNotEmpty() }?.let { "${photos(it)} from this selection could not be imported." },
                    skipped.takeIf { it.isNotEmpty() }?.let { "${photos(it)} ${if (it.size == 1) "was" else "were"} not added: a meal holds up to 8 photos." },
                    "Your other photos and note are preserved.",
                    "Choose a smaller image or another photo.".takeIf { failed.isNotEmpty() },
                ).joinToString(" "))
            },
            confirmButton = { TextButton(dismiss) { Text("OK") } },
        )
    }
}

@Composable
private fun Card(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Surface(modifier.fillMaxWidth(), shape = RoundedCornerShape(16.dp), color = MaterialTheme.colorScheme.surface) {
        Column { content() }
    }
}

@Composable
private fun Footnote(text: String) {
    Text(text, Modifier.padding(horizontal = 4.dp), style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant)
}

private val TILE = 112.dp

/** A picked photo, decoded small from its cache copy, with a 48 dp remove control on its corner. */
@Composable
private fun PhotoTile(path: String, position: Int, enabled: Boolean, onRemove: () -> Unit) {
    val px = with(LocalDensity.current) { TILE.roundToPx() }
    val bitmap by produceState<ImageBitmap?>(null, path) {
        value = withContext(Dispatchers.IO) { runCatching { decode(File(path).readBytes(), px) }.getOrNull() }
    }
    Box(Modifier.size(TILE)) {
        val shape = RoundedCornerShape(12.dp)
        bitmap?.let {
            Image(it, contentDescription = "Attached meal photo $position", Modifier.size(TILE).clip(shape), contentScale = ContentScale.Crop)
        } ?: Box(Modifier.size(TILE).background(MivuTheme.colors.summarySurface, shape))
        IconButton(onRemove, Modifier.align(Alignment.TopEnd).size(48.dp), enabled = enabled) {
            Box(Modifier.size(28.dp).background(MaterialTheme.colorScheme.surface.copy(alpha = 0.9f), CircleShape),
                contentAlignment = Alignment.Center) {
                Icon(painterResource(R.drawable.ic_close), contentDescription = "Remove photo $position", Modifier.size(18.dp),
                    tint = MaterialTheme.colorScheme.onSurface)
            }
        }
    }
}
