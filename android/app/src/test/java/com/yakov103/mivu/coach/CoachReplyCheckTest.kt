package com.yakov103.mivu.coach

import com.yakov103.mivu.diary.NutritionValues
import com.yakov103.mivu.diary.SubmissionState
import java.util.UUID
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Synthetic facts only; ports CoachReplyCheck.swift. */
class CoachReplyCheckTest {
    private val turnID = UUID.randomUUID()
    private fun receipt(kcal: Double, state: SubmissionState = SubmissionState.saved) = CoachCommittedReceipt(
        "$turnID/food/2026-10-24", turnID, mealID = UUID.randomUUID(), committedRevision = 1, submissionState = state,
        items = listOf(CoachCommittedItem(UUID.randomUUID(), "Synthetic soup", 1.0, "bowl", NutritionValues(kcal = kcal)),
            CoachCommittedItem(UUID.randomUUID(), "Synthetic bread", 2.0, "slice", NutritionValues(kcal = 120.0))))

    @Test fun replyCheckRejectsUngroundedNumbers() {
        val receipts = listOf(receipt(335.0))
        val id = "12345678-1234-4123-8123-123456789012"
        val allowed = CoachReplyCheck.allowedNumbers(listOf("""{"daily":{"kcal":1,234.5},"id":"$id"}""", "target 2000"), receipts)
        assertFalse(CoachReplyCheck.passes("That meal is about **470** kcal.", allowed, receipts))
        assertFalse(CoachReplyCheck.passes("You have 812 kcal left.", allowed, receipts))
        // Fragments of an ID never ground a number.
        assertFalse(CoachReplyCheck.passes("About 12345678 kcal, 4123 g.", allowed, receipts))
        assertFalse(CoachReplyCheck.passes("  ", allowed, receipts))
        // A review-first estimate may not be described as saved.
        val review = listOf(receipt(335.0, SubmissionState.awaitingReview))
        assertFalse(CoachReplyCheck.passes("I saved your soup.", CoachReplyCheck.allowedNumbers(emptyList(), review), review))
    }

    @Test fun groundedReplyPasses() {
        val receipts = listOf(receipt(335.0))
        val allowed = CoachReplyCheck.allowedNumbers(listOf("Today 1,234.5 of 2000 kcal, down -0.4 kg on 2026-10-24"), receipts)
        // Meal total 455 rounds to 460; item and source values, their rounding and sign-free magnitudes are allowed.
        assertTrue(CoachReplyCheck.passes("That meal is about **460** kcal; you are at 1,235 of 2,000 kcal.", allowed, receipts))
        assertTrue(CoachReplyCheck.passes("Down 0.4 kg, 2 slices of bread, 335 kcal soup on 2026-10-24.", allowed, receipts))
        assertTrue(CoachReplyCheck.passes("Nice work today.", allowed, receipts))
    }
}
