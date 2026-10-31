package com.yakov103.mivu.analysis

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class NutritionWordsTest {
    @Test fun wordsAreLowercasedSingularLetterRunsOfThreeOrMore() {
        assertEquals(setOf("egg", "and", "glass", "coke"), NutritionTable.words("2 Eggs and a glass of Coke"))
        assertTrue(NutritionTable.words("ok").isEmpty())
    }
}
