package com.yakov103.mivu.ui.manual

import com.yakov103.mivu.diary.DiaryError
import com.yakov103.mivu.diary.NutritionProvenance
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test

class ManualNutritionDraftTest {
    private val id = UUID.randomUUID()

    @Test fun commaDecimal() {
        val item = ManualNutritionDraft(name = " Oat porridge ", quantity = "1,5", kcal = "240,5").item(id)
        assertEquals(1.5, item.quantity, 0.0)
        assertEquals(240.5, item.nutrition.kcal!!, 0.0)
        assertEquals("Oat porridge", item.name)
        assertEquals(id, item.id)
    }

    @Test fun zeroAmountRejected() {
        val draft = ManualNutritionDraft(name = "Oats", quantity = "0", kcal = "240")
        assertThrows(DiaryError.InvalidData::class.java) { draft.item(id) }
        assertEquals("Enter an amount greater than 0.", draft.amountError)
    }

    @Test fun noNutrientRejected() {
        assertThrows(DiaryError.InvalidData::class.java) { ManualNutritionDraft(name = "Oats").item(id) }
    }

    @Test fun blankMeansUnknownZeroMeansZero() {
        val item = ManualNutritionDraft(name = "Water", kcal = "0").item(id)
        assertEquals(0.0, item.nutrition.kcal!!, 0.0)
        assertNull(item.nutrition.protein)
        assertNull(item.nutrition.carbs)
        assertNull(item.nutrition.fat)
        // A space is not blank (iOS `isEmpty`): it is an invalid number, not unknown.
        assertThrows(DiaryError.InvalidData::class.java) { ManualNutritionDraft(name = "Water", kcal = "0", fat = " ").item(id) }
        assertThrows(DiaryError.InvalidData::class.java) { ManualNutritionDraft(name = "Water", kcal = "10000001").item(id) }
        assertThrows(DiaryError.InvalidData::class.java) { ManualNutritionDraft(name = "Water", kcal = "1d").item(id) }
    }

    @Test fun sourcesOnlyForFilled() {
        val item = ManualNutritionDraft(name = "Toast", kcal = "120", fat = "3").item(id)
        assertEquals(mapOf("kcal" to NutritionProvenance.user, "fat" to NutritionProvenance.user), item.nutrientSources)
        assertEquals(NutritionProvenance.user, item.provenance)
        assertEquals("Entered manually", item.reference)
        assertEquals("serving", item.unit)
        assertEquals(1.0, item.quantity, 0.0)
    }
}
