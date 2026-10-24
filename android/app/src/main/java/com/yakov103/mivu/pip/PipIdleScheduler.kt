package com.yakov103.mivu.pip

import kotlin.random.Random

/**
 * Picks Pip's next idle beat and when to play it, a one-to-one port of iOS `PipIdleScheduler`. Pure and seedable; the
 * caller plays the beat and skips it when anything higher priority (typing, feedback, taps, motion policy) is active.
 */
class PipIdleScheduler(private val random: Random) {
    sealed interface Beat {
        data object Blink : Beat
        data object DoubleBlink : Beat
        data class Glance(val x: Double, val y: Double) : Beat
        data object EarFlick : Beat
        data object WeightShift : Beat
        data object Yawn : Beat
        data object Stretch : Beat
        data object HugTail : Beat
        data object CurlUp : Beat
    }

    private var last: Beat? = null
    /** Set after a hug; the curl follows unless the user has touched Pip since. */
    private var hugged: Long? = null
    private var curled: Long? = null

    /**
     * The beat to play at the returned time (ms), 2-6 s after [now]. Yawn and stretch need 30 s of quiet; on Today, a
     * tail hug and then a curl-up need 90 s. A curled Pip only blinks and flicks an ear until the next input.
     */
    fun next(lastInput: Long, now: Long, surface: CompanionSurface): Pair<Beat, Long> {
        val quiet = now - lastInput
        if (hugged.let { it != null && it < lastInput }) hugged = null
        if (curled.let { it != null && it < lastInput }) curled = null
        var choices: List<Pair<Beat, Double>> = when {
            curled != null -> listOf(Beat.Blink to 5.0, Beat.DoubleBlink to 1.0, Beat.EarFlick to 2.0)
            hugged != null && surface == CompanionSurface.Today -> listOf(Beat.CurlUp to 1.0) // Coach never curls
            else -> buildList {
                addAll(listOf(Beat.Blink to 5.0, Beat.DoubleBlink to 1.0, glanceTarget() to 3.0, Beat.EarFlick to 2.0, Beat.WeightShift to 2.0))
                if (quiet >= 30_000) addAll(listOf(Beat.Yawn to 1.0, Beat.Stretch to 1.0))
                if (quiet >= 90_000 && surface == CompanionSurface.Today) add(Beat.HugTail to 3.0)
            }
        }
        // Never the same beat twice in a row, so no loop shows.
        val fresh = choices.filter { !sameKind(it.first, last) }
        if (fresh.isNotEmpty()) choices = fresh
        var roll = random.nextDouble(choices.sumOf { it.second })
        val beat = choices.firstOrNull { roll -= it.second; roll < 0 }?.first ?: choices[0].first
        last = beat
        if (beat == Beat.HugTail) hugged = now
        if (beat == Beat.CurlUp) { curled = now; hugged = null }
        return beat to now + (random.nextDouble(2.0, 6.0) * 1000).toLong()
    }

    private fun glanceTarget() = Beat.Glance(random.nextDouble(-0.9, 0.9), random.nextDouble(-0.4, 0.4))

    private fun sameKind(a: Beat, b: Beat?) = a == b || (a is Beat.Glance && b is Beat.Glance)
}
