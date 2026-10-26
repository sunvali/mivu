package com.yakov103.mivu.ui.coach

import com.yakov103.mivu.coach.CoachReplyLines
import com.yakov103.mivu.diary.CoachTurnState
import java.util.Locale
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test

/** Port of ios/MivuTests/PipLineTests.swift, every expectation verbatim. */
class PipLineTest {
    private val previous = Locale.getDefault()
    @Before fun us() = Locale.setDefault(Locale.US)
    @After fun restore() = Locale.setDefault(previous)

    private fun line(hour: Int = 12, mealsLogged: Boolean = false, typing: Boolean = false, connected: Boolean = true,
                     processing: Boolean = false, withPhotos: Boolean = false, recovery: Boolean = false,
                     error: String? = null, turnState: CoachTurnState? = null) =
        PipLine.current(hour, mealsLogged, typing, connected, processing, withPhotos, recovery, error, turnState)

    @Test fun idleFollowsTheTimeOfDayUntilSomethingIsLogged() {
        assertEquals(PipLine.Say("Morning! What’s for breakfast?"), line(hour = 8))
        assertEquals(PipLine.Say("Ready for lunch?"), line(hour = 12))
        assertEquals(PipLine.Say("What’s for dinner?"), line(hour = 19))
        assertEquals(PipLine.Say("Anything to log?"), line(hour = 2))
        assertEquals(PipLine.Say("Anything else to log?"), line(hour = 8, mealsLogged = true))
    }

    @Test fun typingHidesOnlyTheIdleLine() {
        assertNull(line(typing = true))
        assertEquals(PipLine.Working("Counting that up…"), line(typing = true, processing = true))
        assertEquals(PipLine.Connect, line(typing = true, connected = false))
    }

    @Test fun workingNamesTheInput() {
        assertEquals(PipLine.Working("Looking at your photo…"), line(processing = true, withPhotos = true))
        assertEquals(PipLine.Working("Counting that up…"), line(processing = true))
    }

    @Test fun recoveryKeepsTheDetailAndOffersRetryOnlyWhenItApplies() {
        val detail = "Analysis could not finish. Your input is saved."
        assertEquals(PipLine.Problem("That one didn’t go through.", detail, canRetry = true),
            line(recovery = true, error = detail, turnState = CoachTurnState.needsRetry))
        assertEquals(PipLine.Problem("I’m offline. I’ll pick this up when you’re back.", null, canRetry = false),
            line(recovery = true, turnState = CoachTurnState.waitingForNetwork))
        assertEquals(PipLine.Problem("I need a bit more detail. My question is above.", null, canRetry = false),
            line(recovery = true, turnState = CoachTurnState.needsClarification))
        assertEquals(PipLine.Problem("Something went wrong.", detail, canRetry = false), line(recovery = true, error = detail))
        assertEquals(PipLine.Connect, line(recovery = true, turnState = CoachTurnState.waitingForConnection))
    }

    @Test fun chipNamesTheLoggingDayAndIntake() {
        val today = coachDayChip("2026-10-24", "2026-10-24", kcal = 1240.0, kcalPartial = false, mealsLogged = true, goal = 2000.0)
        assertEquals("Today · 1,240 / 2,000 kcal", today.text)
        assertEquals("Logging to today, 1,240 of 2,000 kcal", today.spoken)
        assertEquals("Yesterday · 1,240 kcal",
            coachDayChip("2026-10-23", "2026-10-24", kcal = 1240.0, kcalPartial = false, mealsLogged = true, goal = null).text)
        assertEquals("Other days use the device's date style", CoachReplyLines.dayLabel("2027-01-21", "2026-10-24") + " · 0 / 2,000 kcal",
            coachDayChip("2027-01-21", "2026-10-24", kcal = null, kcalPartial = false, mealsLogged = false, goal = 2000.0).text)
        assertEquals("Unknown intake stays visible instead of reading as zero", "Today · — / 2,000 kcal",
            coachDayChip("2026-10-24", "2026-10-24", kcal = null, kcalPartial = true, mealsLogged = true, goal = 2000.0).text)
    }

    @Test fun foodWithoutCaloriesMakesTheChipALowerBound() {
        val chip = coachDayChip("2026-10-24", "2026-10-24", kcal = 400.0, kcalPartial = true, mealsLogged = true, goal = 2000.0)
        assertEquals("Today · 400+ / 2,000 kcal", chip.text)
        assertEquals("Logging to today, at least 400 of 2,000 kcal", chip.spoken)
    }
}
