package com.yakov103.mivu.pip

import com.yakov103.mivu.pip.PipIdleScheduler.Beat
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.random.Random

/** Ported from iOS `PipIdleSchedulerTests`; times are milliseconds. */
class PipIdleSchedulerTest {
    private val start = 1_000_000_000L

    private data class Draw(val beat: Beat, val quiet: Long, val gap: Long)

    /** Draws [count] beats, each made when the previous one is due, with no input after [start]. */
    private fun draws(count: Int, quietMs: Long, surface: CompanionSurface, seed: Int = 7): List<Draw> {
        val scheduler = PipIdleScheduler(Random(seed))
        var now = start + quietMs
        return List(count) {
            val (beat, at) = scheduler.next(start, now, surface)
            Draw(beat, now - start, at - now).also { now = at }
        }
    }

    private fun sameKind(a: Beat, b: Beat) = a == b || (a is Beat.Glance && b is Beat.Glance)

    @Test fun neverSameKindTwice() {
        val beats = draws(300, 40_000, CompanionSurface.Coach).map { it.beat }
        for ((a, b) in beats.zipWithNext()) assertTrue("$a then $b", !sameKind(a, b))
        assertTrue(Beat.DoubleBlink in beats)
        assertTrue(beats.filterIsInstance<Beat.Glance>().toSet().size > 3)
    }

    @Test fun yawnNeedsThirtySecondsQuiet() {
        for (seed in 1..5) for (draw in draws(100, 0, CompanionSurface.Coach, seed)) if (draw.quiet < 30_000) {
            assertTrue("${draw.beat} at ${draw.quiet}", draw.beat != Beat.Yawn && draw.beat != Beat.Stretch)
        }
        assertTrue(draws(200, 30_000, CompanionSurface.Coach).any { it.beat == Beat.Yawn })
    }

    @Test fun coachNeverCurls() {
        for (draw in draws(500, 600_000, CompanionSurface.Coach)) assertTrue(draw.beat != Beat.HugTail && draw.beat != Beat.CurlUp)
        // A hug on Today never becomes a curl on Coach.
        val scheduler = PipIdleScheduler(Random(7))
        var now = start + 95_000
        var hugged = false
        repeat(200) { if (!hugged) { hugged = scheduler.next(start, now, CompanionSurface.Today).first == Beat.HugTail; now += 4_000 } }
        assertTrue("precondition: a hug on Today", hugged)
        repeat(50) { assertNotEquals(Beat.CurlUp, scheduler.next(start, now, CompanionSurface.Coach).first); now += 4_000 }
        // On Today the curl follows the hug.
        val late = draws(40, 90_000, CompanionSurface.Today).map { it.beat }
        assertEquals(late.indexOf(Beat.HugTail) + 1, late.indexOf(Beat.CurlUp))
    }

    @Test fun beatIsTwoToSixSecondsAhead() {
        for (draw in draws(200, 0, CompanionSurface.Today)) assertTrue("${draw.gap}", draw.gap in 2_000..6_000)
    }

    @Test fun curledOnlyBlinksAndFlicks() {
        val scheduler = PipIdleScheduler(Random(7))
        var now = start + 95_000
        while (true) {
            val (beat, at) = scheduler.next(start, now, CompanionSurface.Today)
            now = at
            if (beat == Beat.CurlUp) break
        }
        repeat(30) {
            val (beat, at) = scheduler.next(start, now, CompanionSurface.Today)
            assertTrue("asleep Pip only blinks and flicks: $beat", beat == Beat.Blink || beat == Beat.DoubleBlink || beat == Beat.EarFlick)
            now = at
        }
        val input = now + 1_000
        val fresh = scheduler.next(input, input, CompanionSurface.Today).first
        assertTrue(fresh != Beat.CurlUp && fresh != Beat.HugTail)
    }
}
