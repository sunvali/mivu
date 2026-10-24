package com.yakov103.mivu.analysis

import com.yakov103.mivu.diary.AnalysisOutput
import com.yakov103.mivu.diary.DiaryDatabase
import com.yakov103.mivu.diary.DiaryError
import com.yakov103.mivu.diary.FoodItem
import com.yakov103.mivu.diary.NutritionProvenance
import com.yakov103.mivu.diary.NutritionValues
import com.yakov103.mivu.diary.atMost
import com.yakov103.mivu.diary.validateItems
import java.util.UUID

/** Port of the fields of iOS `AnalysisInput` that [SampleAnalyzer] reads (photos are not needed). */
data class AnalysisInput(
    val schemaVersion: Int,
    val profileID: UUID,
    val mealID: UUID,
    val submissionID: UUID,
    val baseRevision: Int,
    val text: String,
    val currentItems: List<FoodItem>,
    val language: String,
    val preferences: String,
)

/** iOS `analysisInput`: the submission's text, the meal's items and the profile's language and preferences. */
fun DiaryDatabase.analysisInput(mealID: UUID, submissionID: UUID): AnalysisInput = read { tx ->
    val meal = tx.meal(mealID) ?: throw DiaryError.NotFound
    val sub = meal.submissions.firstOrNull { it.id == submissionID } ?: throw DiaryError.NotFound
    if (sub.state == com.yakov103.mivu.diary.SubmissionState.cancelled) throw DiaryError.NotFound
    if (sub.baseRevision != meal.revision) throw DiaryError.StaleRevision
    val p = tx.head.profile
    AnalysisInput(1, p.id, mealID, submissionID, sub.baseRevision, sub.text, meal.items, p.language, p.preferences)
}

private fun NutritionValues.scaled(f: Double) = NutritionValues(kcal?.times(f), carbs?.times(f), protein?.times(f), fat?.times(f))

private fun FoodItem.scale(f: Double) = copy(quantity = quantity * f, nutrition = nutrition.scaled(f))

/** Port of ios/Mivu/Diary/SampleAnalyzer.swift: a deterministic fixture, never food recognition or a dietary claim. */
object SampleAnalyzer {
    fun analyze(input: AnalysisInput): AnalysisOutput {
        fun invalid(): Nothing = throw DiaryError.InvalidData("analysis input")
        if (input.schemaVersion != 1 || input.baseRevision < 0 || !input.text.atMost(20_000) ||
            input.language !in setOf("en", "he") || !input.preferences.atMost(10_000)) invalid()
        validateItems(input.currentItems)
        var items = input.currentItems
        if (items.isEmpty()) {
            val n = NutritionValues(95.0, 25.0, 0.5, 0.3)
            items = listOf(FoodItem(UUID.randomUUID(), "Apple (sample)", 1.0, "medium", n, NutritionProvenance.sample,
                "Synthetic medium apple", true, listOf("kcal", "carbs", "protein", "fat").associateWith { NutritionProvenance.sample }, n))
        } else {
            val text = input.text.lowercase()
            val number = text.split(Regex("[^0-9.]")).firstNotNullOfOrNull { it.toDoubleOrNull() }
            if ("half" in text || "חצי" in text) items = items.map { it.scale(0.5) }
            else if (number != null) {
                if (!number.isFinite() || number < 0 || number > 100_000) invalid()
                val first = items[0]
                items = listOf(first.nutritionBasis?.let { first.copy(quantity = number, nutrition = it.scaled(number)) }
                    ?: run { if (first.quantity <= 0) invalid(); first.scale(number / first.quantity) }) + items.drop(1)
            }
        }
        validateItems(items)
        return AnalysisOutput(1, input.profileID, input.mealID, input.submissionID, input.baseRevision, items)
    }
}
