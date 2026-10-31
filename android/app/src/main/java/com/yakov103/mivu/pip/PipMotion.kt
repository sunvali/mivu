package com.yakov103.mivu.pip

import androidx.compose.animation.core.AnimationVector1D
import androidx.compose.animation.core.EaseInOut
import androidx.compose.animation.core.SpringSpec
import androidx.compose.animation.core.VectorConverter
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.roundToLong
import kotlin.math.sqrt

/**
 * Pip's springs, blink and breath, ported from the iOS `PipRigView` motion extension. Every changed joint component
 * (rotation, x, y, scaleX, scaleY) gets its own Compose spring, started from the sampled value and velocity, so any
 * pose interrupts any other without a jump. [sample] fills one reused [PipFrame] per call, so frames do not allocate.
 * Main thread only: the frame loop, springs and player jobs share unsynchronized state.
 */
class PipMotion(val scene: PipRigScene) {
    private val parts = scene.asset.parts
    private val n = parts.size
    private val frame = PipFrame(scene)

    /** Progress's chart card, glasses and held arm (iOS `showsProgressProps`); takes effect on the next apply or transition. */
    var progressProps = false

    /** The pose being moved to (the CALayer model values on iOS). */
    var pose = PipPose()
        private set

    private val target = FloatArray(n * 5)
    private val springs = arrayOfNulls<Spring>(n * 5)
    private val visible = BooleanArray(n)
    private val alphaTo = FloatArray(n) { 1f }
    private val alphaFrom = FloatArray(n)
    private val fadeStart = LongArray(n) { NONE }

    /** Lower legs and paws trail the upper leg, like ears, tail and scarf trail the body (overlapping action). */
    private val follower = BooleanArray(n) { i -> FOLLOWERS.any { parts[i].name.startsWith(it) } }
    private val saccade = BooleanArray(n) { scene.followsGaze(parts[it].id) }
    private val heart = BooleanArray(n) { parts[it].name.startsWith("heart-") }
    private val breathers = parts.indices.filter { parts[it].name == "head" || parts[it].name == "chest" }.toIntArray()
    /** Per head view: the part indices of the open, half and shut eye slots, both eyes. */
    private val eyeSlots: Map<String, Array<IntArray>> = listOf("right", "front", "left").associateWith { view ->
        Array(BLINK_SHAPES.size) { s ->
            parts.indices.filter { parts[it].view == view && scene.slot(parts[it].id) in setOf("eye-l.${BLINK_SHAPES[s]}", "eye-r.${BLINK_SHAPES[s]}") }.toIntArray()
        }
    }

    private var blinkStart = NONE
    private var blinkDouble = false
    private var blinkView = "right"
    private var breathing = false
    private var breathStart = NONE

    init { apply(pose) }

    /** Snaps to [pose] with no animation. */
    fun apply(pose: PipPose) {
        val r = scene.resolve(pose, progressProps)
        for ((i, part) in parts.withIndex()) {
            write(i, r.joints[part.id] ?: PipRigScene.REST)
            for (c in 0 until 5) springs[i * 5 + c] = null
            visible[i] = part.id in r.visible
            alphaTo[i] = r.alpha[part.id] ?: 1f
            fadeStart[i] = NONE
        }
        this.pose = pose
    }

    /** Moves to [target] over a key of [periodSeconds]. A part that was or becomes hidden snaps; fades take 180 ms. */
    fun transition(target: PipPose, periodSeconds: Double, nowNanos: Long) {
        val r = scene.resolve(target, progressProps)
        for ((i, part) in parts.withIndex()) {
            val shown = part.id in r.visible
            val joint = r.joints[part.id] ?: PipRigScene.REST
            val alpha = r.alpha[part.id] ?: 1f
            // A part that was hidden has no meaningful on-screen value: it snaps to its pose instead of springing.
            if (!shown || !visible[i]) {
                write(i, joint)
                for (c in 0 until 5) springs[i * 5 + c] = null
                visible[i] = shown
                alphaTo[i] = alpha
                fadeStart[i] = NONE
                continue
            }
            val begin = if (follower[i]) nowNanos + FOLLOW_DELAY else nowNanos
            for (c in 0 until 5) {
                val k = i * 5 + c
                val to = component(joint, c)
                // Only a changed target springs; a running spring, and the additive breath on top of it, are left alone.
                if (abs(this.target[k] - to) <= EPSILON) continue
                val from = value(k, begin)
                val velocity = velocity(k, begin)
                this.target[k] = to
                springs[k] = if (abs(from - to) <= EPSILON) null
                else Spring(from, to, velocity, begin, spring(periodSeconds, follower[i], saccade[i]), springs[k], nowNanos)
            }
            if (part.id in r.alpha && alphaTo[i] != alpha) {
                val from = alphaAt(i, nowNanos)
                alphaFrom[i] = from
                fadeStart[i] = nowNanos
                // Hearts pop in on a bouncy spring as they fade in.
                if (heart[i] && from < 0.5f && alpha == 1f) for (c in 3..4) {
                    springs[i * 5 + c] = Spring(0.2f, this.target[i * 5 + c], 0f, nowNanos, POP, null, nowNanos)
                }
            }
            alphaTo[i] = alpha
        }
        pose = target
    }

    /** A drawn cartoon blink: half-shut 40 ms, shut 72 ms, half-shut 40 ms, open; [double] blinks again 0.3 s later. */
    fun blink(double: Boolean, nowNanos: Long) {
        if (pose.eyes != PipPose.EyeShape.open) return
        blinkView = PipRigScene.viewFor(pose.headTurn).first
        blinkStart = nowNanos
        blinkDouble = double
    }

    /** Chest and head swell 2% over 4.5 s and back, added on top of the springs instead of fighting them. */
    fun setBreathing(on: Boolean) {
        if (on == breathing) return // keep the phase running
        breathing = on
        breathStart = NONE
    }

    fun sample(nowNanos: Long): PipFrame {
        val f = frame
        for (k in 0 until n * 5) f.joints[k] = value(k, nowNanos)
        for (i in 0 until n) {
            f.visible[i] = visible[i]
            f.alpha[i] = alphaAt(i, nowNanos)
        }
        if (blinkStart != NONE) blinkInto(f, nowNanos)
        val breath = if (breathing) {
            if (breathStart == NONE) breathStart = nowNanos
            val phase = (nowNanos - breathStart) % (2 * BREATH)
            val u = if (phase < BREATH) phase.toFloat() / BREATH else 2f - phase.toFloat() / BREATH
            0.02f * EaseInOut.transform(u)
        } else 0f
        for (i in breathers) f.scaleYAdd[i] = breath
        f.set = pose.set
        scene.render(f)
        return f
    }

    private fun blinkInto(f: PipFrame, now: Long) {
        val slots = eyeSlots.getValue(blinkView)
        for (o in 0..(if (blinkDouble) 1 else 0)) {
            val local = now - blinkStart - o * DOUBLE_GAP
            if (local < 0 || local >= BLINK) continue
            // Key times 0, 0.25, 0.7 and 0.95 of 160 ms: half, shut, half, then open again for the last 5%.
            val phase = when { local < BLINK / 4 -> 0; local < BLINK * 7 / 10 -> 1; local < BLINK * 19 / 20 -> 2; else -> 3 }
            for (s in slots.indices) for (i in slots[s]) f.visible[i] = BLINK_SHOWN[s][phase]
        }
        if (now - blinkStart >= DOUBLE_GAP + BLINK) blinkStart = NONE
    }

    private fun value(k: Int, t: Long): Float {
        val s = springs[k] ?: return target[k]
        if (s.done(t)) springs[k] = null
        return s.value(t)
    }

    private fun velocity(k: Int, t: Long) = springs[k]?.velocity(t) ?: 0f

    private fun alphaAt(i: Int, t: Long): Float {
        val start = fadeStart[i]
        if (start == NONE) return alphaTo[i]
        val u = (t - start).toFloat() / FADE
        if (u >= 1f) { fadeStart[i] = NONE; return alphaTo[i] }
        return alphaFrom[i] + (alphaTo[i] - alphaFrom[i]) * u.coerceAtLeast(0f)
    }

    private fun write(i: Int, j: PipPose.Joint) { for (c in 0 until 5) target[i * 5 + c] = component(j, c) }

    private fun component(j: PipPose.Joint, c: Int) = when (c) { 0 -> j.rotation; 1 -> j.offsetX; 2 -> j.offsetY; 3 -> j.scaleX; else -> j.scaleY }

    /** One component's spring from [from] with [v0] (per second), starting at [start]; before that, [prev] still runs. */
    private class Spring(from: Float, private val to: Float, v0: Float, private val start: Long, spec: SpringSpec<Float>, prev: Spring?, now: Long) {
        private val anim = spec.vectorize(Float.VectorConverter)
        private val a = AnimationVector1D(from)
        private val b = AnimationVector1D(to)
        private val v = AnimationVector1D(v0)
        private val duration = anim.getDurationNanos(a, b, v)
        private val hold = from
        // Only a follower's 60 ms delay still needs the old spring; time only moves forward, so older links are cut.
        private var prev: Spring? = prev?.takeIf { start > now }?.also { if (it.start <= now) it.prev = null }

        fun done(t: Long) = t - start >= duration
        fun value(t: Long): Float = when {
            t < start -> prev?.value(t) ?: hold
            t - start >= duration -> to
            else -> anim.getValueFromNanos(t - start, a, b, v).value
        }
        fun velocity(t: Long): Float = when {
            t < start -> prev?.velocity(t) ?: 0f
            t - start >= duration -> 0f
            else -> anim.getVelocityFromNanos(t - start, a, b, v).value
        }
    }

    companion object {
        private const val NONE = Long.MIN_VALUE
        private const val EPSILON = 0.0005f
        private const val FOLLOW_DELAY = 60_000_000L
        private const val FADE = 180_000_000f
        private const val BLINK = 160_000_000L
        private const val DOUBLE_GAP = 300_000_000L
        private const val BREATH = 4_500_000_000L
        private val FOLLOWERS = listOf("ear-", "tail-2", "tail-3", "tail-4", "scarf-end-", "forearm-", "paw-")
        private val BLINK_SHAPES = listOf("open", "half", "closedSleepy")
        private val BLINK_SHOWN = arrayOf(
            booleanArrayOf(false, false, false, true), booleanArrayOf(true, false, true, false), booleanArrayOf(false, true, false, false),
        )
        /** CA `stiffness 260, damping 9`: a damping ratio of 9 / (2√260). */
        private val POP = SpringSpec(dampingRatio = (9 / (2 * sqrt(260.0))).toFloat(), stiffness = 260f, visibilityThreshold = EPSILON)

        /**
         * ω is chosen so the first overshoot lands near the key time, capped so short keys ease instead of snap. The body
         * settles with little wobble; followers are 40% softer and bouncier; gaze parts saccade in about 60 ms.
         */
        fun spring(period: Double, follower: Boolean, saccade: Boolean): SpringSpec<Float> {
            var omega = if (saccade) 110.0 else (3.76 / max(period, 0.05)).coerceIn(14.0, 60.0)
            if (follower) omega *= sqrt(0.6)
            val ratio = if (saccade) 0.6 else if (follower) 0.5 else 0.68
            return SpringSpec(dampingRatio = ratio.toFloat(), stiffness = (omega * omega).toFloat(), visibilityThreshold = EPSILON)
        }
    }
}

/**
 * Plays gestures on a [PipMotion], ported from iOS `play`, `schedule`, `step` and `look(at:)`: a key's spring launches at
 * the previous key's time, eyes lead a head turn by 80 ms, a view swap lands inside a blink, and loops repeat.
 * Main thread only: the frame loop, springs and player jobs share unsynchronized state.
 */
class PipPlayer(private val scope: CoroutineScope, private val motion: PipMotion, private val nanos: () -> Long) {
    private class Playback(val onDone: (Boolean) -> Unit) { val jobs = ArrayList<Job>() }

    private var playback: Playback? = null
    private var lookFollow: Job? = null

    /** Timers still waiting; bounded by one pass of the current gesture's keys, even for a loop. */
    val pendingJobs: Int get() = (playback?.jobs?.count { it.isActive } ?: 0) + (if (lookFollow?.isActive == true) 1 else 0)

    /** `onDone(false)` if another play or [stop] ends it first. */
    fun play(gesture: PipGesture, onDone: (finished: Boolean) -> Unit) {
        stopPlayback()
        val run = Playback(onDone)
        playback = run
        schedule(gesture, run)
    }

    fun stop() {
        stopPlayback()
        lookFollow?.cancel()
        lookFollow = null
    }

    /**
     * Saccade to ([x], [y]) (unit disc, +y down). With no gesture playing the head follows 0.1 s later over 0.45 s: the
     * face slides toward the look inside the right view and nods up to 3°, unless the pose already nods.
     */
    fun look(x: Float, y: Float) {
        val next = motion.pose.copy(gazeX = x, gazeY = y)
        motion.transition(next, 0.06, nanos())
        lookFollow?.cancel()
        if (playback != null) return
        val head = next.joints["head"] ?: PipPose.Joint()
        val follow = next.copy(
            headTurn = 1 + 0.35f * x, // 0.65...1.35 stays in the right view
            joints = if (head.rotation == 0f) next.joints + ("head" to head.copy(rotation = (3 * PI / 180).toFloat() * y)) else next.joints,
        )
        lookFollow = scope.launch {
            delay(100)
            if (playback == null && motion.pose == next) motion.transition(follow, 0.45, nanos())
        }
    }

    private fun schedule(gesture: PipGesture, run: Playback) {
        for ((i, key) in gesture.keys.withIndex()) {
            val launch = if (i == 0) 0.0 else gesture.keys[i - 1].first
            val changesSet = if (i == gesture.keys.lastIndex) gesture.endSet else null
            after(launch, run) { step(key.second, changesSet, key.first - launch, run) }
        }
        after(gesture.duration, run) {
            run.jobs.clear()
            if (gesture.loops && gesture.duration > 0) { // a zero-length loop would recurse forever
                schedule(gesture, run)
            } else {
                playback = null
                run.onDone(true)
            }
        }
    }

    /** Runs [work] now when [seconds] is zero, else later unless the playback was stopped. */
    private fun after(seconds: Double, run: Playback, work: () -> Unit) {
        if (seconds <= 0) { work(); return }
        run.jobs += scope.launch {
            delay((seconds * 1000).roundToLong())
            if (playback === run) work()
        }
    }

    private fun stopPlayback() {
        val run = playback ?: return
        playback = null
        run.jobs.forEach { it.cancel() }
        run.jobs.clear()
        run.onDone(false)
    }

    /** One key: eyes go first when the head turns, then the head follows. */
    private fun step(key: PipPose, set: PipPose.BodySet?, period: Double, run: Playback) {
        val pose = motion.pose
        val target = key.copy(set = set ?: pose.set) // gestures are authored on rest; only a declared endSet changes the set
        if (target.headTurn == pose.headTurn || period <= EYES_LEAD) {
            motion.transition(target, period, nanos())
            return
        }
        motion.transition(pose.copy(gazeX = if (target.headTurn > pose.headTurn) 1f else -1f, gazeY = target.gazeY), period, nanos())
        // A view swap lands while the eyes are shut (40-110 ms into the blink), so it reads as a quick turn, not a cut.
        if (PipRigScene.viewFor(target.headTurn).first != PipRigScene.viewFor(pose.headTurn).first) motion.blink(false, nanos())
        after(EYES_LEAD, run) { motion.transition(target, period - EYES_LEAD, nanos()) }
    }

    private companion object {
        const val EYES_LEAD = 0.08
    }
}
