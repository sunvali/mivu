package com.yakov103.mivu.ui.coach

import android.text.format.DateFormat
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.foundation.BorderStroke
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.yakov103.mivu.diary.CoachClarification
import com.yakov103.mivu.diary.CoachQuestion
import com.yakov103.mivu.diary.CoachReply
import com.yakov103.mivu.diary.DiaryMeal
import com.yakov103.mivu.diary.MealTimePrecision
import com.yakov103.mivu.ui.theme.MivuTheme
import java.util.Date
import java.util.UUID

// Port of iOS CoachQuestionChips (ios/Mivu/Coach/CoachQuestionChips.swift).

/** One-tap answers to a Coach question: the candidate records, or Remove/Keep for a whole-meal delete. */
@Composable
fun CoachQuestionChips(
    question: CoachQuestion,
    meals: List<DiaryMeal>,
    enabled: Boolean,
    loadPhoto: suspend (mealID: UUID, photoID: UUID) -> ByteArray?,
    /** The target, the message sent, and the quote shown above it. */
    onPick: (CoachReply.Target, String, String) -> Unit,
) {
    val first = question.candidates.firstOrNull() ?: return
    if (question.kind == CoachClarification.confirm) {
        val meal = mealID(first)?.let { id -> meals.firstOrNull { it.id == id } }?.let { name(it, CoachReply.Target.Meal(it.id)) } ?: "Meal"
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            OutlinedButton({ onPick(first, "Remove it", meal) }, Modifier.weight(1f).heightIn(min = 48.dp), enabled,
                colors = ButtonDefaults.outlinedButtonColors(contentColor = MaterialTheme.colorScheme.error),
                border = BorderStroke(1.dp, MaterialTheme.colorScheme.error)) { Text("Remove") }
            OutlinedButton({ onPick(first, "Keep it", meal) }, Modifier.weight(1f).heightIn(min = 48.dp), enabled) { Text("Keep") }
        }
        return
    }
    val context = LocalContext.current
    fun time(meal: DiaryMeal) = if (meal.timePrecision == MealTimePrecision.dateOnly) "Time unspecified"
        else DateFormat.getTimeFormat(context).format(Date(meal.eatenAt.toEpochMilli()))
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        question.candidates.forEach { target ->
            val meal = mealID(target)?.let { id -> meals.firstOrNull { it.id == id } } ?: return@forEach
            val title = name(meal, target)
            Surface(
                Modifier.fillMaxWidth().heightIn(min = 48.dp).testTag("coachQuestionChip")
                    .clickable(enabled, role = Role.Button) { onPick(target, title, title) }
                    .clearAndSetSemantics { contentDescription = "$title, ${time(meal)}"; role = Role.Button },
                shape = RoundedCornerShape(14.dp), color = MivuTheme.colors.summarySurface,
            ) {
                Row(Modifier.padding(8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    meal.photos.firstOrNull().let { photo ->
                        CoachPhoto(photo?.id, 44.dp) { photo?.let { loadPhoto(meal.id, it.id) } }
                    }
                    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(title, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold)
                        Text(time(meal), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
    }
}

private fun mealID(target: CoachReply.Target) = when (target) {
    is CoachReply.Target.Meal -> target.mealID
    is CoachReply.Target.Item -> target.mealID
    else -> null
}

private fun name(meal: DiaryMeal, target: CoachReply.Target): String {
    if (target is CoachReply.Target.Item) meal.items.firstOrNull { it.id == target.itemID }?.let { return it.name }
    return meal.items.take(3).joinToString(", ") { it.name }.ifEmpty { "Meal" }
}
