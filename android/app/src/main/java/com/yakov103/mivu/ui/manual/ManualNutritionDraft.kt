package com.yakov103.mivu.ui.manual

import com.yakov103.mivu.diary.DiaryError
import com.yakov103.mivu.diary.FoodItem
import com.yakov103.mivu.diary.NutritionProvenance
import com.yakov103.mivu.diary.NutritionValues
import com.yakov103.mivu.diary.validateItems
import java.util.UUID

/** The text a person typed, as iOS `ManualNutritionDraft`. Serializable so `SavedStateHandle` keeps it through process death. */
data class ManualNutritionDraft(
    val name: String = "",
    val quantity: String = "1",
    val unit: String = "serving",
    val kcal: String = "",
    val carbs: String = "",
    val protein: String = "",
    val fat: String = "",
) : java.io.Serializable {
    val isDirty get() = this != ManualNutritionDraft()

    val amountError get() = if (number(quantity)?.let { it > 0 } == true) null else "Enter an amount greater than 0."

    /** Blank is unknown; anything else must be a number from 0 to 10,000,000. */
    fun nutrientError(text: String) =
        if (text.isEmpty() || number(text)?.let { it.isFinite() && it in 0.0..10_000_000.0 } == true) null
        else "Enter a number from 0 to 10,000,000."

    /** iOS `item()`: throws `InvalidData` unless the amount is above 0, at least one nutrient is filled and every filled one is valid. */
    fun item(id: UUID): FoodItem {
        val strings = listOf(kcal, carbs, protein, fat)
        val amount = number(quantity)
        if (amountError != null || amount == null || strings.any { nutrientError(it) != null } || strings.all { it.isEmpty() }) {
            throw DiaryError.InvalidData("manual draft")
        }
        val values = strings.map(::number)
        val sources = listOf("kcal", "carbs", "protein", "fat").zip(values)
            .filter { it.second != null }.associate { it.first to NutritionProvenance.user }
        val item = FoodItem(id, name.trim(), amount, unit.trim(), NutritionValues(values[0], values[1], values[2], values[3]),
            NutritionProvenance.user, "Entered manually", false, sources)
        validateItems(listOf(item))
        return item
    }

    internal companion object {
        // Swift `Double(String)` grammar; Kotlin's own parser also takes "1d", "1f" and hex.
        private val decimal = Regex("[+-]?(\\d+\\.?\\d*|\\.\\d+)([eE][+-]?\\d+)?")

        fun number(text: String): Double? = text.trim().replace(',', '.').takeIf(decimal::matches)?.toDouble()
    }
}
