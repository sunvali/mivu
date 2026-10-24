package com.yakov103.mivu.coach

import com.yakov103.mivu.diary.NutritionValues
import com.yakov103.mivu.diary.SubmissionState
import com.yakov103.mivu.diary.blankLikeSwift
import java.math.BigDecimal
import java.math.RoundingMode

// Port of ios/Mivu/Coach/CoachReplyCheck.swift.

/**
 * Decides whether the model's prose may be shown: every number must come from this turn's facts.
 * Independent of the store and UI so a server worker can run the same check.
 */
object CoachReplyCheck {
    private val uuid = Regex("[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}")
    private val number = Regex("""-?\d{1,3}(?:,\d{3})+(?:\.\d+)?|-?\d+(?:\.\d+)?""")
    private val nutrients = listOf(NutritionValues::kcal, NutritionValues::carbs, NutritionValues::protein, NutritionValues::fat)

    fun allowedNumbers(sources: List<String>, receipts: List<CoachCommittedReceipt>): Set<BigDecimal> {
        // IDs are digit soup: their fragments would ground almost any number.
        val values = sources.flatMap { numbers(it.replace(uuid, "")) }.toMutableList()
        for (receipt in receipts) {
            for (item in receipt.items) {
                values += decimal(item.quantity)
                item.nutrition?.let { n -> values += nutrients.mapNotNull { it(n)?.let(::decimal) } }
            }
            for (nutrient in nutrients) {
                val parts = receipt.items.mapNotNull { it.nutrition?.let(nutrient) }
                if (parts.isNotEmpty()) values += decimal(parts.sum())
            }
            values += listOfNotNull(receipt.weightValue?.let(::decimal), receipt.workoutMinutes?.let { BigDecimal(it) })
        }
        // Sign is phrasing ("down 0.4 kg"), so compare magnitudes.
        return values.map { it.abs() }.flatMap { listOf(it, rounded(it, BigDecimal.ONE), rounded(it, BigDecimal.TEN)) }
            .map(::normalized).toSet()
    }

    fun numbers(text: String): List<BigDecimal> = number.findAll(text).mapNotNull { match ->
        var token = match.value.replace(",", "")
        // A hyphen joining date parts or a range is not a minus sign.
        if (token.startsWith("-") && match.range.first > 0 && text[match.range.first - 1].isDigit()) token = token.drop(1)
        token.toBigDecimalOrNull()
    }.toList()

    fun passes(prose: String, allowed: Set<BigDecimal>, receipts: List<CoachCommittedReceipt>): Boolean {
        if (prose.blankLikeSwift()) return false
        if (receipts.any { it.mealID != null && it.submissionState == SubmissionState.awaitingReview }) {
            val lowered = prose.lowercase()
            if ("logged" in lowered || "saved" in lowered) return false
        }
        return numbers(prose).all { normalized(it.abs()) in allowed }
    }

    // Like Swift's shortest description: 73.6 stays 73.6, without binary noise.
    private fun decimal(value: Double) = BigDecimal(value.toString())

    private fun rounded(value: BigDecimal, step: BigDecimal) = value.divide(step).setScale(0, RoundingMode.HALF_UP).multiply(step)

    // BigDecimal equality includes scale (1.0 != 1); Decimal's does not.
    private fun normalized(value: BigDecimal): BigDecimal = value.stripTrailingZeros().let { if (it.signum() == 0) BigDecimal.ZERO else it }
}
