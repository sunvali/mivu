@file:UseSerializers(SwiftUUID::class)
@file:OptIn(ExperimentalSerializationApi::class)

package com.yakov103.mivu.diary

import java.io.Closeable
import java.io.File
import java.io.FilterInputStream
import java.io.FilterOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.security.MessageDigest
import java.util.UUID
import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.UseSerializers
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.decodeFromStream
import kotlinx.serialization.json.encodeToStream
import kotlinx.serialization.modules.SerializersModule

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

/**
 * Archive photo bytes on disk, one file per distinct content. Snapshots decoded through it hold each photo's
 * 32-byte SHA-256 as a placeholder, so equal content compares equal; [close] deletes [dir].
 */
class PhotoSpool(val dir: File) : Closeable {
    private var total = 0L

    init { dir.mkdirs() }

    /** Checks the real length (the photo and archive limits of `validate`), writes the bytes, returns the placeholder. */
    fun put(bytes: ByteArray): ByteArray {
        if (bytes.size !in 1..10_000_000) throw DiaryError.InvalidData("photo bytes")
        total += bytes.size
        if (total > 250_000_000) throw DiaryError.InvalidData("photo total")
        val placeholder = MessageDigest.getInstance("SHA-256").digest(bytes)
        file(placeholder).takeIf { !it.exists() }?.writeBytes(bytes)
        return placeholder
    }

    fun bytes(placeholder: ByteArray): ByteArray = file(placeholder).readBytes()

    /** The real bytes' [fingerprint], as manifests record it. */
    fun fingerprint(placeholder: ByteArray): String = placeholder.hex()

    override fun close() { dir.deleteRecursively() }

    private fun file(placeholder: ByteArray) = File(dir, placeholder.hex())
}

private fun placeholderJson(data: PlaceholderData) = Json(SwiftJson) { serializersModule = SerializersModule { contextual(ByteArray::class, data) } }

object DiaryArchive {
    /** Validates, then streams the archive. Over the cap it throws mid-write, so callers must write to a temp file. */
    fun encode(snapshot: DiarySnapshot, out: OutputStream) = encode(snapshot, out, MAX_ARCHIVE_BYTES)

    /** As [encode] for a snapshot whose photo data are placeholders: [source] gives each one's bytes as it is written. */
    internal fun encode(snapshot: DiarySnapshot, out: OutputStream, source: (ByteArray) -> ByteArray) =
        encode(snapshot, out, MAX_ARCHIVE_BYTES, placeholderJson(PlaceholderData(source)))

    internal fun encode(snapshot: DiarySnapshot, out: OutputStream, maxBytes: Long, json: Json = SwiftJson) {
        validateArchiveManifests(snapshot)
        try {
            json.encodeToStream(Envelope(FORMAT, CURRENT_VERSION, snapshot.profile.id, snapshot), CappedOutput(out, maxBytes))
        } catch (e: SerializationException) { // the encoder wraps what a photo source throws
            throw e.cause as? DiaryError ?: e
        }
    }

    fun decode(input: InputStream, expectedProfileID: UUID? = null): DiarySnapshot =
        decode(input, expectedProfileID, MAX_ARCHIVE_BYTES)

    /** As [decode], with each photo's bytes written to [spool] as they are read: photo data are its placeholders. */
    fun decode(input: InputStream, spool: PhotoSpool, expectedProfileID: UUID? = null): DiarySnapshot =
        decode(input, expectedProfileID, MAX_ARCHIVE_BYTES, placeholderJson(PlaceholderData(spool::bytes, spool::put)))

    internal fun decode(input: InputStream, expectedProfileID: UUID?, maxBytes: Long, json: Json = SwiftJson): DiarySnapshot {
        val envelope = try {
            json.decodeFromStream<Envelope>(CappedInput(input, maxBytes))
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
