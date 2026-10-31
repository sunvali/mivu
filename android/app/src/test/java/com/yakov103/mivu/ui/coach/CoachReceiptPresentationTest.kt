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
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
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

    @Test fun committedMacrosAddOnlyKnownValues() {
        val first = committed(item.copy(nutrition = NutritionValues(100.0, 0.0, 10.5, 2.0)))
        val second = committed(item.copy(id = UUID.randomUUID(), nutrition = NutritionValues(50.0, 0.0, 4.5, 3.0)))
        fun present(vararg items: CoachCommittedItem) = CoachReceiptPresentation(receipt(items.toList()), CoachReceiptTarget.Loading)
        val noProtein = second.copy(nutrition = second.nutrition!!.copy(protein = null))
        var p = present(first, noProtein)
        assertEquals("150 kcal", p.committedNutrition)
        assertEquals("Carbs 0 g · Protein 10.5 g · Fat 5 g", p.committedMacros)
        assertEquals("Some nutrients unknown", p.nutritionCompleteness)
        p = present(first.copy(nutrition = null), noProtein)
        assertEquals("50 kcal", p.committedNutrition)
        assertEquals("Carbs 0 g · Protein unknown · Fat 3 g", p.committedMacros)
        p = present(first.copy(nutrition = null), second.copy(nutrition = null))
        assertEquals("Energy unknown", p.committedNutrition)
        assertEquals("Carbs unknown · Protein unknown · Fat unknown", p.committedMacros)
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

    private fun removal(write: String, mealID: UUID? = null, weightID: UUID? = null, workoutID: UUID? = null) =
        CoachCommittedReceipt("$turnID/$write", turnID, mealID = mealID, weightID = weightID, workoutID = workoutID, committedRevision = 3)

    @Test fun removalsReadRemovedAndOnlyOfferUndo() {
        val meal = removal("delete_meal/${UUID.randomUUID()}", mealID = UUID.randomUUID())
        val weight = removal("delete_weight/${UUID.randomUUID()}", weightID = UUID.randomUUID())
        val workout = removal("delete_workout/${UUID.randomUUID()}", workoutID = UUID.randomUUID())
        for (receipt in listOf(meal, weight, workout)) {
            val p = CoachReceiptPresentation(receipt, CoachReceiptTarget.Unavailable)
            assertEquals("Removed", p.committedStatus)
            assertTrue(p.isRemoval)
            assertTrue(CoachReceiptPresentation.showsCard(receipt))
        }
        assertEquals("Photo removed", CoachReceiptPresentation(removal("delete_photo/a/b", mealID = UUID.randomUUID()), CoachReceiptTarget.Loading).committedStatus)
    }

    @Test fun anUndoOfARemovalIsNotLabelledRemoved() {
        val undone = removal("undo/$turnID/delete_meal/${UUID.randomUUID()}", mealID = UUID.randomUUID())
        assertFalse(CoachReceiptPresentation(undone, CoachReceiptTarget.Loading).isRemoval)
        assertEquals("Recorded operation", CoachReceiptPresentation(undone, CoachReceiptTarget.Loading).committedStatus)
        assertTrue(CoachReceiptPresentation.showsCard(removal("undo/$turnID/food/2026-10-24")))
    }

    @Test fun ordinaryReceiptsKeepTheirCardRule() {
        assertFalse(CoachReceiptPresentation.showsCard(removal("start_day")))
        assertTrue(CoachReceiptPresentation.showsCard(receipt()))
    }
}
