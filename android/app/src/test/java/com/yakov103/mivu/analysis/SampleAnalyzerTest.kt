package com.yakov103.mivu.analysis

import com.yakov103.mivu.diary.DiaryError
import com.yakov103.mivu.diary.FoodItem
import com.yakov103.mivu.diary.NutritionProvenance
import com.yakov103.mivu.diary.NutritionValues
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.fail
import org.junit.Test

class SampleAnalyzerTest {
    private val basis = NutritionValues(100.0, 20.0, 2.0, 1.0)
    private val item = FoodItem(UUID.randomUUID(), "Synthetic bowl", 1.0, "bowl", basis, NutritionProvenance.sample, "", true,
        emptyMap(), basis)

    private fun input(text: String = "", items: List<FoodItem> = emptyList(), language: String = "en") =
        AnalysisInput(1, UUID.randomUUID(), UUID.randomUUID(), UUID.randomUUID(), 0, text, items, language, "")

    @Test fun noItemsGivesSampleApple() {
        val out = SampleAnalyzer.analyze(input("synthetic"))
        val apple = out.items.single()
        val n = NutritionValues(95.0, 25.0, 0.5, 0.3)
        assertEquals("Apple (sample)", apple.name)
        assertEquals(n, apple.nutrition)
        assertEquals(n, apple.nutritionBasis)
        assertEquals(setOf("kcal", "carbs", "protein", "fat"), apple.nutrientSources.keys)
        assertEquals(setOf(NutritionProvenance.sample), apple.nutrientSources.values.toSet())
    }

    @Test fun halfNoteScales() {
        val out = SampleAnalyzer.analyze(input("Half of it", listOf(item))).items.single()
        assertEquals(0.5, out.quantity, 0.0)
        assertEquals(50.0, out.nutrition.kcal!!, 1e-9)
    }

    @Test fun numberSetsQuantity() {
        val out = SampleAnalyzer.analyze(input("about 3 bowls", listOf(item))).items.single()
        assertEquals(3.0, out.quantity, 0.0)
        assertEquals(300.0, out.nutrition.kcal!!, 1e-9)
        try { SampleAnalyzer.analyze(input("100001", listOf(item))); fail() } catch (_: DiaryError.InvalidData) {}
    }

    @Test fun hebrewHalfScales() {
        val out = SampleAnalyzer.analyze(input("חצי", listOf(item), "he")).items.single()
        assertEquals(0.5, out.quantity, 0.0)
    }

    @Test fun invalidLanguageRejected() {
        try { SampleAnalyzer.analyze(input(language = "fr")); fail() } catch (_: DiaryError.InvalidData) {}
    }
}
