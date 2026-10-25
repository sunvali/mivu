package com.yakov103.mivu.coach

import com.yakov103.mivu.diary.CoachTurn
import com.yakov103.mivu.diary.CoachTurnState
import java.time.Instant
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** Synthetic turns only; ports CoachReplyNotification.text(for:). */
class CoachReplyNotificationTest {
    private fun turn(state: CoachTurnState, reply: String? = null, meal: UUID? = null) = CoachTurn(UUID.randomUUID(), Instant.EPOCH,
        "Synthetic lunch", emptyList(), state, reply, emptyList(), "UTC", photoIDs = emptyList(), pendingMealID = meal)
    private val saved = "Coach" to "Your message is saved. Open Mivu for the Coach's reply."

    @Test fun capturedAndAnalyzingPostNothing() {
        assertNull(CoachReplyNotification.text(turn(CoachTurnState.captured)))
        assertNull(CoachReplyNotification.text(turn(CoachTurnState.analyzing)))
    }

    @Test fun mealTurnsLeaveItToTheMealNotification() {
        assertNull(CoachReplyNotification.text(turn(CoachTurnState.completed, "Logged.", meal = UUID.randomUUID())))
        assertNull(CoachReplyNotification.text(turn(CoachTurnState.needsRetry, meal = UUID.randomUUID())))
    }

    @Test fun completedReplyIsPlainAndCutAt180() {
        assertEquals("Coach" to "Logged your soup, about 460 kcal.",
            CoachReplyNotification.text(turn(CoachTurnState.completed, "  Logged your **soup**, about *460* kcal.\n")))
        val long = "a".repeat(200)
        assertEquals("Coach" to "a".repeat(179) + "…", CoachReplyNotification.text(turn(CoachTurnState.completed, long)))
        val exact = "b".repeat(180)
        assertEquals("Coach" to exact, CoachReplyNotification.text(turn(CoachTurnState.completed, exact)))
    }

    @Test fun emptyReplyPostsNothing() {
        assertNull(CoachReplyNotification.text(turn(CoachTurnState.completed, " \n ")))
        assertNull(CoachReplyNotification.text(turn(CoachTurnState.completed, null)))
    }

    @Test fun clarificationAsksForAnswer() {
        assertEquals("Coach" to "The Coach needs a quick answer.", CoachReplyNotification.text(turn(CoachTurnState.needsClarification)))
    }

    @Test fun waitingStatesSaySaved() {
        for (state in listOf(CoachTurnState.needsRetry, CoachTurnState.waitingForNetwork, CoachTurnState.waitingForConnection)) {
            assertEquals(saved, CoachReplyNotification.text(turn(state)))
        }
    }
}
