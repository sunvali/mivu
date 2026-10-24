package com.yakov103.mivu.ui.coach

import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.foundation.clickable
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.yakov103.mivu.R
import com.yakov103.mivu.coach.CoachCommittedReceipt
import com.yakov103.mivu.diary.CoachReceiptTarget
import com.yakov103.mivu.diary.CoachUndoState
import com.yakov103.mivu.ui.theme.MivuTheme
import com.yakov103.mivu.ui.today.isLargeText
import com.yakov103.mivu.ui.today.tabular

// Port of iOS CoachReceiptView (ios/Mivu/Coach/CoachReceiptView.swift:153-315) in the mockup's card layout.

/** A saved meal or workout: what the receipt committed, how the record stands now, Undo and Review / Edit. */
@Composable
fun CoachReceiptCard(
    receipt: CoachCommittedReceipt,
    target: CoachReceiptTarget,
    undo: CoachUndoState?,
    onUndo: () -> Unit,
    onOpen: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val presentation = CoachReceiptPresentation(receipt, target)
    val large = isLargeText()
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
    Surface(modifier.fillMaxWidth(), shape = RoundedCornerShape(20.dp), color = MaterialTheme.colorScheme.surface,
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant)) {
        Column(Modifier.padding(start = 16.dp, end = 16.dp, top = 14.dp, bottom = 6.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                if (undo != CoachUndoState.Undone) Icon(painterResource(R.drawable.ic_check_circle), null, Modifier.size(18.dp), tint = MivuTheme.colors.success)
                Text(if (undo == CoachUndoState.Undone) "Undone" else presentation.committedStatus, style = MaterialTheme.typography.labelLarge,
                    color = if (undo == CoachUndoState.Undone) secondary else MivuTheme.colors.success)
            }
            Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(title(receipt), Modifier.weight(1f).padding(bottom = 2.dp), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                presentation.committedNutrition?.let { energy ->
                    val kcal = energy.removeSuffix(" kcal")
                    Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                        Text(kcal, style = MaterialTheme.typography.headlineSmall.tabular(), fontWeight = FontWeight.SemiBold,
                            color = MaterialTheme.colorScheme.primary)
                        if (kcal != energy) Text("kcal", Modifier.padding(bottom = 3.dp), style = MaterialTheme.typography.bodySmall, color = secondary)
                    }
                }
            }
            presentation.committedMacros?.let { macros ->
                // "Carbs 62 g · Protein 14 g · Fat 13 g", each part in its Today colour.
                val colors = listOf(MivuTheme.colors.carbs, MivuTheme.colors.protein, MivuTheme.colors.fat)
                Row(Modifier.semantics(mergeDescendants = true) {}, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    macros.split(" · ").forEachIndexed { i, part ->
                        Text(part, style = MaterialTheme.typography.labelMedium.tabular(), fontWeight = FontWeight.Medium, color = colors[i])
                    }
                }
            }
            listOfNotNull(presentation.nutritionCompleteness, presentation.changeNotice, presentation.targetNotice).forEach {
                Text(it, style = MaterialTheme.typography.bodySmall, color = secondary)
            }
            if (presentation.itemRows.isNotEmpty()) Details(presentation)
            val review = @Composable {
                if (receipt.mealID != null || receipt.workoutID != null) FilledTonalButton(
                    onClick = onOpen,
                    // Android has no workout detail yet; a workout receipt shows the action without opening it.
                    enabled = target is CoachReceiptTarget.Meal,
                    modifier = Modifier.heightIn(min = 48.dp),
                    contentPadding = ButtonDefaults.ButtonWithIconContentPadding,
                ) {
                    Icon(painterResource(R.drawable.ic_edit), null, Modifier.size(ButtonDefaults.IconSize))
                    Spacer(Modifier.width(ButtonDefaults.IconSpacing))
                    Text("Review / Edit")
                }
            }
            val undoButton = @Composable {
                if (undo == CoachUndoState.Available) TextButton(onClick = onUndo, Modifier.heightIn(min = 48.dp),
                    contentPadding = ButtonDefaults.TextButtonWithIconContentPadding) {
                    Icon(painterResource(R.drawable.ic_undo), null, Modifier.size(ButtonDefaults.IconSize))
                    Spacer(Modifier.width(ButtonDefaults.IconSpacing))
                    Text("Undo")
                }
            }
            if (large) {
                Column(Modifier.padding(vertical = 4.dp)) { review(); undoButton() }
            } else {
                Row(Modifier.fillMaxWidth().padding(top = 2.dp), verticalAlignment = Alignment.CenterVertically) {
                    undoButton(); Spacer(Modifier.weight(1f)); review()
                }
            }
        }
    }
}

/** The receipt's foods, or "Meal" when it has none. */
private fun title(receipt: CoachCommittedReceipt) = receipt.items.take(3).joinToString(", ") { it.name }.ifEmpty { "Meal" }

/** iOS CoachReceiptDisclosureStyle: the whole row toggles each dish's amount and calories. */
@Composable
private fun Details(presentation: CoachReceiptPresentation) {
    var open by rememberSaveable(presentation.receipt.operationKey) { mutableStateOf(false) }
    Column(Modifier.animateContentSize()) {
        Row(
            Modifier.fillMaxWidth().heightIn(min = 48.dp)
                .clickable(role = Role.Button) { open = !open }
                .semantics { stateDescription = if (open) "Expanded" else "Collapsed" },
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(presentation.estimateLabel ?: "Nutrition details", Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
            Icon(painterResource(R.drawable.ic_arrow_drop_down), null, Modifier.rotate(if (open) 0f else -90f),
                tint = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        if (open) presentation.itemRows.forEach { row ->
            Row(
                Modifier.fillMaxWidth().padding(vertical = 2.dp).semantics(mergeDescendants = true) {
                    contentDescription = "${row.name}, ${row.amount}, ${if (row.kcal == "—") "calories unknown" else row.kcal + " calories"}"
                },
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(row.name, Modifier.weight(1f, fill = false), style = MaterialTheme.typography.bodyMedium)
                Text(row.amount, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.weight(1f))
                Text(row.kcal, style = MaterialTheme.typography.bodyMedium.tabular(), color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}
