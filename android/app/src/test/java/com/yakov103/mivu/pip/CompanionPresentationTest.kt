package com.yakov103.mivu.pip

import com.yakov103.mivu.pip.MotionPolicy.Playback
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.ZoneOffset
import java.util.UUID

/** Ported from iOS `CompanionPresentationTests` for the Coach and Today poses. */
class CompanionPresentationTest {
    private val t = 1_800_000_000_000L
    private var now = t
    private val owner = UUID.randomUUID()

    private fun context(
        surface: CompanionSurface? = CompanionSurface.Today, typing: Boolean = false, processing: Boolean = false,
        recovery: Boolean = false, playback: Playback = Playback.Animated,
    ) = CompanionContext(surface, typing, processing, recovery, playback)

    private fun event(at: Long = t, operation: UUID = UUID.randomUUID(), kind: CompanionEvent.Kind = CompanionEvent.Kind.Saved) =
        CompanionEvent(owner, operation, kind, at)

    private fun presentation() = CompanionPresentation({ now }, { ZoneOffset.UTC })
    private fun attached() = presentation().also { it.attach(owner) }

    private fun resolve(p: CompanionPresentation, at: Long, context: CompanionContext = context()): CompanionOutput {
        now = at
        return p.resolve(context)
    }

    @Test fun submittedThenSavedThenRest() {
        val p = attached()
        val submission = CompanionSubmission(owner, UUID.randomUUID(), t)
        assertTrue(p.receive(submission))
        p.receive(event(operation = submission.operationID))
        val accepted = resolve(p, t)
        assertEquals(CompanionPose.Submitted, accepted.pose)
        assertEquals(t + 800, accepted.nextDeadline)
        assertEquals(accepted, resolve(p, t + 799))
        assertEquals(CompanionPose.Saved, resolve(p, t + 800).pose)
        assertEquals(CompanionPose.Saved, resolve(p, t + 1_249).pose)
        val rest = resolve(p, t + 1_250)
        assertEquals(CompanionPose.Resting, rest.pose)
        assertNull(rest.reactionID)
    }

    @Test fun typingClearsReactions() {
        val p = attached()
        p.receive(event())
        resolve(p, t)
        val focused = resolve(p, t + 100, context(typing = true, processing = true))
        assertEquals(CompanionPose.Attentive, focused.pose)
        assertNull(focused.reactionID)
        assertNull(focused.nextDeadline)
        assertNotEquals(CompanionPose.Saved, resolve(p, t + 200).pose)
    }

    @Test fun recoveryOutranksEverything() {
        val p = attached()
        p.receive(event())
        val recovery = resolve(p, t, context(typing = true, processing = true, recovery = true))
        assertEquals(CompanionPose.Recovery, recovery.pose)
        assertNull(recovery.nextDeadline)
        assertNotEquals(CompanionPose.Saved, resolve(p, t + 100).pose)
        // Policy outranks recovery: hidden stays hidden.
        assertEquals(Playback.Hidden, resolve(p, t + 200, context(recovery = true, playback = Playback.Hidden)).playback)
    }

    @Test fun processingShowsThinkingAfterSubmitted() {
        val p = attached()
        val operation = UUID.randomUUID()
        val submission = CompanionSubmission(owner, operation, t)
        p.receive(submission)
        val first = resolve(p, t, context(processing = true))
        assertEquals(CompanionPose.Submitted, first.pose)
        assertNotNull(first.reactionID)
        assertEquals(CompanionPose.Thinking, resolve(p, t + 800, context(processing = true)).pose)
        // The same attempt again never replays.
        now = t + 1_000
        assertFalse(p.receive(CompanionSubmission(owner, operation, t + 1_000, submission.attemptID)))
        val duplicate = resolve(p, t + 1_000, context(processing = true))
        assertEquals(CompanionPose.Thinking, duplicate.pose)
        assertNull(duplicate.reactionID)
    }

    @Test fun staleEventIgnored() {
        val p = attached()
        resolve(p, t) // the greeting
        now = t + 10_000
        p.receive(event(at = t)) // 10 s old
        p.receive(event(at = t - 1)) // before the attach
        assertEquals(CompanionPose.Resting, resolve(p, t + 10_000).pose)
        now = t + 10_000
        p.receive(event(at = t + 9_000))
        p.receive(event(at = t + 8_000)) // older than the latest commit
        assertEquals(CompanionPose.Saved, resolve(p, t + 10_000).pose)
        assertEquals(CompanionPose.Resting, resolve(p, t + 10_450).pose)
    }

    @Test fun duplicateEventIgnored() {
        val p = attached()
        val saved = event()
        p.receive(saved)
        assertEquals(CompanionPose.Saved, resolve(p, t).pose)
        assertEquals(CompanionPose.Resting, resolve(p, t + 500).pose)
        now = t + 600
        p.receive(saved.copy(committedAt = t + 600)) // same identity, new timestamp
        assertEquals(CompanionPose.Resting, resolve(p, t + 600).pose)
    }

    @Test fun tapDuringProcessingOnlyTwitches() {
        val p = attached()
        val busy = context(processing = true)
        val before = resolve(p, t, busy)
        assertFalse(p.touch(CompanionTouch.Tap))
        val after = resolve(p, t + 100, busy)
        assertEquals(CompanionPose.Thinking, after.pose)
        assertEquals(before.pose, after.pose)
        // Static playback never starts a reaction either.
        resolve(p, t + 200, context(playback = Playback.StaticPose))
        assertFalse(p.touch(CompanionTouch.Pat))
    }

    @Test fun fifthRapidTapShakesOff() {
        val p = attached()
        val levels = mutableListOf<Int>()
        val ids = mutableSetOf<UUID>()
        for (i in 0 until 6) {
            val at = t + 300L * i
            resolve(p, at)
            assertTrue(p.touch(CompanionTouch.Tap))
            val out = resolve(p, at)
            assertEquals(CompanionPose.Tapped, out.pose)
            levels += out.tapLevel
            ids += out.reactionID!!
        }
        assertEquals(listOf(0, 1, 2, 3, 4, 0), levels)
        assertEquals(6, ids.size)
        val late = resolve(p, t + 5_000)
        assertEquals(CompanionPose.Resting, late.pose)
        assertEquals(0, late.tapLevel)
        // A pat is its own reaction with no tap level.
        assertTrue(p.touch(CompanionTouch.Pat))
        assertEquals(CompanionPose.Patted, resolve(p, t + 5_000).pose)
    }

    @Test fun greetingOnceAfterAttach() {
        val p = attached()
        assertEquals(Playback.Hidden, resolve(p, t, context(playback = Playback.Hidden)).playback) // hidden keeps it
        val greeting = resolve(p, t)
        assertEquals(CompanionPose.Greeting, greeting.pose)
        assertEquals(t + 900, greeting.nextDeadline)
        assertEquals(greeting, resolve(p, t + 899))
        assertEquals(CompanionPose.Resting, resolve(p, t + 900).pose)
        p.attach(owner)
        assertEquals(CompanionPose.Resting, resolve(p, t + 1_000).pose)
        // No profile hides Pip.
        assertEquals(Playback.Hidden, presentation().resolve(context()).playback)
    }

    @Test fun savedEventCarriesNoAmount() {
        val fields = CompanionEvent::class.java.declaredFields.filterNot { it.isSynthetic || java.lang.reflect.Modifier.isStatic(it.modifiers) }
        assertEquals(setOf("profileID", "operationID", "kind", "committedAt"), fields.map { it.name }.toSet())
        assertEquals(listOf("Saved", "Reviewed", "FirstMealToday", "DayComplete", "PhotoAdded"), CompanionEvent.Kind.entries.map { it.name })
    }
    @Test fun welcomeBackOnceAfterADayAway() {
        val p = presentation().also { it.attach(owner, lastActiveAt = t - 86_400_000) }
        val welcome = resolve(p, t)
        assertEquals(CompanionPose.WelcomeBack, welcome.pose)
        assertEquals(t + 1_600, welcome.nextDeadline)
        assertEquals(CompanionPose.Resting, resolve(p, t + 1_600).pose)
        p.enterBackground()
        p.attach(owner, lastActiveAt = t)
        assertEquals(CompanionPose.Greeting, resolve(p, t + 2_000).pose)
    }

    @Test fun sameDayReturnGreets() {
        val p = presentation().also { it.attach(owner, lastActiveAt = t - 60_000) }
        assertEquals(CompanionPose.Greeting, resolve(p, t).pose)
    }

    @Test fun enterBackgroundGreetsAgain() {
        val p = attached()
        assertEquals(CompanionPose.Greeting, resolve(p, t).pose)
        assertEquals(CompanionPose.Resting, resolve(p, t + 900).pose)
        p.enterBackground()
        assertEquals(Playback.Hidden, resolve(p, t + 1_000).playback)
        p.attach(owner)
        assertEquals(CompanionPose.Greeting, resolve(p, t + 1_000).pose)
    }

    @Test fun habitAndReviewKindsPlayTheirPoses() {
        val p = attached()
        resolve(p, t + 900) // the greeting is spent
        now = t + 1_000
        p.receive(event(at = now, kind = CompanionEvent.Kind.Reviewed))
        val reviewed = resolve(p, now)
        assertEquals(CompanionPose.Reviewed, reviewed.pose)
        assertEquals(now + 650, reviewed.nextDeadline)
        now = t + 2_000
        p.receive(event(at = now, kind = CompanionEvent.Kind.FirstMealToday))
        val first = resolve(p, now)
        assertEquals(CompanionPose.FirstMealToday, first.pose)
        assertEquals(now + 1_000, first.nextDeadline)
    }

    @Test fun firstMealReplacesAPlayingSaved() {
        val p = attached()
        p.receive(event())
        assertEquals(CompanionPose.Saved, resolve(p, t).pose)
        now = t + 100
        p.receive(event(at = now, kind = CompanionEvent.Kind.FirstMealToday))
        assertEquals(CompanionPose.FirstMealToday, resolve(p, now).pose)
    }

    @Test fun staticPlaybackDropsAPendingMoment() {
        val p = attached()
        p.receive(event(kind = CompanionEvent.Kind.Reviewed))
        assertEquals(Playback.StaticPose, resolve(p, t, context(playback = Playback.StaticPose)).playback)
        assertEquals(CompanionPose.Resting, resolve(p, t + 100).pose)
    }

    @Test fun pendingMomentExpiresAfterTheLifetime() {
        val p = attached()
        resolve(p, t)
        resolve(p, t + 900) // the greeting is spent
        now = t + 1_000
        p.receive(event(at = now, kind = CompanionEvent.Kind.Reviewed))
        assertEquals(Playback.Hidden, resolve(p, now, context(playback = Playback.Hidden)).playback)
        assertEquals(CompanionPose.Resting, resolve(p, t + 1_000 + 10_001).pose)
    }

    @Test fun processingInterruptsWelcomeBack() {
        val p = presentation().also { it.attach(owner, lastActiveAt = t - 86_400_000) }
        assertEquals(CompanionPose.WelcomeBack, resolve(p, t).pose)
        assertEquals(CompanionPose.Thinking, resolve(p, t + 100, context(processing = true)).pose)
    }
}
