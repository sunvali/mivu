package com.yakov103.mivu.pip

import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.sqrt

@OptIn(ExperimentalCoroutinesApi::class)
class PipMotionTest {
    private val scene = PipRigScene(PipRigAsset.load(javaClass.classLoader!!.getResource("pip/pip-rig.json")!!.readBytes()))
    private val motion = PipMotion(scene)
    private fun ms(value: Long) = value * 1_000_000
    private fun nod(degrees: Double) = PipPose(joints = mapOf("head" to PipPose.Joint(rotation = (degrees * PI / 180).toFloat())))
    private fun rotation(id: String, atMs: Long) = motion.sample(ms(atMs)).joint(id).rotation

    @Test fun springUsesCoreAnimationConstants() {
        val body = PipMotion.spring(0.45, follower = false, saccade = false)
        assertEquals(196f, body.stiffness, 1e-3f)
        assertEquals(0.68f, body.dampingRatio, 1e-6f)
        val follower = PipMotion.spring(0.45, follower = true, saccade = false)
        assertEquals(196f * 0.6f, follower.stiffness, 1e-3f) // ω 14√0.6
        assertEquals(0.5f, follower.dampingRatio, 1e-6f)
        // Short keys raise ω to land the overshoot near the key time, up to 60; gaze parts saccade at 110.
        assertEquals((3.76 / 0.1).let { it * it }.toFloat(), PipMotion.spring(0.1, follower = false, saccade = false).stiffness, 1e-2f)
        assertEquals(3600f, PipMotion.spring(0.01, follower = false, saccade = false).stiffness, 1e-2f)
        assertEquals(110f * 110f, PipMotion.spring(0.45, follower = false, saccade = true).stiffness, 1e-2f)
        assertEquals(sqrt(196f), sqrt(body.stiffness), 1e-4f)
    }

    @Test fun followerStartsSixtyMsLate() {
        motion.apply(PipPose())
        val target = PipPose(joints = mapOf("head" to PipPose.Joint(rotation = 0.2f), "ear-l" to PipPose.Joint(rotation = 0.3f)))
        motion.transition(target, 0.45, ms(0))
        assertNotEquals(0f, rotation("head@right", 30))
        assertEquals(0f, rotation("ear-l@right", 55), 0f)
        assertNotEquals(0f, rotation("ear-l@right", 90))
        assertEquals(0.3f, rotation("ear-l@right", 3_000), 1e-4f)
        assertEquals(0.2f, rotation("head@right", 3_000), 1e-4f)
    }

    @Test fun retargetStartsFromSampledValue() {
        motion.apply(PipPose())
        motion.transition(nod(10.0), 0.45, ms(0))
        val before = rotation("head@right", 100)
        val slightlyBefore = rotation("head@right", 99)
        motion.transition(nod(-10.0), 0.45, ms(100))
        assertEquals(before, rotation("head@right", 100), 1e-6f)
        // The velocity carries over: the next millisecond continues the old direction.
        val after = rotation("head@right", 101)
        assertTrue("no kink: ${slightlyBefore} ${before} ${after}", abs((after - before) - (before - slightlyBefore)) < 2e-3f)
        assertEquals(nod(-10.0).joints.getValue("head").rotation, rotation("head@right", 3_000), 1e-4f)
    }

    @Test fun hiddenPartSnaps() {
        motion.apply(PipPose())
        assertFalse(motion.sample(ms(0)).isVisible("body@seated"))
        val seated = PipPose(set = PipPose.BodySet.seated, joints = mapOf("body" to PipPose.Joint(offsetY = -10f)))
        motion.transition(seated, 0.45, ms(0))
        val frame = motion.sample(ms(1))
        assertTrue(frame.isVisible("body@seated"))
        assertEquals(-10f, frame.joint("body@seated").offsetY, 0f)
    }

    @Test fun blinkShowsHalfShutHalfOpenOver160ms() {
        motion.apply(PipPose())
        motion.blink(double = false, nowNanos = ms(0))
        fun shown(atMs: Long) = motion.sample(ms(atMs)).let { f ->
            listOf("open", "half", "closedSleepy").filter { f.isVisible("eye-l.$it@right") && f.isVisible("eye-r.$it@right") }
        }
        assertEquals(listOf("half"), shown(20))
        assertEquals(listOf("closedSleepy"), shown(80))
        assertEquals(listOf("half"), shown(130))
        assertEquals(listOf("open"), shown(155))
        assertEquals(listOf("open"), shown(170))
        motion.blink(double = true, nowNanos = ms(1_000))
        assertEquals(listOf("closedSleepy"), shown(1_380))
        assertEquals(listOf("open"), shown(1_470))
    }

    @Test fun breathingAddsTwoPercentAtPeak() {
        motion.apply(PipPose())
        motion.setBreathing(true)
        assertEquals(0f, motion.sample(ms(1_000)).scaleYAdd("head@right"), 1e-6f)
        assertEquals(0.02f, motion.sample(ms(5_500)).scaleYAdd("head@right"), 1e-6f)
        assertEquals(0.02f, motion.sample(ms(5_500)).scaleYAdd("chest"), 1e-6f)
        assertEquals(0f, motion.sample(ms(10_000)).scaleYAdd("head@right"), 1e-6f)
        assertEquals(0f, motion.sample(ms(5_500)).scaleYAdd("body"), 0f)
        motion.setBreathing(false)
        assertEquals(0f, motion.sample(ms(12_250)).scaleYAdd("head@right"), 0f)
    }

    @Test fun sampleIsAllocationFree() {
        motion.apply(PipPose())
        motion.setBreathing(true)
        motion.transition(PipPose(eyes = PipPose.EyeShape.wide, gazeX = 0.5f, hearts = 2, joints = nod(8.0).joints), 0.45, ms(0))
        motion.blink(double = true, nowNanos = ms(0))
        val threads = java.lang.management.ManagementFactory.getThreadMXBean() as com.sun.management.ThreadMXBean
        val id = Thread.currentThread().id
        for (t in 0L until 200) motion.sample(ms(t)) // warm up
        val before = threads.getThreadAllocatedBytes(id)
        for (t in 200L until 400) motion.sample(ms(t)) // mid-spring, fade and double blink
        val perFrame = (threads.getThreadAllocatedBytes(id) - before) / 200
        println("PipMotion.sample: $perFrame bytes per frame")
        assertTrue("$perFrame bytes per frame", perFrame < 64)
    }

    // MARK: Player

    private val keys = PipGesture("test", listOf(0.1 to nod(5.0), 0.3 to nod(-5.0), 0.5 to PipPose()), loops = false, endSet = null)
    private fun TestScope.player() = PipPlayer(backgroundScope, motion) { testScheduler.currentTime * 1_000_000 }
    private fun headTarget() = motion.pose.joints["head"]?.rotation ?: 0f

    @Test fun playLaunchesKeysAtPreviousKeyTime() = runTest {
        val player = player()
        var done: Boolean? = null
        player.play(keys) { done = it }
        runCurrent()
        assertEquals(nod(5.0).joints.getValue("head").rotation, headTarget())
        advanceTimeBy(99); runCurrent()
        assertEquals(nod(5.0).joints.getValue("head").rotation, headTarget())
        advanceTimeBy(1); runCurrent()
        assertEquals(nod(-5.0).joints.getValue("head").rotation, headTarget())
        advanceTimeBy(200); runCurrent()
        assertEquals(0f, headTarget())
        assertEquals(null, done)
        advanceTimeBy(200); runCurrent()
        assertEquals(true, done)
        assertEquals(0, player.pendingJobs)
    }

    @Test fun newPlayInterruptsAndReportsFalse() = runTest {
        val player = player()
        val results = mutableListOf<Pair<String, Boolean>>()
        player.play(keys) { results += "first" to it }
        advanceTimeBy(150); runCurrent()
        player.play(keys.copy(name = "second")) { results += "second" to it }
        assertEquals(listOf("first" to false), results)
        advanceTimeBy(600); runCurrent()
        assertEquals(listOf("first" to false, "second" to true), results)
    }

    @Test fun loopRepeatsFromFirstKey() = runTest {
        val player = player()
        val loop = PipGesture("loop", listOf(0.2 to nod(5.0), 0.4 to nod(-5.0)), loops = true, endSet = null)
        var done: Boolean? = null
        player.play(loop) { done = it }
        runCurrent()
        assertEquals(nod(5.0).joints.getValue("head").rotation, headTarget())
        advanceTimeBy(200); runCurrent()
        assertEquals(nod(-5.0).joints.getValue("head").rotation, headTarget())
        advanceTimeBy(200); runCurrent()
        assertEquals(nod(5.0).joints.getValue("head").rotation, headTarget())
        advanceTimeBy(4_000); runCurrent()
        assertEquals(null, done)
        assertTrue(player.pendingJobs in 1..3) // bounded by one pass of the keys
    }

    @Test fun stopLeavesZeroPendingJobs() = runTest {
        val player = player()
        var done: Boolean? = null
        player.play(keys) { done = it }
        player.look(0.5f, 0.2f)
        assertTrue(player.pendingJobs > 0)
        player.stop()
        assertEquals(0, player.pendingJobs)
        assertEquals(false, done)
        advanceTimeBy(1_000); runCurrent()
        assertEquals(false, done)
    }

    @Test fun headTurnEyesLeadAndSwapLandsInBlink() = runTest {
        val player = player()
        motion.apply(PipPose())
        player.play(PipGesture("turn", listOf(0.3 to PipPose(headTurn = 0f), 0.6 to PipPose()), loops = false, endSet = null)) {}
        runCurrent()
        assertEquals(1f, motion.pose.headTurn) // eyes go first
        assertEquals(-1f, motion.pose.gazeX)
        assertEquals(listOf("half"), listOf("open", "half").filter { motion.sample(ms(20)).isVisible("eye-l.$it@right") })
        advanceTimeBy(80); runCurrent()
        assertEquals(0f, motion.pose.headTurn)
    }
}
