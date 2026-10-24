@file:UseSerializers(SwiftUUID::class)
@file:OptIn(ExperimentalSerializationApi::class)

package com.yakov103.mivu.diary

import java.io.FilterInputStream
import java.io.FilterOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.util.UUID
import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.Serializable
import kotlinx.serialization.UseSerializers
import kotlinx.serialization.json.decodeFromStream
import kotlinx.serialization.json.encodeToStream

// Port of ios/Mivu/Diary/DiaryArchive.swift: the "mivu-diary" envelope, versions 1-4, written as version 4.

private const val FORMAT = "mivu-diary"
private const val CURRENT_VERSION = 4
private const val MAX_ARCHIVE_BYTES = 350_000_000L

@Serializable
private data class Envelope(val format: String, val version: Int, val profileID: UUID, val snapshot: DiarySnapshot)

private class CappedInput(input: InputStream, private var left: Long) : FilterInputStream(input) {
    private fun take(n: Int) {
        if (n > 0) { left -= n; if (left < 0) throw DiaryError.InvalidData("archive size") }
    }
    override fun read(): Int = super.read().also { if (it >= 0) take(1) }
    override fun read(b: ByteArray, off: Int, len: Int): Int = super.read(b, off, len).also { take(it) }
}

private class CappedOutput(out: OutputStream, private var left: Long) : FilterOutputStream(out) {
    private fun take(n: Int) {
        left -= n
        if (left < 0) throw DiaryError.InvalidData("archive size")
    }
    override fun write(b: Int) { take(1); out.write(b) }
    override fun write(b: ByteArray, off: Int, len: Int) { take(len); out.write(b, off, len) }
}

object DiaryArchive {
    /** Validates, then streams the archive. Over the cap it throws mid-write, so callers must write to a temp file. */
    fun encode(snapshot: DiarySnapshot, out: OutputStream) = encode(snapshot, out, MAX_ARCHIVE_BYTES)

    internal fun encode(snapshot: DiarySnapshot, out: OutputStream, maxBytes: Long) {
        validateArchiveManifests(snapshot)
        SwiftJson.encodeToStream(Envelope(FORMAT, CURRENT_VERSION, snapshot.profile.id, snapshot), CappedOutput(out, maxBytes))
    }

    fun decode(input: InputStream, expectedProfileID: UUID? = null): DiarySnapshot =
        decode(input, expectedProfileID, MAX_ARCHIVE_BYTES)

    internal fun decode(input: InputStream, expectedProfileID: UUID?, maxBytes: Long): DiarySnapshot {
        val envelope = try {
            SwiftJson.decodeFromStream<Envelope>(CappedInput(input, maxBytes))
        } catch (e: DiaryError) {
            throw e
        } catch (e: Exception) { // SerializationException, IllegalArgumentException, truncated or empty input
            throw DiaryError.InvalidData(e.message ?: "archive")
        }
        if (envelope.format != FORMAT || envelope.version !in 1..CURRENT_VERSION) throw DiaryError.InvalidData("archive header")
        val snapshot = envelope.snapshot
        if (envelope.profileID != snapshot.profile.id) throw DiaryError.WrongOwner
        if (expectedProfileID != null && expectedProfileID != envelope.profileID) throw DiaryError.WrongOwner
        if (envelope.version < CURRENT_VERSION && snapshot.meals.any { m -> m.submissions.any { it.manualAcceptance != null } }) {
            throw DiaryError.InvalidData("manual acceptance needs version 4")
        }
        validateArchiveManifests(snapshot)
        return snapshot
    }
}
