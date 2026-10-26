package com.yakov103.mivu.coach

import com.yakov103.mivu.analysis.ResponsesClient
import com.yakov103.mivu.connection.SessionError
import com.yakov103.mivu.diary.DiaryError
import java.net.SocketTimeoutException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** The stored failure code names the error only, never its message, and fits the turn's 200-byte limit. */
class CoachFailureReasonTest {
    @Test fun reasonIsTheErrorCaseOnly() {
        assertEquals("CoachError.InvalidArguments", CoachEngine.failureReason(CoachError.InvalidArguments))
        assertEquals("ResponsesClient.Failure.Http(503)", CoachEngine.failureReason(ResponsesClient.Failure.Http(503)))
        assertEquals("DiaryError.InvalidData", CoachEngine.failureReason(DiaryError.InvalidData("coach json")))
        assertEquals("SocketTimeoutException", CoachEngine.failureReason(SocketTimeoutException("secret")))
        val all = listOf(CoachError.LimitExceeded, ResponsesClient.Failure.Malformed("x".repeat(500)), SessionError.ProviderFailure(500),
            DiaryError.InvalidData("y".repeat(500)), object : Exception("z".repeat(500)) {}, IllegalStateException())
        all.forEach { assertTrue(CoachEngine.failureReason(it).toByteArray().size <= 200) }
    }

    @Test fun correctableAndModelOutputTablesArePinned() {
        val correctable = listOf(CoachError.InvalidTool, CoachError.InvalidArguments, DiaryError.InvalidData("x"), DiaryError.NotFound,
            DiaryError.StaleRevision, DiaryError.InvalidAmountUnitChange)
        val modelOutput = listOf(CoachError.InvalidTool, CoachError.InvalidArguments, ResponsesClient.Failure.Malformed("x"),
            ResponsesClient.Failure.ResponseFailed)
        val others = listOf(CoachError.LimitExceeded, DiaryError.AmbiguousDay, ResponsesClient.Failure.Unauthorized,
            CoachError.UngroundedConfirmation, ResponsesClient.Failure.Http(503), ResponsesClient.Failure.LimitExceeded, SocketTimeoutException())
        for (error in correctable + modelOutput + others) {
            assertEquals(error.toString(), error in correctable, CoachEngine.isCorrectable(error))
            assertEquals(error.toString(), error in modelOutput, CoachEngine.isModelOutputFailure(error))
        }
    }
}
