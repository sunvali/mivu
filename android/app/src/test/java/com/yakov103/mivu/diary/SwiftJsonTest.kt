package com.yakov103.mivu.diary

import java.time.Instant
import java.util.UUID
import kotlin.math.abs
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.decodeFromString
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SwiftJsonTest {
    @Serializable
    private data class Box(
        @Serializable(SwiftDate::class) val at: Instant,
        @Serializable(SwiftUUID::class) val id: UUID,
        @Serializable(SwiftData::class) val data: ByteArray,
        val note: String? = null,
    )

    private fun decode(at: String, id: String = "\"e621e1f8-c36c-495a-93fc-0c247a3e6e5f\"", data: String = "\"\"") =
        SwiftJson.decodeFromString<Box>("""{"at":$at,"id":$id,"data":$data}""")

    @Test fun dateReferenceEpoch() {
        assertEquals(Instant.parse("2001-01-01T00:00:00Z"), decode("0.0").at)
        assertEquals(Instant.parse("2001-01-01T00:00:00Z"), decode("0").at)
        assertEquals(Instant.EPOCH, decode("-978307200.0").at)
    }

    @Test fun dateRoundTripsSubSecond() {
        val t = Instant.ofEpochSecond(750000000L + 978307200L, 123_456_000)
        val back = SwiftJson.decodeFromString<Box>(SwiftJson.encodeToString(Box(t, UUID.randomUUID(), byteArrayOf())))
        assertTrue(abs(back.at.until(t, java.time.temporal.ChronoUnit.NANOS)) < 1_000)
        assertTrue(SwiftJson.encodeToString(Box(Instant.parse("2001-01-01T00:00:00Z"), UUID.randomUUID(), byteArrayOf()))
            .contains("\"at\":0.0"))
    }

    @Test fun uuidReadsLowerWritesUpper() {
        val box = decode("0")
        val json = SwiftJson.encodeToString(box)
        assertTrue(json.contains("E621E1F8-C36C-495A-93FC-0C247A3E6E5F"))
    }

    @Test fun dataRoundTripsAndAcceptsEscapedSlash() {
        val bytes = byteArrayOf(0, -1, 47)
        val json = SwiftJson.encodeToString(Box(Instant.EPOCH, UUID.randomUUID(), bytes))
        assertTrue(json.contains("\"data\":\"AP8v\""))
        assertArrayEquals(bytes, SwiftJson.decodeFromString<Box>(json).data)
        // 0xFF 0xFF 0xFF -> "////"; Foundation may write "\/".
        assertArrayEquals(byteArrayOf(-1, -1, -1), decode("0", data = "\"\\/\\/\\/\\/\"").data)
    }

    @Test fun nilOmitted() {
        assertFalse(SwiftJson.encodeToString(Box(Instant.EPOCH, UUID.randomUUID(), byteArrayOf())).contains("note"))
    }
}
