package com.yakov103.mivu.pip

import com.yakov103.mivu.pip.MotionPolicy.Playback
import java.util.UUID

/** The Coach, Today and Progress poses. Reviewed, welcome back, first meal and day complete come in milestone 7. */
enum class CompanionPose {
    Resting, Attentive, Thinking, Saved, Recovery, Greeting, Submitted, Curious, Tapped, Patted,
    /** Progress: holding the chart card, a cheer on a good period and a calm smile otherwise; both loop. */
    PresentingCalm, PresentingCheer,
    /** Progress one-shots: the entrance once a visit, a range switch, and each tap's next trick (`tapLevel`). */
    ProgressEntrance, ProgressEntranceCheer, ProgressRange, ProgressTap,
}

/** A durable commit Pip may acknowledge. It carries no food amounts, so feedback can never celebrate them. */
data class CompanionEvent(val profileID: UUID, val operationID: UUID, val kind: Kind, val committedAt: Long) {
    enum class Kind { Saved, PhotoAdded }
}

/** An accepted Coach send, acknowledged before any data work finishes. */
data class CompanionSubmission(val profileID: UUID, val operationID: UUID, val acceptedAt: Long, val attemptID: UUID = UUID.randomUUID())

data class CompanionContext(
    val surface: CompanionSurface?,
    val isTyping: Boolean,
    val isProcessing: Boolean,
    val needsRecovery: Boolean,
    val playback: Playback,
    /** How far the typing gaze has moved right, 0...60. */
    val draftLength: Int = 0,
)

enum class CompanionTouch { Tap, Pat }

data class CompanionOutput(
    val pose: CompanionPose,
    val playback: Playback,
    val reactionID: UUID?,
    val tapLevel: Int = 0,
    val typingProgress: Double = 0.0,
    /** When the reaction ends (ms), so the caller resolves again then; null when nothing is timed. */
    val nextDeadline: Long? = null,
)

/**
 * Which pose Pip shows, a port of iOS `CompanionPresentation`. Priority: policy > recovery > typing > fresh success >
 * processing > tap/pat > greeting > rest. Events and submissions are deduplicated per profile and dropped after
 * [MivuMotion.feedbackLifetime] or when older than the attach or the latest commit. Times are epoch ms from [nowMs].
 */
class CompanionPresentation(private val nowMs: () -> Long) {
    private class Reaction(val pose: CompanionPose, val deadline: Long, val tapLevel: Int = 0) { val id: UUID = UUID.randomUUID() }

    private var profileID: UUID? = null
    private var attachedAt: Long? = null
    private val received = HashSet<Triple<UUID, UUID, CompanionEvent.Kind>>()
    private val receivedSubmissions = HashSet<Triple<UUID, UUID, UUID>>()
    private var pendingSubmission: CompanionSubmission? = null
    private var pending: CompanionEvent? = null
    private var latestCommit: Long? = null
    private var active: Reaction? = null
    private var greetingAvailable = true
    private var lastContext: CompanionContext? = null
    private var typingProgress = 0.0
    private var lastTapAt: Long? = null
    private var tapCount = 0
    private var tapTurn = 0

    fun attach(profileID: UUID?) {
        if (this.profileID != profileID) {
            clearReactions()
            attachedAt = if (profileID == null) null else nowMs()
            latestCommit = null
            tapCount = 0
            tapTurn = 0
            lastTapAt = null
        }
        this.profileID = profileID
    }

    fun receive(submission: CompanionSubmission): Boolean {
        if (submission.profileID != profileID ||
            !receivedSubmissions.add(Triple(submission.profileID, submission.operationID, submission.attemptID))) return false
        if (!fresh(submission.acceptedAt)) return false
        clearReactions()
        pendingSubmission = submission
        return true
    }

    fun receive(event: CompanionEvent) {
        if (event.profileID != profileID || !received.add(Triple(event.profileID, event.operationID, event.kind))) return
        if (!fresh(event.committedAt)) return
        latestCommit = event.committedAt
        pending = event
    }

    fun resolve(context: CompanionContext): CompanionOutput {
        val now = nowMs()
        if (pendingSubmission.let { it != null && now - it.acceptedAt >= LIFETIME }) pendingSubmission = null
        if (pending.let { it != null && now - it.committedAt >= LIFETIME }) pending = null
        lastContext = context
        typingProgress = context.draftLength.coerceIn(0, 60) / 60.0
        val semantic = when {
            context.needsRecovery -> CompanionPose.Recovery
            context.isTyping -> CompanionPose.Attentive
            context.isProcessing -> CompanionPose.Thinking
            else -> CompanionPose.Resting
        }
        val playback = if (profileID == null || context.surface == null) Playback.Hidden else context.playback

        if (context.needsRecovery || context.isTyping) {
            clearReactions()
            greetingAvailable = false
        }
        if (playback == Playback.Hidden) {
            if (pendingSubmission != null || active?.pose == CompanionPose.Submitted) clearReactions()
            active = null
            return output(semantic, playback)
        }
        if (playback != Playback.Animated) {
            clearReactions()
            greetingAvailable = false
            return output(semantic, Playback.StaticPose)
        }
        if (context.needsRecovery || context.isTyping) return output(semantic, playback)

        if (pendingSubmission != null) {
            pendingSubmission = null
            greetingAvailable = false
            active = Reaction(CompanionPose.Submitted, now + ms(MivuMotion.submitted))
        }
        active?.let { if (it.pose == CompanionPose.Submitted && now < it.deadline) return output(it.pose, playback, it) }
        pending?.let {
            pending = null
            greetingAvailable = false
            active = when (it.kind) {
                CompanionEvent.Kind.Saved -> Reaction(CompanionPose.Saved, now + ms(MivuMotion.saved))
                CompanionEvent.Kind.PhotoAdded -> Reaction(CompanionPose.Curious, now + ms(MivuMotion.curious))
            }
        }
        if (context.isProcessing && active?.pose in INTERRUPTIBLE) active = null
        active?.let {
            if (now < it.deadline) return output(it.pose, playback, it)
            active = null
        }
        if (context.isProcessing) {
            greetingAvailable = false
            return output(CompanionPose.Thinking, playback)
        }
        if (greetingAvailable) {
            greetingAvailable = false
            val greeting = Reaction(CompanionPose.Greeting, now + ms(MivuMotion.greeting))
            active = greeting
            return output(greeting.pose, playback, greeting)
        }
        return output(CompanionPose.Resting, playback)
    }

    /** False means the caller should only twitch an ear: no reaction is started or queued. */
    fun touch(kind: CompanionTouch): Boolean {
        val context = lastContext ?: return false
        if (context.playback != Playback.Animated || context.surface == null || profileID == null || context.needsRecovery ||
            context.isTyping || context.isProcessing || pending != null || pendingSubmission != null) return false
        val now = nowMs()
        active?.let { if (now < it.deadline && it.pose !in TOUCHABLE) return false }
        greetingAvailable = false
        active = when (kind) {
            CompanionTouch.Pat -> Reaction(CompanionPose.Patted, now + ms(MivuMotion.patted))
            CompanionTouch.Tap -> {
                val rapid = lastTapAt.let { it != null && now - it <= 1_500 }
                tapCount = if (rapid) tapCount + 1 else 0
                val shakeOff = tapCount == 4 // a rapid burst ends in the shake-off; other taps take the next reaction in the set
                val reaction = Reaction(CompanionPose.Tapped, now + ms(MivuMotion.tapped), if (shakeOff) 4 else tapTurn % 4)
                if (!shakeOff) tapTurn += 1
                lastTapAt = if (shakeOff) null else now // the shake-off resets the run
                reaction
            }
        }
        return true
    }

    private fun fresh(at: Long): Boolean {
        val age = nowMs() - at
        return age in 0 until LIFETIME && attachedAt.let { it == null || at >= it } && latestCommit.let { it == null || at >= it }
    }

    private fun clearReactions() {
        pendingSubmission = null
        pending = null
        active = null
    }

    private fun output(pose: CompanionPose, playback: Playback, reaction: Reaction? = null) = CompanionOutput(
        pose, playback, reaction?.id, if (pose == CompanionPose.Tapped) reaction?.tapLevel ?: 0 else 0, typingProgress, reaction?.deadline,
    )

    private companion object {
        val LIFETIME = ms(MivuMotion.feedbackLifetime)
        val INTERRUPTIBLE = setOf(CompanionPose.Greeting, CompanionPose.Resting, CompanionPose.Tapped, CompanionPose.Patted)
        val TOUCHABLE = setOf(CompanionPose.Greeting, CompanionPose.Tapped, CompanionPose.Patted)
        fun ms(seconds: Double) = Math.round(seconds * 1000)
    }
}
