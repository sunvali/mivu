package com.yakov103.mivu.diary

import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.util.UUID
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class DiaryArchiveTest {
    private fun fixture(name: String) = javaClass.classLoader!!.getResource("archive/$name")!!.readText()
    private fun decode(text: String, owner: UUID? = null) = DiaryArchive.decode(text.byteInputStream(), owner)
    private val full = fixture("ios-v4-full.json")

    private fun edited(text: String, key: String, value: JsonPrimitive) =
        JsonObject(SwiftJson.parseToJsonElement(text).jsonObject + (key to value)).toString()

    private inline fun <reified E : Throwable> throws(block: () -> Unit) {
        try { block(); fail("expected ${E::class.simpleName}") } catch (e: Throwable) { if (e !is E) throw e }
    }

    @Test fun allIosFixturesDecode() {
        listOf("ios-v1.json", "ios-v2.json", "ios-v3.json", "ios-v4-full.json").forEach { decode(fixture(it)) }
    }

    @Test fun manualAcceptanceNeedsVersion4() {
        for (v in 1..3) throws<DiaryError.InvalidData> { decode(edited(full, "version", JsonPrimitive(v))) }
    }

    @Test fun badFormatOrVersionIsInvalid() {
        throws<DiaryError.InvalidData> { decode(edited(full, "format", JsonPrimitive("other"))) }
        throws<DiaryError.InvalidData> { decode(edited(full, "version", JsonPrimitive(5))) }
        throws<DiaryError.InvalidData> { decode("not json") }
        throws<DiaryError.InvalidData> { decode("") }
    }

    @Test fun ownerMismatchIsWrongOwner() {
        throws<DiaryError.WrongOwner> { decode(edited(full, "profileID", JsonPrimitive(UUID.randomUUID().toString().uppercase()))) }
        throws<DiaryError.WrongOwner> { decode(full, UUID.randomUUID()) }
        val snap = decode(full)
        assertEquals(snap, decode(full, snap.profile.id))
    }

    @Test fun oversizeStreamIsNotReadPastTheCap() {
        var served = 0L
        val endless = object : InputStream() {
            override fun read() = ' '.code.also { served++ }
            override fun read(b: ByteArray, off: Int, len: Int): Int { b.fill(' '.code.toByte(), off, off + len); served += len; return len }
        }
        throws<DiaryError.InvalidData> { DiaryArchive.decode(endless, null, maxBytes = 1_000_000) }
        assertTrue("served $served", served <= 1_000_000 + 65_536)
        throws<DiaryError.InvalidData> { DiaryArchive.decode(full.byteInputStream(), null, maxBytes = 1000) }
    }

    @Test fun encodeWritesVersion4AndRoundTrips() {
        val snap = decode(full)
        val out = ByteArrayOutputStream().also { DiaryArchive.encode(snap, it) }
        assertTrue(out.toString().contains("\"version\":4"))
        assertEquals(snap, DiaryArchive.decode(out.toByteArray().inputStream(), snap.profile.id))
    }

    @Test fun encodeOverCapFails() {
        throws<DiaryError.InvalidData> { DiaryArchive.encode(decode(full), ByteArrayOutputStream(), maxBytes = 1000) }
    }
}
