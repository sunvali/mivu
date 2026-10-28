package com.yakov103.mivu.analysis

import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

// Ports ios/MivuTests/NutritionTableTests.swift.
class NutritionTableTest {
    private val table = NutritionTable.bundled(ApplicationProvider.getApplicationContext())

    @Test fun searchPutsPlainFoodsBeforeDishesThatMentionThem() {
        assertEquals("Apple, raw", table.search("apple").first().description)
        assertTrue(table.search("diet cola").map { it.description }.contains("Soft drink, cola, diet"))
        assertEquals("Big Mac (McDonalds)", table.search("big mac").first().description)
        assertTrue(table.search("pepperoni pizza").all { it.description.lowercase().contains("pepperoni") })
        assertTrue(table.search("").isEmpty() && table.search("\"*)").isEmpty())
    }

    @Test fun portionsResolveUnitsAndSynonymsButNoDefaultServing() {
        val apple = table.search("apple").first()
        assertEquals(200.0, table.portionGrams(apple.code, "medium")!!, 0.0)
        assertNull("No default serving: the caller keeps the model estimate", table.portionGrams(apple.code, "piece"))
        val cola = table.search("diet cola").first { it.description == "Soft drink, cola, diet" }
        assertEquals(360.0, table.portionGrams(cola.code, "can")!!, 0.0)
        val pizza = table.search("pepperoni pizza", limit = 30).first { it.description == "Pizza with pepperoni, stuffed crust" }
        assertEquals("A slice resolves to the general 1 piece, NFS portion", 164.0, table.portionGrams(pizza.code, "slice")!!, 0.0)
        assertEquals(61.0, apple.kcal, 0.0)
    }

    @Test fun sliceSearchGivesAFoodWithAPortion() {
        val grams = table.search("pizza", limit = 30).firstNotNullOfOrNull { table.portionGrams(it.code, "slice") }
        assertTrue(grams != null && grams > 0)
    }
}
