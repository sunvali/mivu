package com.yakov103.mivu.ui.coach

import com.yakov103.mivu.coach.CoachCommittedReceipt
import com.yakov103.mivu.coach.CoachReplyLines
import com.yakov103.mivu.diary.CoachReceiptTarget
import com.yakov103.mivu.diary.DiaryMeal
import com.yakov103.mivu.diary.NutritionProvenance
import com.yakov103.mivu.diary.NutritionValues
import com.yakov103.mivu.diary.SubmissionState
import java.math.BigDecimal
import java.math.RoundingMode
import java.text.DecimalFormat
import java.text.DecimalFormatSymbols
import java.util.Locale

// Pure port of the iOS CoachReceiptPresentation struct (ios/Mivu/Coach/CoachReceiptView.swift:13-152): what the committed
// receipt recorded, and how the record it points at stands now.

data class CoachReceiptPresentation(val receipt: CoachCommittedReceipt, val target: CoachReceiptTarget) {
    data class ItemRow(val name: String, val amount: String, val kcal: String)

    val committedStatus: String get() = when (receipt.submissionState) {
        SubmissionState.saved -> "Saved food"
        SubmissionState.awaitingReview -> "Estimate awaiting review"
        else -> "Recorded operation"
    }

    val committedNutrition: String? get() = if (receipt.items.isEmpty()) null else committedTotal { it.kcal }?.let(::energy) ?: "Energy unknown"

    val committedMacros: String? get() =
        if (receipt.items.isEmpty()) null else macros(committedTotal { it.carbs }, committedTotal { it.protein }, committedTotal { it.fat })

    val nutritionCompleteness: String? get() = if (receipt.items.isEmpty()) null else
        "Some nutrients unknown".takeIf { receipt.items.any { i -> i.nutrition.let { it == null || listOf(it.kcal, it.carbs, it.protein, it.fat).contains(null) } } }

    val estimateLabel: String? get() = when {
        receipt.items.isEmpty() -> null
        receipt.items.any { it.uncertain == true || it.provenance == NutritionProvenance.estimate } -> "Estimated nutrition"
        receipt.items.any { it.provenance == null } -> "Nutrition provenance unknown"
        else -> null
    }

    private val currentStatus: String get() = when (target) {
        CoachReceiptTarget.Loading -> "Loading current record"
        CoachReceiptTarget.Unavailable -> "Record unavailable"
        CoachReceiptTarget.Failed -> "Could not load current record"
        is CoachReceiptTarget.Meal -> when (target.meal.state) {
            SubmissionState.awaitingReview -> "Needs review"
            SubmissionState.needsRetry -> "Analysis needs retry"
            else -> if (target.meal.revision > 0) "Current saved meal" else "Captured on this device"
        }
        is CoachReceiptTarget.Workout -> "Current workout"
    }

    private val currentDate: String? get() = when (target) {
        is CoachReceiptTarget.Meal -> target.localDate
        is CoachReceiptTarget.Workout -> target.localDate
        else -> null
    }

    val targetNotice: String? get() = when (target) {
        CoachReceiptTarget.Loading, CoachReceiptTarget.Unavailable, CoachReceiptTarget.Failed -> currentStatus
        is CoachReceiptTarget.Meal -> {
            val state = target.meal.state
            when {
                state == SubmissionState.awaitingReview && receipt.submissionState == SubmissionState.awaitingReview -> null
                state == SubmissionState.needsRetry || target.meal.revision <= 0 -> currentStatus
                state == SubmissionState.awaitingReview -> currentStatus
                else -> null
            }
        }
        is CoachReceiptTarget.Workout -> null
    }

    val changeNotice: String? get() {
        val moved = receipt.targetLocalDate != null && currentDate != null && receipt.targetLocalDate != currentDate
        var edited = false
        var stateChanged = false
        if (target is CoachReceiptTarget.Meal) {
            val meal = target.meal
            stateChanged = receipt.submissionState?.let { it != meal.state } ?: false
            if (receipt.items.isNotEmpty()) {
                val current = if (meal.state == SubmissionState.awaitingReview) meal.submissions.lastOrNull()?.proposal?.items ?: meal.items else meal.items
                edited = receipt.itemID == null && receipt.items.size != current.size
                edited = edited || receipt.items.any { original ->
                    val item = current.firstOrNull { it.id == original.itemID } ?: return@any true
                    original.name != item.name || original.quantity != item.quantity || original.unit != item.unit ||
                        original.nutrition?.let { it != item.nutrition } == true || original.provenance?.let { it != item.provenance } == true ||
                        original.uncertain?.let { it != item.uncertain } == true
                }
            }
        }
        if (moved) return (if (edited) "Edited · moved to " else "Moved to ") + CoachReplyLines.shortDate(currentDate!!)
        if (edited) return "Edited later"
        return if (stateChanged) "Status changed later" else null
    }

    val itemRows: List<ItemRow> get() = receipt.items.map {
        ItemRow(it.name, "${plain(it.quantity)} ${it.unit}", it.nutrition?.kcal?.let(::whole) ?: "—")
    }

    val weightLabel: String? get() {
        if (receipt.weightID == null || "/delete_weight/" in receipt.operationKey) return null
        val value = receipt.weightValue ?: return "Weight saved"
        val unit = receipt.weightUnit ?: return "Weight saved"
        return "Weight saved · ${plain(value)} $unit"
    }

    private fun committedTotal(nutrient: (NutritionValues) -> Double?): Double? {
        var total = 0.0
        for (item in receipt.items) total += item.nutrition?.let(nutrient) ?: return null
        return total
    }

    private companion object {
        val us = DecimalFormatSymbols(Locale.US)
        fun whole(value: Double): String = DecimalFormat("#,##0", us).apply { roundingMode = RoundingMode.HALF_EVEN }.format(value)
        fun energy(value: Double) = whole(value) + " kcal"
        /** Swift `.number.grouping(.never)`: every significant digit, no grouping. */
        fun plain(value: Double): String = BigDecimal(value.toString()).stripTrailingZeros().toPlainString()
        fun macros(carbs: Double?, protein: Double?, fat: Double?): String {
            fun grams(value: Double?) = value?.let { CoachReplyLines.number(it) + " g" } ?: "unknown"
            return "Carbs ${grams(carbs)} · Protein ${grams(protein)} · Fat ${grams(fat)}"
        }
    }
}

/** iOS `MealReadModel.state`: the latest submission's state, or saved when the meal has none. */
private val DiaryMeal.state get() = submissions.lastOrNull()?.state ?: SubmissionState.saved
