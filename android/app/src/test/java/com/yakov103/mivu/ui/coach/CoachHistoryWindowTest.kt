package com.yakov103.mivu.ui.coach

import com.yakov103.mivu.diary.CoachExchange
import com.yakov103.mivu.diary.CoachPage
import com.yakov103.mivu.diary.CoachTurn
import com.yakov103.mivu.diary.CoachTurnState
import com.yakov103.mivu.ui.coach.CoachHistoryWindow.Direction
import com.yakov103.mivu.ui.coach.CoachHistoryWindow.EdgeState
import java.time.Instant
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CoachHistoryWindowTest {
    private fun exchange(ordinal: Long) = CoachExchange(
        CoachTurn(UUID.randomUUID(), Instant.EPOCH, "Synthetic $ordinal", emptyList(), CoachTurnState.completed, null, emptyList(), "UTC",
            photoIDs = emptyList()),
        ordinal, emptyList(), emptyMap(), emptyMap(), emptyList(),
    )

    /** Rows [from, from + count) of a conversation whose ordinals run 0 until [total]. */
    private fun page(from: Long, count: Int = 20, total: Long = 1_000) =
        CoachPage((from until from + count).map(::exchange), hasEarlier = from > 0, hasLater = from + count < total)

    /** Resident rows plus [reserved] in-flight pages fit 100 exchanges in five page slots. */
    private fun CoachHistoryWindow.withinLimits(reserved: Int) =
        exchanges.size + reserved * CoachHistoryWindow.pageSize <= CoachHistoryWindow.maximumExchanges &&
            occupiedPageSlots <= CoachHistoryWindow.maximumPages

    /** A window holding the latest page plus [earlier] earlier pages, the newest row visible. */
    private fun filled(earlier: Int): CoachHistoryWindow {
        val window = CoachHistoryWindow()
        window.reset(page(980))
        repeat(earlier) {
            val visible = setOf(window.exchanges.last().turn.id)
            val reservation = window.reserve(Direction.earlier, visible)!!
            window.complete(reservation, page(window.exchanges.first().ordinal - 20))
        }
        return window
    }

    @Test fun neverExceedsHundredExchangesWithReservations() {
        val window = filled(0)
        repeat(12) {
            val visible = setOf(window.exchanges.first().turn.id)
            val reservation = window.reserve(Direction.earlier, visible) ?: return@repeat
            assertTrue(window.withinLimits(1))
            window.complete(reservation, page(window.exchanges.first().ordinal - 20))
            assertTrue(window.withinLimits(0))
        }
        assertEquals(CoachHistoryWindow.maximumExchanges, window.exchanges.size)
        assertEquals(CoachHistoryWindow.maximumPages, window.occupiedPageSlots)
    }

    @Test fun retiredReadKeepsSlotUntilExit() {
        val window = filled(3)
        val reservation = window.reserve(Direction.earlier, emptySet())!!
        assertEquals(5, window.occupiedPageSlots)
        window.retireAll()
        assertFalse(window.complete(reservation, page(window.exchanges.first().ordinal - 20)))
        assertEquals(5, window.occupiedPageSlots)
        // The retired read still holds its slot, so a full window cannot reserve without evicting first.
        assertEquals(EdgeState.Available, window.edgeState(Direction.earlier))
        window.exited(reservation.id)
        assertEquals(4, window.occupiedPageSlots)
    }

    @Test fun evictsOnlyInvisibleFarEdge() {
        val window = filled(4)
        val newest = window.exchanges.last().turn.id
        assertTrue(window.isLatest(newest))
        assertNull(window.reserve(Direction.earlier, setOf(newest)))
        assertEquals(100, window.exchanges.size)
        assertNotNull(window.reserve(Direction.earlier, setOf(window.exchanges.first().turn.id)))
        assertEquals(80, window.exchanges.size)
        assertFalse(window.isLatest(newest))
        assertEquals(EdgeState.Available, window.edgeState(Direction.later))
    }

    @Test fun exhaustedEdgeDoesNotReserve() {
        val window = CoachHistoryWindow()
        window.reset(page(0, 12, total = 12))
        assertNull(window.reserve(Direction.earlier, emptySet()))
        assertNull(window.reserve(Direction.later, emptySet()))
        assertEquals(EdgeState.Exhausted, window.edgeState(Direction.earlier))
        assertEquals(EdgeState.Exhausted, window.edgeState(Direction.later))
    }

    @Test fun failedEdgeRetries() {
        val window = filled(0)
        val first = window.reserve(Direction.earlier, emptySet())!!
        assertEquals(EdgeState.Loading, window.edgeState(Direction.earlier))
        window.fail(first, "Synthetic failure")
        assertEquals(EdgeState.Failed("Synthetic failure"), window.edgeState(Direction.earlier))
        val retry = window.reserve(Direction.earlier, emptySet())!!
        assertEquals(EdgeState.Loading, window.edgeState(Direction.earlier))
        assertTrue(window.complete(retry, page(960)))
        assertEquals(40, window.exchanges.size)
    }

    @Test fun isLatestOnlyForTrueNewest() {
        val window = CoachHistoryWindow()
        window.reset(page(500))
        assertFalse(window.isLatest(window.exchanges.last().turn.id))
        window.reset(page(980))
        assertTrue(window.isLatest(window.exchanges.last().turn.id))
        assertFalse(window.isLatest(window.exchanges.first().turn.id))
    }
}
