package com.yakov103.mivu.pip

import com.yakov103.mivu.pip.MotionPolicy.Playback
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.UUID
import kotlin.math.PI
import kotlin.random.Random

@OptIn(ExperimentalCoroutinesApi::class)
class CompanionRuntimeTest {
    private val loader = javaClass.classLoader!!
    private val scene = PipRigScene(PipRigAsset.load(loader.getResource("pip/pip-rig.json")!!.readBytes()))
    private val library = PipGestureLibrary.load(loader.getResource("pip/gestures.json")!!.readText())

    private fun TestScope.runtime() = CompanionRuntime(library, scene, backgroundScope, { testScheduler.currentTime }, Random(7))

    private fun output(pose: CompanionPose, playback: Playback = Playback.Animated, reaction: UUID? = null, typing: Double = 0.0) =
        CompanionOutput(pose, playback, reaction, typingProgress = typing)

    @Test fun staticPolicyAppliesStillPoseWithZeroJobs() = runTest {
        val rt = runtime()
        rt.apply(output(CompanionPose.Thinking, Playback.StaticPose), CompanionSurface.Today)
        runCurrent()
        assertEquals(0, rt.activeJobs)
        val still = library.stillPose(PipMoment.Thinking).copy(set = PipPose.BodySet.standing)
        assertEquals(still, rt.motion.pose)
        advanceTimeBy(30_000)
        assertEquals(0, rt.activeJobs)
        assertEquals(still, rt.motion.pose)
        assertEquals(0, rt.idleBeats)
    }

    @Test fun policyFlipMidGestureLeavesZeroJobs() = runTest {
        val rt = runtime()
        val greeting = output(CompanionPose.Greeting, reaction = UUID.randomUUID())
        rt.apply(greeting, CompanionSurface.Today)
        advanceTimeBy(300)
        assertTrue(rt.activeJobs > 0)
        rt.apply(greeting.copy(playback = Playback.StaticPose), CompanionSurface.Today)
        assertEquals(0, rt.activeJobs)
        val pose = rt.motion.pose
        advanceTimeBy(30_000)
        assertEquals(0, rt.activeJobs)
        assertEquals(pose, rt.motion.pose)
    }

    @Test fun hiddenStopsIdleLoop() = runTest {
        val rt = runtime()
        rt.apply(output(CompanionPose.Resting), CompanionSurface.Today)
        advanceTimeBy(30_000)
        assertTrue(rt.idleBeats > 0)
        rt.apply(output(CompanionPose.Resting, Playback.Hidden), CompanionSurface.Today)
        val beats = rt.idleBeats
        assertEquals(0, rt.activeJobs)
        advanceTimeBy(120_000)
        assertEquals(beats, rt.idleBeats)
        assertEquals(0, rt.activeJobs)
        assertEquals(PipPose(), rt.motion.pose)
    }

    @Test fun coachRestsSeated() = runTest {
        val rt = runtime()
        rt.apply(output(CompanionPose.Resting, Playback.StaticPose), CompanionSurface.Coach)
        assertEquals(PipPose(set = PipPose.BodySet.seated), rt.motion.pose)
        rt.apply(output(CompanionPose.Resting), CompanionSurface.Coach)
        advanceTimeBy(1_000)
        assertEquals(PipPose.BodySet.seated, rt.motion.pose.set)
        rt.stop()
        assertEquals(0, rt.activeJobs)
    }

    @Test fun typingHoldsFirstAttentiveKeyLookingDown() = runTest {
        val rt = runtime()
        rt.apply(output(CompanionPose.Attentive, typing = 0.5), CompanionSurface.Today)
        advanceTimeBy(5_000)
        val first = library.named("attentive").keys.first().second
        val head = (first.joints["head"] ?: PipPose.Joint()).copy(rotation = (14 * PI / 180).toFloat())
        val x = -0.3f + 1.3f * 0.5f
        val expected = first.copy(joints = first.joints + ("head" to head), gazeX = x, gazeY = 0.8f, headTurn = 1 + 0.35f * x)
        assertEquals(expected, rt.motion.pose)
        // A longer draft moves only the eyes; nothing restarts.
        rt.apply(output(CompanionPose.Attentive, typing = 1.0), CompanionSurface.Today)
        advanceTimeBy(1_000)
        assertEquals(1f, rt.motion.pose.gazeX, 1e-6f)
        assertEquals(0.8f, rt.motion.pose.gazeY, 1e-6f)
    }

    @Test fun idleBeatWaitsForGesture() = runTest {
        val rt = runtime()
        rt.apply(output(CompanionPose.Thinking), CompanionSurface.Today) // a looping gesture
        advanceTimeBy(60_000)
        assertEquals(0, rt.idleBeats)
        assertTrue(rt.activeJobs <= library.named("thinking").keys.size + 2)
        rt.apply(output(CompanionPose.Resting), CompanionSurface.Today)
        advanceTimeBy(30_000)
        assertTrue(rt.idleBeats > 0)
    }
}
