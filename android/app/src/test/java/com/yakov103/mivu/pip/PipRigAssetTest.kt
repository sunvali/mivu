package com.yakov103.mivu.pip

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class PipRigAssetTest {
    private val shipped = javaClass.classLoader!!.getResource("pip/pip-rig.json")!!.readBytes()

    private fun edited(edit: (MutableMap<String, kotlinx.serialization.json.JsonElement>) -> Unit): ByteArray {
        val root = Json.parseToJsonElement(shipped.decodeToString()).jsonObject.toMutableMap()
        edit(root)
        return JsonObject(root).toString().encodeToByteArray()
    }

    @Test fun shippedRigLoads() {
        val asset = PipRigAsset.load(shipped)
        assertEquals(2, asset.version)
        assertEquals(listOf(37.3f, 29.2f, 277.8f, 288.8f), asset.frames["coach"])
        asset.parts.forEach { parsePath(it.path) }
        assertEquals("head", asset.parts.first { it.id == "head@right" }.name)
    }

    @Test fun oversizeRejected() {
        assertThrows(PipRigError.TooLarge::class.java) { PipRigAsset.load(ByteArray(1_048_577)) }
    }

    @Test fun wrongVersionRejected() {
        val bytes = edited { it["version"] = JsonPrimitive(3) }
        assertThrows(PipRigError.Version::class.java) { PipRigAsset.load(bytes) }
    }

    @Test fun missingHeadViewRejected() {
        val bytes = edited { root ->
            root["parts"] = JsonArray(root["parts"]!!.jsonArray.filter {
                it.jsonObject["id"]!!.jsonPrimitive.content != "mouth.closedSmile@left"
            })
        }
        val error = assertThrows(PipRigError.MissingPart::class.java) { PipRigAsset.load(bytes) }
        assertEquals("mouth.closedSmile@left", error.id)
    }

    @Test fun relativePathRejected() {
        assertThrows(PipRigError.BadPath::class.java) { parsePath("M 0 0 l 1 1") }
    }

    @Test fun pathParsesEveryAbsoluteCommand() {
        assertEquals(
            listOf(PathOp.MoveTo(0f, 0f), PathOp.LineTo(1f, -2.5f), PathOp.CubicTo(1f, 2f, 3f, 4f, 5f, 6f),
                PathOp.QuadTo(1f, 1f, .5f, 2f), PathOp.Close),
            parsePath("M 0 0 L 1,-2.5\nC 1 2 3 4 5 6\tQ 1 1 .5 2 Z"),
        )
    }

    @Test fun boundsFollowTheCurveNotItsControlPoints() {
        // A unit-ish bump whose control points reach y = -4 but whose curve peaks at y = -3.
        val b = pathBounds(parsePath("M 0 0 C 0 -4 4 -4 4 0 Q 6 2 8 0 Z"))
        assertArrayEquals(floatArrayOf(0f, -3f, 8f, 1f), b, 1e-4f)
    }
}
