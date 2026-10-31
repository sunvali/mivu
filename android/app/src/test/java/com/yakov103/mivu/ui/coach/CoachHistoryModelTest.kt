package com.yakov103.mivu.ui.coach

import com.yakov103.mivu.diary.CoachDayCursor
import com.yakov103.mivu.diary.CoachDayPage
import com.yakov103.mivu.diary.CoachSegmentSummary
import java.io.IOException
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Test

/** iOS CoachHistoryModel semantics against a fake load: late results drop, paging waits for the running load. */
class CoachHistoryModelTest {
    private fun page(preview: String, hasMore: Boolean = false): CoachDayPage {
        val id = UUID.randomUUID()
        val row = CoachSegmentSummary(id, null, "2026-10-24", "UTC", UUID.randomUUID(), Instant.EPOCH, 1, 1, preview)
        return CoachDayPage(listOf(row), CoachDayCursor(1, id, null), hasMore)
    }

    private class Calls {
        val requests = mutableListOf<Pair<String?, CoachDayCursor?>>()
        val answers = mutableListOf<CompletableDeferred<CoachDayPage>>()
        val load: suspend (String?, CoachDayCursor?) -> CoachDayPage = { date, before ->
            requests += date to before
            CompletableDeferred<CoachDayPage>().also { answers += it }.await()
        }
    }

    @Test fun lateResultAfterShowDateIsDropped() = runTest {
        val calls = Calls()
        val model = CoachHistoryModel(calls.load)
        launch { model.show() }
        runCurrent()
        launch { model.show("2026-10-23") }
        runCurrent()
        calls.answers[1].complete(page("dated"))
        runCurrent()
        calls.answers[0].complete(page("all, late"))
        runCurrent()
        assertEquals("2026-10-23", model.state.value.dateFilter)
        assertEquals("dated", model.state.value.page!!.segments.single().preview)
        assertFalse(model.state.value.isLoading)
    }

    @Test fun earlierIgnoredWhileLoading() = runTest {
        val calls = Calls()
        val model = CoachHistoryModel(calls.load)
        launch { model.show() }
        runCurrent()
        calls.answers[0].complete(page("first", hasMore = true))
        runCurrent()
        launch { model.earlier() }
        runCurrent()
        launch { model.earlier() } // the first page read is still running
        runCurrent()
        assertEquals(2, calls.requests.size)
        assertEquals(model.state.value.page!!.cursor, calls.requests[1].second)
        calls.answers[1].complete(page("second"))
        runCurrent()
        assertEquals("second", model.state.value.page!!.segments.single().preview)
        model.earlier() // no more pages
        assertEquals(2, calls.requests.size)
    }

    @Test fun failureShowsIosMessage() = runTest {
        val model = CoachHistoryModel { _, _ -> throw IOException("synthetic") }
        model.show()
        assertEquals("Chat history is unavailable. Try again.", model.state.value.errorMessage)
        assertFalse(model.state.value.isLoading)
    }

    @Test fun invalidateDropsInFlight() = runTest {
        val calls = Calls()
        val model = CoachHistoryModel(calls.load)
        launch { model.show() }
        runCurrent()
        model.invalidate()
        calls.answers[0].complete(page("late"))
        runCurrent()
        assertNull(model.state.value.page)
        assertFalse(model.state.value.isLoading)
    }
}
