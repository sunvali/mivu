package com.yakov103.mivu.ui.meal

import com.yakov103.mivu.diary.FoodItem
import com.yakov103.mivu.diary.NutritionProvenance
import com.yakov103.mivu.diary.NutritionValues
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Test

class FoodEditTest {
    private val original = FoodItem(UUID.randomUUID(), "Greek yogurt", 200.0, "g", NutritionValues(190.0, 10.0, 18.0, 5.0),
        NutritionProvenance.user, "Entered manually", false, emptyMap())

    @Test fun rebasedKeepsTypedFieldsAndFollowsTheReloadedFood() {
        val typed = FoodEdit.start(original, 1, null).copy(quantity = "400").nutrient("protein", "30")
        val reloaded = original.copy(name = "Skyr", quantity = 100.0, nutrition = NutritionValues(95.0, 5.0, 9.0, 2.5))

        val rebased = typed.rebased(reloaded, 2)

        assertEquals(2, rebased.revision)
        assertEquals(reloaded, rebased.item)
        assertEquals("Skyr", rebased.name) // untouched: follows the reload
        assertEquals("400", rebased.quantity) // typed: kept
        assertEquals("30", rebased.protein) // explicit: kept and still explicit
        assertEquals(setOf("protein"), rebased.explicitNutrients)
        assertEquals("95", rebased.kcal) // not typed: the reloaded value, as the store requires
        assertEquals(380.0, rebased.preview()!!.nutrition.kcal!!, 0.001)
    }
}
