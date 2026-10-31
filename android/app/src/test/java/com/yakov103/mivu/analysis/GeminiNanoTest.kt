package com.yakov103.mivu.analysis

import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.common.GenAiException
import com.google.mlkit.genai.common.GenAiException.ErrorCode
import com.google.mlkit.genai.prompt.Candidate
import com.yakov103.mivu.connection.NanoStatus
import java.time.Duration
import org.junit.Assert.assertEquals
import org.junit.Test

class GeminiNanoTest {
    @Test fun failureMapping() {
        assertEquals(OnDeviceFailure.Busy, GeminiNano.failure(ErrorCode.BUSY))
        assertEquals(OnDeviceFailure.Paused, GeminiNano.failure(ErrorCode.BACKGROUND_USE_BLOCKED))
        assertEquals(OnDeviceFailure.BatteryQuota, GeminiNano.failure(ErrorCode.PER_APP_BATTERY_USE_QUOTA_EXCEEDED))
        assertEquals(OnDeviceFailure.ImagesUnsupported, GeminiNano.failure(ErrorCode.INVALID_INPUT_IMAGE, images = true))
        assertEquals(OnDeviceFailure.ImagesUnsupported, GeminiNano.failure(ErrorCode.NOT_SUPPORTED, images = true))
        assertEquals(OnDeviceFailure.Unavailable, GeminiNano.failure(ErrorCode.NOT_SUPPORTED))
        for (code in listOf(ErrorCode.UNKNOWN, ErrorCode.NOT_AVAILABLE, ErrorCode.REQUEST_TOO_LARGE, ErrorCode.CANCELLED)) {
            assertEquals(OnDeviceFailure.Unavailable, GeminiNano.failure(code, images = true))
        }
    }

    @Test fun statusMapping() {
        assertEquals(NanoStatus.unavailable, GeminiNano.status { FeatureStatus.UNAVAILABLE })
        assertEquals(NanoStatus.downloadable, GeminiNano.status { FeatureStatus.DOWNLOADABLE })
        assertEquals(NanoStatus.downloading, GeminiNano.status { FeatureStatus.DOWNLOADING })
        assertEquals(NanoStatus.available, GeminiNano.status { FeatureStatus.AVAILABLE })
        // AICore 606 FEATURE_NOT_FOUND: its configuration is still downloading.
        assertEquals(NanoStatus.preparing, GeminiNano.status { throw GenAiException(null, ErrorCode.NOT_AVAILABLE, Duration.ZERO, 606, 3) })
        // Only a returned UNAVAILABLE is an answer: any other error, transient or not, leaves the check unfinished.
        assertEquals(null, GeminiNano.status { throw GenAiException(null, ErrorCode.NOT_AVAILABLE, Duration.ZERO, 601, 4) })
        assertEquals(null, GeminiNano.status { throw GenAiException(null, ErrorCode.BUSY, Duration.ZERO, 0, 4) })
        assertEquals(null, GeminiNano.status { throw SecurityException("synthetic") })
    }

    @Test fun truncatedReplyIsMalformed() {
        assertEquals("{}", GeminiNano.reply("{}", Candidate.FinishReason.STOP))
        assertEquals(ResponsesClient.Failure.Malformed("truncated"),
            runCatching { GeminiNano.reply("{\"intent\": \"log\", \"foods\": [", Candidate.FinishReason.MAX_TOKENS) }.exceptionOrNull())
        assertEquals(ResponsesClient.Failure.Malformed("no candidate"), runCatching { GeminiNano.reply(null, null) }.exceptionOrNull())
    }
}
