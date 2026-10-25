package com.yakov103.mivu.diary

import java.math.BigDecimal
import java.time.Instant
import java.util.Base64
import java.util.UUID
import kotlin.math.floor
import kotlin.math.roundToLong
import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerializationException
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonEncoder
import kotlinx.serialization.json.JsonUnquotedLiteral

/** Reads and writes the default Foundation JSONEncoder/JSONDecoder wire format. */
val SwiftJson: Json = Json {
    explicitNulls = false
    encodeDefaults = true
    ignoreUnknownKeys = true // mirrors JSONDecoder so archives from a newer iOS app still import
}

private const val REFERENCE_OFFSET = 978_307_200L // seconds from 1970 to 2001-01-01

/** Swift Date: JSON number of seconds since 2001-01-01 UTC. */
object SwiftDate : KSerializer<Instant> {
    override val descriptor = PrimitiveSerialDescriptor("SwiftDate", PrimitiveKind.DOUBLE)

    // Foundation writes shortest plain decimals (783000000, not 7.83E8).
    // shortcut: assumes Double.toString is shortest round-trip (JDK 19+); ART may print more digits for some
    // fractions. Dates are not fingerprinted; revisit if byte-equal date text is ever required.
    @OptIn(ExperimentalSerializationApi::class)
    override fun serialize(encoder: Encoder, value: Instant) {
        val seconds = (value.epochSecond - REFERENCE_OFFSET) + value.nano / 1e9
        val plain = BigDecimal(seconds.toString()).stripTrailingZeros().toPlainString()
        if (encoder is JsonEncoder) encoder.encodeJsonElement(JsonUnquotedLiteral(plain)) else encoder.encodeDouble(seconds)
    }

    override fun deserialize(decoder: Decoder): Instant {
        val seconds = decoder.decodeDouble()
        if (!seconds.isFinite() || kotlin.math.abs(seconds) > 1e15) throw SerializationException("Date out of range")
        val whole = floor(seconds)
        return Instant.ofEpochSecond(whole.toLong() + REFERENCE_OFFSET, ((seconds - whole) * 1e9).roundToLong())
    }
}

private val CANONICAL_UUID = Regex("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")

/** Swift `UUID(uuidString:)`: canonical form in either case, else null. */
internal fun swiftUUID(text: String): UUID? = if (CANONICAL_UUID.matches(text)) UUID.fromString(text) else null

/** Swift `uuidString`. */
internal val UUID.swift: String get() = toString().uppercase()

/** Swift UUID: uppercase string; read case-insensitively. */
object SwiftUUID : KSerializer<UUID> {
    override val descriptor = PrimitiveSerialDescriptor("SwiftUUID", PrimitiveKind.STRING)
    override fun serialize(encoder: Encoder, value: UUID) = encoder.encodeString(value.toString().uppercase())
    override fun deserialize(decoder: Decoder): UUID = decoder.decodeString().let {
        if (!CANONICAL_UUID.matches(it)) throw SerializationException("Malformed UUID")
        UUID.fromString(it)
    }
}

/**
 * Swift Data: padded standard base64 string. An archive `Json` may bind a contextual ByteArray serializer
 * ([PlaceholderData]); every Data field then goes through it, so models keep their schema.
 */
object SwiftData : KSerializer<ByteArray> {
    override val descriptor = PrimitiveSerialDescriptor("SwiftData", PrimitiveKind.STRING)
    override fun serialize(encoder: Encoder, value: ByteArray) {
        val bound = encoder.serializersModule.getContextual(ByteArray::class)
        if (bound != null) bound.serialize(encoder, value) else encoder.encodeString(Base64.getEncoder().encodeToString(value))
    }
    override fun deserialize(decoder: Decoder): ByteArray =
        decoder.serializersModule.getContextual(ByteArray::class)?.deserialize(decoder) ?: base64Data(decoder.decodeString())
}

private fun base64Data(text: String): ByteArray =
    try {
        Base64.getDecoder().decode(text)
    } catch (_: IllegalArgumentException) {
        throw SerializationException("Malformed base64 data")
    }

/**
 * Swift Data whose in-memory values are placeholders, so one photo's bytes are held at a time:
 * encoding writes [resolve] of the placeholder, decoding returns [store] of the decoded bytes.
 */
internal class PlaceholderData(
    private val resolve: (ByteArray) -> ByteArray,
    private val store: (ByteArray) -> ByteArray = { throw UnsupportedOperationException("encode only") },
) : KSerializer<ByteArray> {
    override val descriptor = SwiftData.descriptor
    override fun serialize(encoder: Encoder, value: ByteArray) =
        encoder.encodeString(Base64.getEncoder().encodeToString(resolve(value)))
    override fun deserialize(decoder: Decoder): ByteArray = store(base64Data(decoder.decodeString()))
}
