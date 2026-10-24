package com.yakov103.mivu.ui.coach

import com.yakov103.mivu.coach.CoachCommittedItem
import com.yakov103.mivu.coach.CoachCommittedReceipt
import com.yakov103.mivu.diary.CoachReceiptTarget
import com.yakov103.mivu.diary.DiaryMeal
import com.yakov103.mivu.diary.FoodItem
import com.yakov103.mivu.diary.MealSubmission
import com.yakov103.mivu.diary.NutritionProvenance
import com.yakov103.mivu.diary.NutritionValues
import com.yakov103.mivu.diary.SubmissionState
import java.time.Instant
import java.util.Locale
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test

class CoachReceiptPresentationTest {
    private val turnID = UUID.randomUUID()
    private val item = FoodItem(UUID.randomUUID(), "Synthetic toast", 2.0, "slice", NutritionValues(160.0, 28.0, 6.0, 2.5),
        NutritionProvenance.estimate, "", true, emptyMap())

    @Before fun locale() = Locale.setDefault(Locale.US)

    private fun committed(item: FoodItem) = CoachCommittedItem(item.id, item.name, item.quantity, item.unit, item.nutrition, item.provenance, item.uncertain)
    private fun receipt(items: List<CoachCommittedItem> = listOf(committed(item))) = CoachCommittedReceipt("${turnID}/food/2026-10-24", turnID,
        mealID = UUID.randomUUID(), committedRevision = 3, targetLocalDate = "2026-10-24", items = items, submissionState = SubmissionState.saved)
    private fun meal(items: List<FoodItem>) = DiaryMeal(UUID.randomUUID(), UUID.randomUUID(), Instant.EPOCH, Instant.EPOCH, 2, null, null, items,
        emptyList(), listOf(MealSubmission(UUID.randomUUID(), 0, "", emptyList(), false, SubmissionState.saved)))

    @Test fun savedFoodHeaderAndMacros() {
        val p = CoachReceiptPresentation(receipt(), CoachReceiptTarget.Meal(meal(listOf(item)), "2026-10-24"))
        assertEquals("Saved food", p.committedStatus)
        assertEquals("160 kcal", p.committedNutrition)
        assertEquals("Carbs 28 g · Protein 6 g · Fat 2.5 g", p.committedMacros)
        assertEquals("Estimated nutrition", p.estimateLabel)
        assertEquals(listOf(CoachReceiptPresentation.ItemRow("Synthetic toast", "2 slice", "160")), p.itemRows)
        assertNull(p.nutritionCompleteness)
        assertNull(p.targetNotice)
        assertNull(p.changeNotice)
    }

    @Test fun unknownNutrientLabelled() {
        val partial = item.copy(nutrition = NutritionValues(kcal = 160.0))
        val p = CoachReceiptPresentation(receipt(listOf(committed(partial))), CoachReceiptTarget.Loading)
        assertEquals("Carbs unknown · Protein unknown · Fat unknown", p.committedMacros)
        assertEquals("Some nutrients unknown", p.nutritionCompleteness)
        assertEquals("Loading current record", p.targetNotice)
        assertEquals("Energy unknown", CoachReceiptPresentation(receipt(listOf(committed(item.copy(nutrition = NutritionValues())))),
            CoachReceiptTarget.Unavailable).committedNutrition)
    }

    @Test fun editedAndMovedNotice() {
        val moved = CoachReceiptPresentation(receipt(), CoachReceiptTarget.Meal(meal(listOf(item)), "2026-10-23"))
        assertEquals("Moved to Oct 23", moved.changeNotice)
        val edited = meal(listOf(item.copy(quantity = 3.0)))
        assertEquals("Edited · moved to Oct 23", CoachReceiptPresentation(receipt(), CoachReceiptTarget.Meal(edited, "2026-10-23")).changeNotice)
        assertEquals("Edited later", CoachReceiptPresentation(receipt(), CoachReceiptTarget.Meal(edited, "2026-10-24")).changeNotice)
    }

    @Test fun weightLabel() {
        val weight = CoachCommittedReceipt("${turnID}/weight/2026-10-24", turnID, weightID = UUID.randomUUID(), committedRevision = 3,
            weightValue = 71.5, weightUnit = "kg")
        assertEquals("Weight saved · 71.5 kg", CoachReceiptPresentation(weight, CoachReceiptTarget.Unavailable).weightLabel)
        assertEquals("Weight saved", CoachReceiptPresentation(weight.copy(weightValue = null), CoachReceiptTarget.Unavailable).weightLabel)
        assertNull(CoachReceiptPresentation(weight.copy(operationKey = "${turnID}/delete_weight/x"), CoachReceiptTarget.Unavailable).weightLabel)
        assertNull(CoachReceiptPresentation(receipt(), CoachReceiptTarget.Unavailable).weightLabel)
    }
}
