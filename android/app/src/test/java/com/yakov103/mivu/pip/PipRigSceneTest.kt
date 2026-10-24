package com.yakov103.mivu.pip

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.PI

class PipRigSceneTest {
    private val asset = PipRigAsset.load(javaClass.classLoader!!.getResource("pip/pip-rig.json")!!.readBytes())
    /** Every part pretends to fill (0,0)-(20,10), so reaches are easy to predict. */
    private val scene = PipRigScene(asset) { floatArrayOf(0f, 0f, 20f, 10f) }
    private fun drawn(pose: PipPose) = scene.draw(scene.resolve(pose))
    private fun part(id: String) = asset.parts.first { it.id == id }

    @Test fun restSeatedShowsOnlySeatedSetAndRightView() {
        val ids = drawn(PipPose(set = PipPose.BodySet.seated)).map { it.partID }
        assertTrue("body@seated" in ids && "head@right" in ids && "mouth.closedSmile@right" in ids)
        assertFalse("mouth.smallOpen@right" in ids)
        ids.map(::part).forEach {
            assertTrue(it.id, it.set == null || it.set == "seated")
            assertTrue(it.id, it.view == null || it.view == "right")
        }
    }

    @Test fun drawOrderFollowsTreeThenZ() {
        val ids = drawn(PipPose()).map { it.partID }
        // ear-l@right (z 101) hangs under head@right (z 109) and is drawn before its parent's shape.
        assertTrue(ids.indexOf("ear-l@right") < ids.indexOf("head@right"))
        assertTrue(ids.indexOf("head@right") < ids.indexOf("muzzle@right"))
        assertTrue(ids.indexOf("body") < ids.indexOf("head@right"))
    }

    @Test fun jointMatrixRotatesScalesThenOffsets() {
        val m = jointMatrix(10f, 10f, PipPose.Joint(rotation = (PI / 2).toFloat(), offsetX = 5f, offsetY = 0f, scaleX = 2f, scaleY = 1f))
        assertArrayEquals(floatArrayOf(15f, 11f), mapPoint(m, 11f, 10f), 1e-4f)
    }

    @Test fun headTurnPicksView() {
        fun views(turn: Float) = drawn(PipPose(headTurn = turn)).mapNotNull { part(it.partID).view }.toSet()
        assertEquals(setOf("front"), views(0.2f))
        assertEquals(setOf("right"), views(0.5f))
        assertEquals(setOf("left"), views(-0.5f))
    }

    @Test fun gazeMovesIrisByReachAndClips() {
        // Gaze (2, 0) clamps to (1, 0): iris travels 0.3 × white width = 6; glint counter-shifts 0.3 × 6.
        val resolved = scene.resolve(PipPose(gazeX = 2f))
        assertEquals(6f, resolved.joints.getValue("iris-l@right").offsetX, 1e-4f)
        assertEquals(0f, resolved.joints.getValue("iris-l@right").offsetY, 1e-4f)
        assertEquals(-1.8f, resolved.joints.getValue("glint-l@right").offsetX, 1e-4f)
        val down = scene.resolve(PipPose(gazeY = 1f)).joints.getValue("iris-l@right")
        assertEquals(4f, down.offsetY, 1e-4f) // 0.4 × white height

        val draws = scene.draw(resolved)
        val iris = draws.first { it.partID == "iris-l@right" }
        assertEquals("eye-l@right", iris.clip!!.partID)
        assertEquals("eye-l@right", draws.first { it.partID == "pupil-l@right" }.clip!!.partID)
        assertNull(draws.first { it.partID == "eye-l@right" }.clip)
    }

    @Test fun blushAndHeartsUseAlpha() {
        val rest = scene.resolve(PipPose())
        assertEquals(0f, rest.alpha.getValue("cheek-blush-l@right"))
        val happy = scene.resolve(PipPose(blush = true, hearts = 2))
        assertEquals(1f, happy.alpha.getValue("cheek-blush-l@right"))
        assertEquals(1f, happy.alpha.getValue("heart-2"))
        assertEquals(0f, happy.alpha.getValue("heart-3"))
        val ids = scene.draw(happy).map { it.partID }
        assertTrue("heart-2" in ids && "cheek-blush-r@right" in ids)
        assertFalse("heart-3" in ids)
    }

    @Test fun headMountFollowsActiveBody() {
        fun head(pose: PipPose) = scene.draw(scene.resolve(pose)).first { it.partID == "head@right" }.matrix
        assertArrayEquals(floatArrayOf(.97f, 0f, 0f, .97f, 138.8f, 3.6f), head(PipPose()), 1e-3f)
        val seated = PipPose(set = PipPose.BodySet.seated, joints = mapOf("body" to PipPose.Joint(offsetX = 10f)))
        assertArrayEquals(floatArrayOf(.97f, 0f, 0f, .97f, 26.5f, 5.8f), head(seated), 1e-3f)
    }
}
