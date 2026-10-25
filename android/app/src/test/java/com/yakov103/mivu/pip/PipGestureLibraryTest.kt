package com.yakov103.mivu.pip

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Ported from iOS `PipGestureTests`, run over the iOS-exported `fixtures/pip/gestures.json`. */
class PipGestureLibraryTest {
    private val json = javaClass.classLoader!!.getResource("pip/gestures.json")!!.readText()
    private val library = PipGestureLibrary.load(json)
    private val all = library.gestures
    private val setChangers = setOf("curl-up", "wake")

    /** Fixture keys such as `greeting:7`, `tapped:4`, `presenting:true` and `saved`. */
    private fun moment(key: String): PipMoment {
        val name = key.substringBefore(':')
        val arg = key.substringAfter(':', "")
        return when (name) {
            "greeting" -> PipMoment.Greeting(arg.toInt())
            "tapped" -> PipMoment.Tapped(arg.toInt())
            "progressTap" -> PipMoment.ProgressTap(arg.toInt())
            "presenting" -> PipMoment.Presenting(arg.toBooleanStrict())
            "progressEntrance" -> PipMoment.ProgressEntrance(arg.toBooleanStrict())
            "welcomeBack" -> PipMoment.WelcomeBack
            "attentive" -> PipMoment.Attentive
            "submitted" -> PipMoment.Submitted
            "thinking" -> PipMoment.Thinking
            "saved" -> PipMoment.Saved
            "reviewed" -> PipMoment.Reviewed
            "recovery" -> PipMoment.Recovery
            "firstMealToday" -> PipMoment.FirstMealToday
            "dayComplete" -> PipMoment.DayComplete
            "curious" -> PipMoment.Curious
            "patted" -> PipMoment.Patted
            "earTwitch" -> PipMoment.EarTwitch
            "progressRange" -> PipMoment.ProgressRange
            else -> error("unknown moment $key")
        }
    }

    private val moments: Map<String, String> = Json.parseToJsonElement(json).jsonObject.getValue("moments").jsonObject
        .mapValues { it.value.jsonPrimitive.content }

    @Test fun everyOneShotEndsAtRestWithinTwoSeconds() {
        assertEquals(39, all.size)
        assertEquals(all.size, all.map { it.name }.toSet().size)
        for (gesture in all) {
            assertTrue("${gesture.name} has no keys", gesture.keys.isNotEmpty())
            if (gesture.loops) continue
            var end = PipPose(set = gesture.endSet ?: PipPose.BodySet.standing)
            if (gesture.name == "curl-up" || gesture.name == "curled-ear-flick") end = end.copy(eyes = PipPose.EyeShape.closedSleepy)
            assertEquals("${gesture.name} must end at rest", end, gesture.keys.last().second)
            assertTrue("${gesture.name} lasts ${gesture.duration}", gesture.duration <= 2.0)
            assertEquals(gesture.name, gesture.keys.map { it.first }.sorted(), gesture.keys.map { it.first })
        }
    }

    @Test fun onlyCurlUpAndWakeChangeBodySet() {
        assertEquals(setChangers, all.filter { it.endSet != null }.map { it.name }.toSet())
        assertEquals(PipPose.BodySet.standing, library.named("wake").endSet)
        assertEquals(PipPose.BodySet.curled, library.gesture(PipIdleScheduler.Beat.CurlUp, curled = false)?.endSet)
        for (gesture in all) if (gesture.name !in setChangers) {
            assertTrue(gesture.name, gesture.keys.all { it.second.set == PipPose.BodySet.standing })
        }
        assertEquals("curled-ear-flick", library.gesture(PipIdleScheduler.Beat.EarFlick, curled = true)?.name)
        assertEquals("idle-ear-flick", library.gesture(PipIdleScheduler.Beat.EarFlick, curled = false)?.name)
        assertNull(library.gesture(PipIdleScheduler.Beat.Glance(0.1, 0.2), curled = false))
        assertNull(library.gesture(PipIdleScheduler.Beat.Blink, curled = false))
    }

    @Test fun squashStaysWithinTenPercent() {
        for (gesture in all) for ((_, pose) in gesture.keys) for ((name, joint) in pose.joints) {
            assertTrue("${gesture.name} $name", joint.scaleX in 0.9f..1.1f && joint.scaleY in 0.9f..1.1f)
            if (name.startsWith("foot-")) assertTrue("${gesture.name} $name below ground", joint.offsetY <= 0f)
        }
    }

    @Test fun everyJointNamesARigPart() {
        val asset = PipRigAsset.load(javaClass.classLoader!!.getResource("pip/pip-rig.json")!!.readBytes())
        // Plain names address the standing (and shared) parts; a full id like `arm-r@seated` addresses one set's part.
        val known = asset.parts.filter { it.set == null || it.set == "standing" }.map { it.name }.toSet() + asset.parts.map { it.id }
        for (gesture in all) for ((_, pose) in gesture.keys) for (name in pose.joints.keys) {
            assertTrue("${gesture.name} moves unknown joint $name", name in known)
        }
    }

    @Test fun momentMappingMatchesIosTable() {
        assertEquals(24 + 5 + 6 + 4 + 13, moments.size)
        for ((key, name) in moments) assertEquals(key, name, library.gesture(moment(key)).name)
        // Past the table: tap levels clamp and Progress taps wrap, as in the iOS switch.
        assertEquals("shake-off", library.gesture(PipMoment.Tapped(9)).name)
        assertEquals("tap-giggle", library.gesture(PipMoment.Tapped(-1)).name)
        assertEquals(moments["progressTap:0"], library.gesture(PipMoment.ProgressTap(6)).name)
        assertTrue(library.loop(PipMoment.Thinking)!!.loops)
        assertNull(library.loop(PipMoment.Saved))
    }

    @Test fun stillPoseIsKeyBeforeSettle() {
        for (key in moments.keys) {
            val keys = library.gesture(moment(key)).keys
            assertEquals(key, if (keys.size > 1) keys[keys.size - 2].second else PipPose(), library.stillPose(moment(key)))
        }
        assertEquals(0.28, library.gesture(PipMoment.Saved).keys.first { it.second == library.stillPose(PipMoment.Saved) }.first, 1e-9)
    }

    @Test fun durationsCoverGestures() {
        val reactions = listOf(
            MivuMotion.greeting to (0..23).map { PipMoment.Greeting(it) },
            MivuMotion.submitted to listOf(PipMoment.Submitted),
            MivuMotion.saved to listOf(PipMoment.Saved),
            MivuMotion.reviewed to listOf(PipMoment.Reviewed),
            MivuMotion.firstMealToday to listOf(PipMoment.FirstMealToday),
            MivuMotion.dayComplete to listOf(PipMoment.DayComplete),
            MivuMotion.curious to listOf(PipMoment.Curious),
            MivuMotion.tapped to (0..4).map { PipMoment.Tapped(it) },
            MivuMotion.patted to listOf(PipMoment.Patted),
            MivuMotion.welcomeBack to listOf(PipMoment.WelcomeBack),
            MivuMotion.progressEntrance to listOf(PipMoment.ProgressEntrance(true), PipMoment.ProgressEntrance(false)),
            MivuMotion.progressRange to listOf(PipMoment.ProgressRange),
            MivuMotion.progressTap to (0..5).map { PipMoment.ProgressTap(it) },
        )
        for ((lifetime, list) in reactions) for (m in list) {
            val duration = library.gesture(m).duration
            assertTrue("$m: $lifetime vs $duration", lifetime >= duration - 1e-9 && lifetime - duration <= 0.3 + 1e-9)
        }
    }

    @Test fun heartsAlwaysPopToScaleOne() {
        for (gesture in all) for ((_, pose) in gesture.keys) for ((name, joint) in pose.joints) {
            if (name.startsWith("heart-")) assertTrue("${gesture.name} $name", joint.scaleX == 1f && joint.scaleY == 1f)
        }
    }
}
