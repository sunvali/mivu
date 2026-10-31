package com.yakov103.mivu.pip

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/** App moments Pip reacts to, as iOS `PipMoment`. [PipGestureLibrary.gesture] is the only place that maps them. */
sealed interface PipMoment {
    data class Greeting(val hour: Int) : PipMoment
    data object WelcomeBack : PipMoment
    data object Attentive : PipMoment
    data object Submitted : PipMoment
    data object Thinking : PipMoment
    data object Saved : PipMoment
    data object Reviewed : PipMoment
    data object Recovery : PipMoment
    data object FirstMealToday : PipMoment
    data object DayComplete : PipMoment
    data object Curious : PipMoment
    data class Tapped(val level: Int) : PipMoment
    data object Patted : PipMoment
    data object EarTwitch : PipMoment
    /** Progress: leaning in over the chart; `cheer` on a good period, a calm smile otherwise. */
    data class Presenting(val cheer: Boolean) : PipMoment
    data class ProgressEntrance(val cheer: Boolean) : PipMoment
    data object ProgressRange : PipMoment
    data class ProgressTap(val level: Int) : PipMoment
}

/**
 * Timed poses. Each key is the full pose Pip should arrive at by its time in seconds; the previous key's time is when
 * its spring launches. The last key of a one-shot is rest; a loop repeats from its first key.
 */
data class PipGesture(
    val name: String,
    val keys: List<Pair<Double, PipPose>>,
    val loops: Boolean,
    /** The body set Pip is in afterwards, for the few gestures that change it on purpose (`curl-up`, `wake`). */
    val endSet: PipPose.BodySet?,
) {
    val duration: Double get() = keys.lastOrNull()?.first ?: 0.0
}

/** The gestures iOS exports to `fixtures/pip/gestures.json` (never hand-ported), and the iOS moment table. */
class PipGestureLibrary(val gestures: List<PipGesture>) {
    private val byName = gestures.associateBy { it.name }

    fun named(name: String): PipGesture = byName[name] ?: error("no gesture $name")

    /** The only mapping from app moments to gestures; a port of iOS `gesture(for:)`. */
    fun gesture(moment: PipMoment): PipGesture = named(
        when (moment) {
            is PipMoment.Greeting -> when {
                moment.hour in 5..11 -> "greeting-morning"
                moment.hour >= 19 || moment.hour <= 4 -> "greeting-evening"
                else -> "greeting"
            }
            PipMoment.WelcomeBack -> "welcome-back"
            PipMoment.Attentive -> "attentive"
            PipMoment.Submitted -> "submitted"
            PipMoment.Thinking -> "thinking"
            PipMoment.Saved -> "saved"
            PipMoment.Reviewed -> "reviewed"
            PipMoment.Recovery -> "recovery"
            PipMoment.FirstMealToday -> "first-meal-today"
            PipMoment.DayComplete -> "day-complete"
            PipMoment.Curious -> "curious"
            is PipMoment.Tapped ->
                if (moment.level >= 4) "shake-off" else TAPS[maxOf(moment.level, 0)]
            PipMoment.Patted -> "patted"
            PipMoment.EarTwitch -> "ear-twitch"
            is PipMoment.Presenting -> if (moment.cheer) "presenting-cheer" else "presenting-calm"
            is PipMoment.ProgressEntrance -> if (moment.cheer) "progress-entrance-cheer" else "progress-entrance"
            PipMoment.ProgressRange -> "progress-range"
            is PipMoment.ProgressTap -> PROGRESS_TAPS[maxOf(moment.level, 0) % PROGRESS_TAPS.size]
        },
    )

    fun loop(moment: PipMoment): PipGesture? = gesture(moment).takeIf { it.loops }

    /** The held pose a static Pip shows (reduced motion, power saving): the key before the final settle. */
    fun stillPose(moment: PipMoment): PipPose = gesture(moment).keys.let { if (it.size > 1) it[it.size - 2].second else PipPose() }

    /** The idle beats that need body motion; blinks and glances use [PipMotion.blink] and [PipPlayer.look] instead. */
    fun gesture(idle: PipIdleScheduler.Beat, curled: Boolean): PipGesture? = when (idle) {
        PipIdleScheduler.Beat.Blink, PipIdleScheduler.Beat.DoubleBlink, is PipIdleScheduler.Beat.Glance -> null
        PipIdleScheduler.Beat.EarFlick -> named(if (curled) "curled-ear-flick" else "idle-ear-flick")
        PipIdleScheduler.Beat.WeightShift -> named("idle-weight-shift")
        PipIdleScheduler.Beat.Yawn -> named("idle-yawn")
        PipIdleScheduler.Beat.Stretch -> named("idle-stretch")
        PipIdleScheduler.Beat.HugTail -> named("idle-hug-tail")
        PipIdleScheduler.Beat.CurlUp -> named("curl-up")
    }

    companion object {
        private val TAPS = listOf("tap-giggle", "tap-ear-wiggle", "tap-wink", "tap-tail-flick")
        private val PROGRESS_TAPS = listOf(
            "progress-tap-boing", "progress-tap-dizzy", "progress-tap-tail-chase",
            "progress-tap-heart-eyes", "progress-tap-surprise", "progress-tap-sign-tap",
        )
        private val json = Json { ignoreUnknownKeys = true }

        /**
         * The card arm of the Progress hold, iOS `atChart(.rest)` (`pawUp(.right, -45, elbow: -60)`) on the standing arm
         * only: kept whenever a pose leaves that arm alone ([PipRigScene.resolve] `progressProps`).
         */
        val progressHeldArm: Map<String, PipPose.Joint> = mapOf(
            "arm-r" to PipPose.Joint(rotation = Math.toRadians(-45.0).toFloat()),
            "forearm-r" to PipPose.Joint(rotation = Math.toRadians(60 * 0.85).toFloat()),
            "paw-r" to PipPose.Joint(rotation = Math.toRadians(60 * 0.25).toFloat()),
        )

        fun load(text: String): PipGestureLibrary = PipGestureLibrary(
            json.decodeFromString<FileDto>(text).gestures.map { g ->
                PipGesture(g.name, g.keys.map { it.at to it.pose.toPose() }, g.loops, g.endSet)
            },
        )
    }

    @Serializable private class FileDto(val gestures: List<GestureDto>)
    @Serializable private class GestureDto(val name: String, val loops: Boolean, val endSet: PipPose.BodySet? = null, val keys: List<KeyDto>)
    @Serializable private class KeyDto(val at: Double, val pose: PoseDto)
    @Serializable private class JointDto(val rotation: Float, val offset: List<Float>, val scale: List<Float>)
    @Serializable private class PoseDto(
        val joints: Map<String, JointDto>, val eyes: PipPose.EyeShape, val mouth: PipPose.MouthShape, val gaze: List<Float>,
        val blush: Boolean, val hearts: Int, val set: PipPose.BodySet, val headTurn: Float,
    ) {
        fun toPose() = PipPose(
            joints.mapValues { (_, j) -> PipPose.Joint(j.rotation, j.offset[0], j.offset[1], j.scale[0], j.scale[1]) },
            eyes, mouth, gaze[0], gaze[1], blush, hearts, set, headTurn,
        )
    }
}
