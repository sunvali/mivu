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

    // A crafted 30 MB string (photo data or text) is refused at the base64 size of the 10,000,000-byte photo cap, before
    // the decoder holds it as one String.
    @Test fun oversizedStringIsNotReadPastTheTokenCap() {
        val (head, tail) = full.split("\"AQID\"", limit = 2)
        var served = 0L
        val huge = object : InputStream() {
            var left = 30_000_000
            override fun read() = if (left-- > 0) 'A'.code.also { served++ } else -1
            override fun read(b: ByteArray, off: Int, len: Int): Int {
                if (left <= 0) return -1
                val n = minOf(len, left); b.fill('A'.code.toByte(), off, off + n); left -= n; served += n; return n
            }
        }
        val input = java.io.SequenceInputStream(java.util.Collections.enumeration(listOf(
            (head + "\"").byteInputStream(), huge, ("\"" + tail).byteInputStream())))
        throws<DiaryError.InvalidData> { DiaryArchive.decode(input) }
        assertTrue("served $served", served <= 13_333_336 + 65_536)
    }

    @Test fun encodeWritesVersion4AndRoundTrips() {
        val snap = decode(full)
        val out = ByteArrayOutputStream().also { DiaryArchive.encode(snap, it) }
        assertTrue(out.toString().contains("\"version\":4"))
        assertEquals(snap, DiaryArchive.decode(out.toByteArray().inputStream(), snap.profile.id))
    }

    private fun withReason(reason: String) = decode(full).let { s ->
        s.copy(coachTurns = listOf(s.coachTurns[0].copy(failureReason = reason)) + s.coachTurns.drop(1))
    }

    @Test fun failureReasonSurvivesReexport() {
        val snap = withReason("CoachError.InvalidArguments")
        val first = ByteArrayOutputStream().also { DiaryArchive.encode(snap, it) }.toByteArray()
        val again = DiaryArchive.decode(first.inputStream(), snap.profile.id)
        assertEquals("CoachError.InvalidArguments", again.coachTurns[0].failureReason)
        val second = ByteArrayOutputStream().also { DiaryArchive.encode(again, it) }.toByteArray()
        assertTrue(first.contentEquals(second))
    }

    @Test fun oversizedFailureReasonIsInvalid() {
        withReason("x".repeat(200)).validate()
        throws<DiaryError.InvalidData> { withReason("x".repeat(201)).validate() }
    }

    @Test fun encodeOverCapFails() {
        throws<DiaryError.InvalidData> { DiaryArchive.encode(decode(full), ByteArrayOutputStream(), maxBytes = 1000) }
    }
}
