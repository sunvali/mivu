package com.yakov103.mivu.ui.meal

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.yakov103.mivu.R
import com.yakov103.mivu.diary.FoodItem
import com.yakov103.mivu.diary.NutritionProvenance
import com.yakov103.mivu.diary.NutritionValues
import com.yakov103.mivu.diary.SwiftJson
import com.yakov103.mivu.diary.diaryCorrectedItem
import com.yakov103.mivu.diary.validateItems
import com.yakov103.mivu.ui.CaptureDialog
import com.yakov103.mivu.ui.diary.fixed
import com.yakov103.mivu.ui.manual.ManualNutritionDraft
import com.yakov103.mivu.ui.manual.SectionTitle
import com.yakov103.mivu.ui.theme.MivuTheme
import com.yakov103.mivu.ui.today.MacroChip
import com.yakov103.mivu.ui.today.isLargeText
import com.yakov103.mivu.ui.today.tabular
import java.util.UUID

/**
 * An open iOS `FoodItemEditor`: the food as it was ([itemJson]), the meal revision and review it belongs to, the typed
 * text and the nutrients the person typed themselves. Serializable so `SavedStateHandle` keeps it through process death.
 */
data class FoodEdit(
    val itemJson: String,
    val revision: Int,
    val submissionID: UUID?,
    val name: String,
    val quantity: String,
    val unit: String,
    val kcal: String,
    val carbs: String,
    val protein: String,
    val fat: String,
    val explicitNutrients: Set<String> = emptySet(),
) : java.io.Serializable {
    val item: FoodItem get() = SwiftJson.decodeFromString(FoodItem.serializer(), itemJson)

    val dirty get() = this != start(item, revision, submissionID)

    /** The food saving would send, or null while a field is invalid (iOS `edited`). */
    fun edited(): FoodItem? {
        val amount = number(quantity)
        if (name.isBlank() || unit.isEmpty() || amount == null || !amount.isFinite() || amount < 0 || amount > 100_000) return null
        val values = listOf(kcal, carbs, protein, fat).map { text ->
            if (text.isEmpty()) null else number(text)?.takeIf { it.isFinite() && it >= 0 && it <= 10_000_000 } ?: return null
        }
        val updated = item.copy(name = name, quantity = amount, unit = unit, nutrition = NutritionValues(values[0], values[1], values[2], values[3]),
            provenance = NutritionProvenance.user)
        return updated.takeIf { runCatching { validateItems(listOf(it)) }.isSuccess }
    }

    /** What saving would record, by the store's own scaling rule. */
    fun preview(): FoodItem? = edited()?.let { runCatching { diaryCorrectedItem(it, item, explicitNutrients) }.getOrNull() }

    fun nutrient(key: String, text: String) = when (key) {
        "kcal" -> copy(kcal = text)
        "carbs" -> copy(carbs = text)
        "protein" -> copy(protein = text)
        else -> copy(fat = text)
    }.copy(explicitNutrients = explicitNutrients + key)

    companion object {
        fun start(item: FoodItem, revision: Int, submissionID: UUID?) = FoodEdit(
            SwiftJson.encodeToString(FoodItem.serializer(), item), revision, submissionID, item.name, item.quantity.plain(), item.unit,
            item.nutrition.kcal.plain(), item.nutrition.carbs.plain(), item.nutrition.protein.plain(), item.nutrition.fat.plain(),
        )
    }
}

private fun number(text: String) = ManualNutritionDraft.number(text)

/** A typed value without a trailing ".0" ("200", "0.5"); blank when unknown. */
private fun Double?.plain() = this?.toBigDecimal()?.stripTrailingZeros()?.toPlainString().orEmpty()

private val Decimal = KeyboardOptions(keyboardType = KeyboardType.Decimal, imeAction = ImeAction.Next)

/**
 * iOS `FoodItemEditor` as an M3 full-screen dialog: the portion with quick multiples, a live preview, "More details" for the
 * name and nutrients, Ask Pip, and Delete food or (for a meal's only food) Delete meal. Failures show in [snackbar].
 */
@Composable
internal fun FoodItemEditor(
    edit: FoodEdit,
    saving: Boolean,
    snackbar: SnackbarHostState,
    canDeleteFood: Boolean,
    canDeleteMeal: Boolean,
    onChange: (FoodEdit) -> Unit,
    onClose: () -> Unit,
    onSave: (FoodItem) -> Unit,
    onAskPip: () -> Unit,
    onDelete: () -> Unit,
) {
    val item = remember(edit.itemJson) { edit.item }
    var showDetails by rememberSaveable { mutableStateOf(false) }
    var confirmDelete by rememberSaveable { mutableStateOf(false) }
    // The screen owns back (and Escape), so an edited draft always asks before it is discarded.
    Dialog(onClose, DialogProperties(dismissOnBackPress = false, usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        CaptureDialog(
            title = "Edit food", closeTag = "cancelEditItem", saveTag = "saveItem",
            canSave = edit.edited() != null, saving = saving, dirty = edit.dirty,
            discardMessage = "The saved ingredient will keep its original values.",
            onClose = onClose, onSave = { edit.edited()?.let(onSave) }, snackbar = snackbar,
        ) {
            val enabled = !saving
            Text(edit.name.ifBlank { item.name }, Modifier.padding(horizontal = 4.dp, vertical = 4.dp).semantics { heading() },
                style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
            SectionTitle("Portion", Modifier.padding(top = 8.dp))
            FieldPair(
                { Field(edit.quantity, { onChange(edit.copy(quantity = it)) }, "Amount", "itemQuantity", it, enabled, Decimal) },
                { Field(edit.unit, { onChange(edit.copy(unit = it)) }, "Unit", "itemUnit", it, enabled, KeyboardOptions(imeAction = ImeAction.Next)) },
            )
            PortionChips(item.quantity, number(edit.quantity)) { onChange(edit.copy(quantity = it.plain())) }
            SectionTitle("This food", Modifier.padding(top = 16.dp))
            Preview(edit.preview())
            MoreDetailsToggle(showDetails) { showDetails = !showDetails }
            AnimatedVisibility(showDetails) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Field(edit.name, { onChange(edit.copy(name = it)) }, "Name", "itemName", Modifier.fillMaxWidth(), enabled,
                        KeyboardOptions(KeyboardCapitalization.Sentences, imeAction = ImeAction.Next))
                    Field(edit.kcal, { onChange(edit.nutrient("kcal", it)) }, "Energy (kcal)", "itemCalories", Modifier.fillMaxWidth(), enabled, Decimal,
                        hint = "Unknown".takeIf { edit.kcal.isEmpty() })
                    FieldPair(
                        { Field(edit.protein, { v -> onChange(edit.nutrient("protein", v)) }, "Protein (g)", "itemProtein", it, enabled, Decimal,
                            hint = "Unknown".takeIf { edit.protein.isEmpty() }) },
                        { Field(edit.carbs, { v -> onChange(edit.nutrient("carbs", v)) }, "Carbs (g)", "itemCarbs", it, enabled, Decimal,
                            hint = "Unknown".takeIf { edit.carbs.isEmpty() }) },
                    )
                    Field(edit.fat, { onChange(edit.nutrient("fat", it)) }, "Fat (g)", "itemFat", Modifier.fillMaxWidth(), enabled,
                        Decimal.copy(imeAction = ImeAction.Done), hint = "Unknown".takeIf { edit.fat.isEmpty() })
                    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
                    Column(Modifier.padding(horizontal = 4.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(item.sourceCaption, style = MaterialTheme.typography.bodyMedium, color = secondary)
                        if (item.reference.isNotEmpty()) Text(item.reference, style = MaterialTheme.typography.bodyMedium, color = secondary)
                        if (item.uncertain) Text("Portion or nutrients are uncertain", style = MaterialTheme.typography.bodyMedium, color = secondary)
                        Text("Leave unknown values blank. Changing only the amount scales the recorded nutrients. Changes update this meal only.",
                            style = MaterialTheme.typography.bodySmall, color = secondary)
                    }
                }
            }
            Column(Modifier.padding(top = 16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                FilledTonalButton(onAskPip, Modifier.fillMaxWidth().heightIn(min = 48.dp).testTag("askPipAboutFood")) {
                    Icon(painterResource(R.drawable.ic_auto_awesome), contentDescription = null, Modifier.size(18.dp))
                    Spacer(Modifier.size(8.dp))
                    Text("Ask Pip to fix this")
                }
                if (canDeleteFood || canDeleteMeal) {
                    val error = MaterialTheme.colorScheme.error
                    TextButton({ confirmDelete = true }, Modifier.fillMaxWidth().heightIn(min = 48.dp)
                        .testTag(if (canDeleteFood) "deleteFood" else "deleteMealFromFood"), enabled = enabled,
                        colors = ButtonDefaults.textButtonColors(contentColor = error)) {
                        Icon(painterResource(R.drawable.ic_delete), contentDescription = null, Modifier.size(18.dp))
                        Spacer(Modifier.size(8.dp))
                        Text(if (canDeleteFood) "Delete food" else "Delete meal")
                    }
                    if (!canDeleteFood) Text("This is the meal’s only food, so deleting it deletes the meal.", Modifier.padding(horizontal = 4.dp),
                        style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
        if (confirmDelete) {
            if (canDeleteFood) ConfirmDelete("Delete ${item.name}?", "Only this food is removed. The meal keeps its other foods.",
                "Delete food", "confirmDeleteFood", { confirmDelete = false; onDelete() }, { confirmDelete = false })
            else ConfirmDelete("Delete this meal?", "This removes the meal and its attached photos from this diary.",
                "Delete meal", "confirmDeleteMeal", { confirmDelete = false; onDelete() }, { confirmDelete = false })
        }
    }
}

/** Two fields across; one per row at large text so labels and values keep their width. */
@Composable
private fun FieldPair(first: @Composable (Modifier) -> Unit, second: @Composable (Modifier) -> Unit) {
    if (isLargeText()) { first(Modifier.fillMaxWidth()); second(Modifier.fillMaxWidth()) }
    else Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) { first(Modifier.weight(1f)); second(Modifier.weight(1f)) }
}

@Composable
private fun Field(
    value: String, onChange: (String) -> Unit, label: String, tag: String, modifier: Modifier, enabled: Boolean,
    keyboard: KeyboardOptions, hint: String? = null,
) = OutlinedTextField(
    value, onChange, modifier.testTag(tag), enabled = enabled, singleLine = true, label = { Text(label) },
    // iOS shows "Unknown" in a blank row; an outlined field hides its placeholder under the label until focused.
    supportingText = hint?.let { { Text(it) } },
    textStyle = MaterialTheme.typography.bodyLarge.tabular(), keyboardOptions = keyboard,
)

/** iOS portion chips: half, the original, one and a half and double the saved amount. */
@Composable
private fun PortionChips(original: Double, current: Double?, onPick: (Double) -> Unit) {
    val chips = listOf(Triple(0.5, "½×", "Half"), Triple(1.0, "1×", "Original"), Triple(1.5, "1½×", "One and a half"), Triple(2.0, "2×", "Double"))
    Row(Modifier.padding(vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        chips.forEach { (factor, title, spoken) ->
            val value = original * factor
            val selected = current == value
            Surface(
                { onPick(value) },
                Modifier.weight(1f).heightIn(min = 48.dp).testTag("foodScale" + if (factor == 0.5 || factor == 1.5) factor.toString() else factor.toInt().toString())
                    .semantics { contentDescription = "$spoken portion"; this.selected = selected },
                shape = CircleShape,
                color = if (selected) MaterialTheme.colorScheme.primary else MivuTheme.colors.summarySurface,
                contentColor = if (selected) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurface,
            ) {
                Row(horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
                    Text(title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                }
            }
        }
    }
}

@Composable
private fun Preview(result: FoodItem?) {
    Surface(Modifier.fillMaxWidth(), shape = MaterialTheme.shapes.extraLarge, color = MivuTheme.colors.summarySurface) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            KcalFigure(result?.nutrition?.kcal, "foodPreviewCalories")
            if (result != null) {
                val n = result.nutrition
                val chips = listOf(Triple("Protein", n.protein, MivuTheme.colors.protein), Triple("Carbs", n.carbs, MivuTheme.colors.carbs),
                    Triple("Fat", n.fat, MivuTheme.colors.fat))
                val large = isLargeText()
                if (large) Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    chips.forEach { (t, v, c) -> MacroChip(t, v?.let { "${it.fixed(1)} g" }, c, Modifier.fillMaxWidth(), inline = true) }
                } else Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    chips.forEach { (t, v, c) -> MacroChip(t, v?.let { "${it.fixed(1)} g" }, c, Modifier.weight(1f)) }
                }
            }
        }
    }
}

/** A large kcal figure read as one phrase ("380 kcal"); "—" while there is no valid value. */
@Composable
internal fun KcalFigure(kcal: Double?, tag: String, missing: String? = null) {
    val text = kcal?.fixed(0) ?: "—"
    Row(
        Modifier.testTag(tag).clearAndSetSemantics { contentDescription = if (kcal == null && missing != null) missing else "$text kcal" },
        verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Text(text, style = MaterialTheme.typography.displayMedium.tabular().copy(fontSize = 44.sp, lineHeight = 50.sp),
            fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.primary)
        Text("kcal", Modifier.padding(bottom = 8.dp), style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun MoreDetailsToggle(expanded: Boolean, onToggle: () -> Unit) {
    val angle by animateFloatAsState(if (expanded) 180f else 0f, label = "chevron")
    Surface(
        onToggle,
        Modifier.fillMaxWidth().padding(top = 8.dp).heightIn(min = 48.dp).testTag("foodMoreDetails")
            .semantics { stateDescription = if (expanded) "Expanded" else "Collapsed"; role = Role.Button },
        shape = MaterialTheme.shapes.large,
        color = MaterialTheme.colorScheme.surface,
    ) {
        Row(Modifier.padding(horizontal = 16.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("More details", Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium)
            Icon(painterResource(R.drawable.ic_arrow_drop_down), contentDescription = null, Modifier.rotate(angle))
        }
    }
}
