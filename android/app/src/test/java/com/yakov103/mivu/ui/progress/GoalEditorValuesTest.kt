package com.yakov103.mivu.ui.progress

import com.yakov103.mivu.diary.GoalRecord
import com.yakov103.mivu.diary.NutritionValues
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class GoalEditorValuesTest {
    private val saved = GoalRecord(UUID.randomUUID(), "2026-10-01", "UTC", 3, NutritionValues(2100.0, 230.0, 120.5, null), 68.0, true)

    @Test fun blankFieldsAreNoTarget() {
        val values = GoalEditorValues.of(null, "2026-10-24").copy(kcal = "2100", protein = "  ")
        assertTrue(values.valid)
        val record = values.record("UTC")
        assertEquals(NutritionValues(2100.0, null, null, null), record.targets)
        assertNull(record.goalWeightKg)
        assertEquals("2026-10-24", record.effectiveLocalDate)
        assertFalse(record.exerciseCreditEnabled)
    }

    @Test fun negativeOrTextIsInvalid() {
        val blank = GoalEditorValues.of(null, "2026-10-24")
        listOf("-5", "0", "abc", "1.5f", "Infinity", "NaN", "1,2,3").forEach { assertFalse(it, blank.copy(kcal = it).valid) }
        assertFalse(blank.copy(weight = "-1").valid)
        assertNull(progressNumber("1e999"))
    }

    @Test fun commaDecimalIsAccepted() {
        assertEquals(72.5, progressNumber(" 72,5 ")!!, 0.0)
        val values = GoalEditorValues.of(null, "2026-10-24").copy(fat = "65,5")
        assertTrue(values.valid)
        assertEquals(65.5, values.record("UTC").targets.fat!!, 0.0)
    }

    @Test fun recordKeepsTheOriginalID() {
        val values = GoalEditorValues.of(saved, saved.effectiveLocalDate)
        assertEquals("2100", values.kcal)
        assertEquals("120.5", values.protein)
        assertEquals("", values.fat)
        assertEquals(3, values.expectedRevision)
        val record = values.copy(kcal = "1900").record("Europe/Paris")
        assertEquals(saved.id, record.id)
        assertEquals(1900.0, record.targets.kcal!!, 0.0)
        assertEquals("Europe/Paris", record.timeZoneID)
        assertTrue(record.exerciseCreditEnabled)
        assertNull(GoalEditorValues.of(null, "2026-10-24").expectedRevision)
    }

    @Test fun hasEditedTargetsIgnoresUntouchedFields() {
        val values = GoalEditorValues.of(saved, saved.effectiveLocalDate)
        assertFalse(values.hasEditedTargets)
        assertTrue(values.copy(fat = "60").hasEditedTargets)
        assertTrue(values.copy(exerciseCredit = false).hasEditedTargets)
        assertFalse(GoalEditorValues.of(null, "2026-10-24").hasEditedTargets)
    }
}
