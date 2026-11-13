package com.yakov103.mivu.coach

import org.junit.Assert.assertTrue
import org.junit.Test

/** Google Play's AI-generated content policy: the Play declaration says Coach is told to decline restricted content. */
class CoachRestrictedContentTest {
    @Test fun rulesTellCoachToDeclineRestrictedContent() {
        val rules = CoachEngine.STABLE_RULES
        for (kind in listOf("sexual", "violent", "hateful", "self-harm")) assertTrue(kind, rules.contains(kind))
        assertTrue(rules.contains("decline"))
    }
}
