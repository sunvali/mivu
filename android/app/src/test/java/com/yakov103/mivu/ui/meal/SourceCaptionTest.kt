package com.yakov103.mivu.ui.meal

import com.yakov103.mivu.diary.FoodItem
import com.yakov103.mivu.diary.NutritionProvenance
import com.yakov103.mivu.diary.NutritionValues
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Test

class SourceCaptionTest {
    private fun caption(model: String) = FoodItem(UUID.randomUUID(), "Synthetic toast", 1.0, "slice", NutritionValues(80.0, 14.0, 3.0, 1.0),
        NutritionProvenance.estimate, "ref", false, emptyMap(), estimatedBy = model).sourceCaption

    @Test fun namesTheEstimatingModel() {
        assertEquals("Estimated nutrition · Gemini Nano", caption("gemini-nano"))
        assertEquals("Estimated nutrition · Apple Intelligence", caption("apple-intelligence")) // restored iOS archives
        assertEquals("Estimated nutrition · ChatGPT", caption("gpt-5"))
    }
}
