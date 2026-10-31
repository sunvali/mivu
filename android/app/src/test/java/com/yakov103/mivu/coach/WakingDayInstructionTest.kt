package com.yakov103.mivu.coach

import com.yakov103.mivu.diary.DayCutoff
import java.time.Instant
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class WakingDayInstructionTest {
    private val zone = "America/New_York" // UTC-4 in October

    @After fun reset() { DayCutoff.hour = 4 }

    @Test fun earlyMorningWindowFollowsTheCutoff() {
        DayCutoff.hour = 6 // the default comes from the per-device cutoff
        val inside = CoachEngine.wakingDayInstruction(Instant.parse("2026-10-24T11:00:00Z"), zone) // 07:00
        assertTrue(inside, inside.startsWith("This was captured early in the morning"))
        assertTrue(inside, inside.contains("(2026-10-23)") && inside.endsWith("belongs to 2026-10-24."))
        val outside = CoachEngine.wakingDayInstruction(Instant.parse("2026-10-24T09:30:00Z"), zone) // 05:30
        assertEquals("The current waking day is 2026-10-23; log new intake to it unless the person names another day.", outside)
    }
}
