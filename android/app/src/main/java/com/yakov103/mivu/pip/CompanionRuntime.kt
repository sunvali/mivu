package com.yakov103.mivu.pip

import com.yakov103.mivu.pip.MotionPolicy.Playback
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import java.time.LocalTime
import java.util.UUID
import kotlin.coroutines.resume
import kotlin.math.PI
import kotlin.random.Random

/**
 * Plays [CompanionOutput]s on one Pip, a port of iOS `CompanionRuntime` (`apply`, `showStill`, `earTwitch`, `stop`, idle
 * loop). Static or hidden playback runs nothing: no player timers, no breath, no idle loop. [nowMs] is monotonic and
 * drives the springs too, so frames must be sampled on the same clock (`System.nanoTime`, which `withFrameNanos` uses).
 */
class CompanionRuntime(
    private val library: PipGestureLibrary,
    scene: PipRigScene,
    private val scope: CoroutineScope,
    private val nowMs: () -> Long,
    random: Random,
) {
    val motion = PipMotion(scene)
    private val player = PipPlayer(scope, motion) { nowMs() * 1_000_000 }
    private val scheduler = PipIdleScheduler(random)

    /** Timers and loops still running: the player's pending keys plus the idle loop. Zero whenever Pip is still. */
    val activeJobs: Int get() = player.pendingJobs + (if (idleJob?.isActive == true) 1 else 0)
    /** Test probes: idle beats played, and frames drawn by [PipCompanion]. */
    var idleBeats = 0
        private set
    var frames = 0L
        internal set

    private var displayedPose = CompanionPose.Resting
    private var displayedSurface = CompanionSurface.Today
    private var latestSurface = CompanionSurface.Today
    private var latestOutput: CompanionOutput? = null
    private var consumedReaction: UUID? = null
    private var playbackGeneration = 0
    private var gestureToken = 0
    private var gestureActive = false
    private var live = false
    private var curled = false
    private var gaze: Pair<Float, Float>? = null
    private var lastInput = nowMs()
    private var idleJob: Job? = null

    /** Progress dresses Pip with the chart card and glasses; changing it re-applies the current pose without animation (iOS `didSet`). */
    var showsProgressProps: Boolean
        get() = motion.progressProps
        set(value) {
            if (value == motion.progressProps) return
            motion.progressProps = value
            motion.apply(motion.pose)
        }

    fun apply(output: CompanionOutput, surface: CompanionSurface) {
        latestOutput = output
        latestSurface = surface
        if (output.playback != Playback.Animated) {
            output.reactionID?.let { consumedReaction = it }
            pauseAndReset()
            if (output.playback == Playback.StaticPose) showStill(output)
            return
        }
        val fresh = output.reactionID != null && output.reactionID != consumedReaction
        val oneShot = output.pose !in LASTING
        val pose = if (oneShot && !fresh && (displayedPose != output.pose || !gestureActive)) CompanionPose.Resting else output.pose
        val surfaceChanged = surface != displayedSurface
        if (pose != CompanionPose.Attentive) gaze = null
        val typingGaze = if (pose == CompanionPose.Attentive) typingGaze(output.typingProgress) else null
        val changed = pose != displayedPose || surfaceChanged
        if (surfaceChanged) show(surface)
        startIdle()
        if (!(changed || fresh || !live)) {
            if (typingGaze != null && typingGaze != gaze) {
                gaze = typingGaze // same pose: only the eyes follow the text, never a restart
                player.look(typingGaze.first, typingGaze.second)
            }
        } else {
            val token = ++playbackGeneration
            live = true
            displayedPose = pose
            displayedSurface = surface
            motion.setBreathing(true)
            if (pose != CompanionPose.Resting || fresh) lastInput = nowMs()
            val moment = moment(pose, output.tapLevel)
            if (moment != null) {
                var gesture = library.loop(moment) ?: library.gesture(moment)
                if (typingGaze != null) gesture = looking(gesture, typingGaze)
                play(gesture) { if (token == playbackGeneration && oneShot) displayedPose = CompanionPose.Resting }
                if (typingGaze != null) gaze = typingGaze
            } else if (!curled) { // a quiet re-render does not wake a sleeping Pip
                if (fresh) motion.blink(false, nowMs() * 1_000_000)
                play(REST) {}
            }
        }
        output.reactionID?.let { consumedReaction = it }
    }

    /** The small acknowledgement for a touch that cannot start a reaction. Never interrupts anything. */
    fun earTwitch() {
        if (!live || gestureActive || displayedPose != CompanionPose.Resting || curled) return
        play(library.gesture(PipMoment.EarTwitch), wakes = false) {}
    }

    fun stop() = pauseAndReset()

    private fun moment(pose: CompanionPose, tapLevel: Int): PipMoment? = when (pose) {
        CompanionPose.Resting -> null
        CompanionPose.Attentive -> PipMoment.Attentive
        CompanionPose.Thinking -> PipMoment.Thinking
        CompanionPose.Saved -> PipMoment.Saved
        CompanionPose.Reviewed -> PipMoment.Reviewed
        CompanionPose.FirstMealToday -> PipMoment.FirstMealToday
        CompanionPose.DayComplete -> PipMoment.DayComplete
        CompanionPose.WelcomeBack -> PipMoment.WelcomeBack
        CompanionPose.Recovery -> PipMoment.Recovery
        CompanionPose.Greeting -> PipMoment.Greeting(LocalTime.now().hour)
        CompanionPose.Submitted -> PipMoment.Submitted
        CompanionPose.Curious -> PipMoment.Curious
        CompanionPose.Tapped -> PipMoment.Tapped(tapLevel)
        CompanionPose.Patted -> PipMoment.Patted
        CompanionPose.PresentingCheer -> PipMoment.Presenting(cheer = true)
        CompanionPose.PresentingCalm -> PipMoment.Presenting(cheer = false)
        CompanionPose.ProgressEntrance -> PipMoment.ProgressEntrance(cheer = false)
        CompanionPose.ProgressEntranceCheer -> PipMoment.ProgressEntrance(cheer = true)
        CompanionPose.ProgressRange -> PipMoment.ProgressRange
        CompanionPose.ProgressTap -> PipMoment.ProgressTap(tapLevel)
    }

    private fun restPose(surface: CompanionSurface) =
        PipPose(set = if (surface == CompanionSurface.Coach) PipPose.BodySet.seated else PipPose.BodySet.standing)

    /** Remove animations and friends: the semantic pose, held, with no animation and no timers. */
    private fun showStill(output: CompanionOutput) {
        var pose = moment(output.pose, output.tapLevel)?.let(library::stillPose) ?: PipPose()
        pose = pose.copy(set = restPose(latestSurface).set)
        if (output.pose == CompanionPose.Attentive) typingGaze(output.typingProgress).let { pose = pose.copy(gazeX = it.first, gazeY = it.second) }
        motion.apply(pose)
    }

    private fun show(surface: CompanionSurface) {
        curled = false
        displayedSurface = surface
        motion.apply(restPose(surface))
    }

    /** Plays [gesture]; `done(finished)` is false when anything else takes the rig. A sleeping Pip wakes first. */
    private fun play(gesture: PipGesture, wakes: Boolean = true, done: (Boolean) -> Unit) {
        val token = ++gestureToken
        gestureActive = true
        val finish = { finished: Boolean ->
            if (token == gestureToken) {
                gestureActive = false // an interrupted gesture must not leave the idle loop waiting
                if (finished) gesture.endSet?.let { curled = it == PipPose.BodySet.curled }
            }
            done(finished)
        }
        if (curled && wakes) {
            player.play(library.named("wake").copy(endSet = restPose(displayedSurface).set)) { finished ->
                if (!finished || token != gestureToken) finish(false)
                else {
                    curled = false
                    player.play(gesture, finish)
                }
            }
        } else {
            player.play(gesture, finish)
        }
    }

    private fun startIdle() {
        if (idleJob == null) idleJob = scope.launch { idleLoop() }
    }

    private suspend fun idleLoop() {
        while (currentCoroutineContext().isActive) {
            // Wait out feedback and gestures first, so the scheduler's hug-then-curl memory never advances unseen.
            if (!live || displayedPose != CompanionPose.Resting || gestureActive) { delay(500); continue }
            val now = nowMs()
            val surface = displayedSurface
            val (beat, at) = scheduler.next(lastInput, now, surface)
            delay(maxOf(0, at - now))
            // The wait can outlast a touch, a reaction or a surface change; a beat chosen before them is stale.
            if (!live || displayedPose != CompanionPose.Resting || gestureActive || lastInput > now || displayedSurface != surface) continue
            idleBeats++
            when (beat) {
                PipIdleScheduler.Beat.Blink -> motion.blink(false, nowMs() * 1_000_000)
                PipIdleScheduler.Beat.DoubleBlink -> motion.blink(true, nowMs() * 1_000_000)
                is PipIdleScheduler.Beat.Glance -> {
                    player.look(beat.x.toFloat(), beat.y.toFloat())
                    delay(900)
                    if (live && !gestureActive && displayedPose == CompanionPose.Resting) player.look(0f, 0f)
                }
                else -> {
                    val gesture = library.gesture(beat, curled) ?: continue
                    suspendCancellableCoroutine { done -> play(gesture, wakes = false) { if (done.isActive) done.resume(Unit) } }
                }
            }
        }
    }

    private fun pauseAndReset() {
        playbackGeneration++
        gestureToken++
        gestureActive = false
        live = false
        curled = false
        idleJob?.cancel()
        idleJob = null
        player.stop()
        motion.setBreathing(false)
        gaze = null
        show(latestSurface)
        displayedPose = CompanionPose.Resting
        latestOutput?.reactionID?.let { consumedReaction = it }
    }

    private companion object {
        val REST = PipGesture("rest", listOf(0.3 to PipPose()), loops = false, endSet = null)
        val LASTING = setOf(CompanionPose.Resting, CompanionPose.Attentive, CompanionPose.Thinking, CompanionPose.Recovery,
            CompanionPose.PresentingCheer, CompanionPose.PresentingCalm)

        /** Looks down at the field below Pip's paws and follows the caret left to right as the draft grows. */
        fun typingGaze(progress: Double) = (-0.3f + 1.3f * progress.coerceIn(0.0, 1.0).toFloat()) to 0.8f

        /** Typing holds the attentive loop's first pose, head bowed 14° toward the text and turned with it. */
        fun looking(gesture: PipGesture, at: Pair<Float, Float>) = gesture.copy(
            keys = gesture.keys.take(1).map { (time, pose) ->
                val head = (pose.joints["head"] ?: PipPose.Joint()).copy(rotation = (14 * PI / 180).toFloat())
                time to pose.copy(joints = pose.joints + ("head" to head), gazeX = at.first, gazeY = at.second, headTurn = 1 + 0.35f * at.first)
            },
            loops = false,
        )
    }
}
