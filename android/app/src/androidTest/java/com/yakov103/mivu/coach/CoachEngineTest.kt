package com.yakov103.mivu.coach

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.yakov103.mivu.analysis.ResponsesClient
import com.yakov103.mivu.diary.CoachCaptureContext
import com.yakov103.mivu.diary.CoachClarification
import com.yakov103.mivu.diary.CoachSubmissionPayload
import com.yakov103.mivu.diary.CoachTurn
import com.yakov103.mivu.diary.CoachTurnState
import com.yakov103.mivu.diary.DiaryDatabase
import com.yakov103.mivu.diary.DiaryProfile
import com.yakov103.mivu.diary.MealPhoto
import com.yakov103.mivu.diary.PhotoRole
import com.yakov103.mivu.diary.applyCoachWrites
import com.yakov103.mivu.diary.captureCoachSubmission
import com.yakov103.mivu.diary.startDay
import java.io.File
import java.net.SocketTimeoutException
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test

/** Synthetic diaries and scripted inference only; ports the iOS CoachEngine.run rules. */
class CoachEngineTest {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val profile = DiaryProfile(UUID.randomUUID(), "Synthetic", "en", "UTC", "")
    private lateinit var db: DiaryDatabase
    private val at = Instant.parse("2026-10-24T12:00:00Z")
    private val today = "2026-10-24"

    @Before fun open() {
        File(context.filesDir, "profiles").deleteRecursively()
        db = DiaryDatabase.create(context, profile)
        db.startDay(at, db.head().revision)
    }

    @After fun close() {
        db.close()
        File(context.filesDir, "profiles").deleteRecursively()
    }

    /** Scripted rounds; each input item must serialize as the transport would send it. */
    private class Script(vararg rounds: () -> CoachInferenceResult) {
        val rounds = rounds.toMutableList()
        val inputs = mutableListOf<List<CoachInferenceInput>>()
        suspend fun infer(input: List<CoachInferenceInput>, tools: JsonObject): CoachInferenceResult {
            input.forEach { it.json() }
            assertEquals("namespace", tools["type"].toString().trim('"'))
            inputs += input
            return (rounds.removeFirstOrNull() ?: throw AssertionError("unexpected round"))()
        }
    }

    private fun call(name: String, arguments: String, id: String = name) = CoachToolCall("fc_$id", "call_$id", name, "mivu", arguments)
    private fun result(vararg calls: CoachToolCall, text: String = ""): () -> CoachInferenceResult = {
        CoachInferenceResult("fixture-model", text, calls.toList(), calls.map { c ->
            buildJsonObject { put("type", "function_call"); put("id", c.id); put("call_id", c.callID); put("name", c.name)
                put("namespace", "mivu"); put("arguments", c.arguments); put("status", "completed") }.toString()
        })
    }
    private fun failing(error: Throwable): () -> CoachInferenceResult = { throw error }
    private val logFood = """{"target_local_date":"$today","items":[{"name":"Synthetic sandwich","quantity":1,"unit":"piece","kcal":300,"carbs":null,"protein":null,"fat":null}]}"""

    private fun turn(text: String = "I had a synthetic sandwich", photos: List<MealPhoto> = emptyList()): CoachTurn {
        val h = db.head()
        return db.captureCoachSubmission(CoachSubmissionPayload(UUID.randomUUID(), text, photos,
            CoachCaptureContext(at, "UTC", h.activeDayID, h.previousDayConfirmedAt, h.activeConversationSegmentID)), h.revision)
    }
    private fun stored(id: UUID) = db.read { it.coachTurnWithoutPhotos(id) }!!
    private fun run(script: Script, id: UUID) = runBlocking { CoachEngine(db, script::infer).run(id) }
    private fun failure(script: Script, id: UUID): Throwable = try { run(script, id); fail("expected failure"); throw AssertionError() } catch (e: Throwable) { e }

    @Test fun textOnlyMealLogsAndCompletes() {
        val t = turn()
        val script = Script(result(call("log_food", logFood)), result(text = " Logged — **300** kcal so far today. "))
        val done = run(script, t.id)
        assertEquals(CoachTurnState.completed, done.state)
        assertEquals("Logged — **300** kcal so far today.", done.assistantText)
        assertEquals(1, done.receipts.size)
        val meal = db.snapshot().meals.single()
        assertEquals(listOf("fixture-model"), meal.items.map { it.estimatedBy })
        val first = script.inputs[0]
        assertEquals(CoachInferenceInput.Message(CoachInferenceInput.Role.developer, CoachEngine.STABLE_RULES), first[0])
        assertTrue((first[1] as CoachInferenceInput.Message).text.startsWith("The current waking day is $today; "))
        assertEquals(CoachInferenceInput.Message(CoachInferenceInput.Role.user, t.text), first.last())
        // The next round replays the call and answers it with the receipt.
        val second = script.inputs[1]
        assertEquals(first.size + 2, second.size)
        assertTrue(second[first.size] is CoachInferenceInput.PriorOutput)
        assertEquals(CoachInferenceInput.FunctionOutput("call_log_food", done.receipts[0].resultJSON), second.last())
    }

    @Test fun replayModeSendsNoPhotosAndNoDuplicateWrites() {
        val jpeg = byteArrayOf(-1, -40, -1, -32, 1, 2, 3)
        val t = turn(photos = listOf(MealPhoto(UUID.randomUUID(), jpeg, at, PhotoRole.unspecified)))
        val write = (CoachTools.parse(call("log_food", logFood), emptyList(), emptyList()).estimatedBy("fixture-model") as CoachCommand.Write).write
        val prior = db.applyCoachWrites(t.id, listOf(write), at = at)
        val script = Script(result(call("log_food", logFood)), result(text = "Logged **300** kcal."))
        val done = run(script, t.id)
        assertEquals(CoachTurnState.completed, done.state)
        assertEquals(prior, done.receipts)
        assertEquals(1, db.snapshot().meals.size)
        assertTrue(script.inputs.flatten().none { it is CoachInferenceInput.Message && it.images.isNotEmpty() })
        // A new write is refused on replay; the committed food still completes the turn, marked incomplete.
        val other = turn("Synthetic second")
        db.applyCoachWrites(other.id, listOf(write), at = at)
        val weight = """{"local_date":"$today","value":70,"unit":"kg"}"""
        val refused = run(Script(result(call("log_weight", weight))), other.id)
        assertEquals(true, refused.incomplete)
        assertEquals(2, db.snapshot().meals.size)
        assertTrue(db.snapshot().weights.isEmpty())
    }

    @Test fun ungroundedSaveClaimRejected() {
        val t = turn()
        assertEquals(CoachError.UngroundedConfirmation, failure(Script(result(text = "I've logged your sandwich.")), t.id))
        assertEquals(CoachTurnState.needsClarification, stored(t.id).state)
        assertTrue(db.snapshot().meals.isEmpty())
    }

    @Test fun clarificationMustBeOnlyCall() {
        val t = turn()
        val ask = call("ask_clarification", """{"kind":"portion"}""")
        assertEquals(CoachError.InvalidArguments, failure(Script(result(ask, call("log_food", logFood))), t.id))
        assertEquals(CoachTurnState.needsRetry, stored(t.id).state)
        assertTrue(db.snapshot().meals.isEmpty())
        val done = run(Script(result(ask)), t.id)
        assertEquals(CoachTurnState.completed, done.state)
        assertEquals("How much did you eat? Give grams, a serving size, or a container size.", done.assistantText)
        assertEquals(CoachClarification.portion, done.question?.kind)
    }

    @Test fun partialSuccessMarksIncomplete() {
        val t = turn()
        val done = run(Script(result(call("log_food", logFood)), failing(ResponsesClient.Failure.Http(500))), t.id)
        assertEquals(CoachTurnState.completed, done.state)
        assertEquals(true, done.incomplete)
        assertEquals("Saved — about **300** kcal.", done.assistantText)
    }

    @Test fun unauthorizedWaitsForConnection() {
        val t = turn()
        assertEquals(ResponsesClient.Failure.Unauthorized, failure(Script(failing(ResponsesClient.Failure.Unauthorized)), t.id))
        assertEquals(CoachTurnState.waitingForConnection, stored(t.id).state)
    }

    @Test fun usageUnavailableNeedsRetry() {
        val t = turn()
        assertEquals(ResponsesClient.Failure.UsageUnavailable, failure(Script(failing(ResponsesClient.Failure.UsageUnavailable)), t.id))
        assertEquals(CoachTurnState.needsRetry, stored(t.id).state)
    }

    @Test fun transientWaitsForNetwork() {
        val t = turn()
        assertTrue(failure(Script(failing(SocketTimeoutException())), t.id) is SocketTimeoutException)
        assertEquals(CoachTurnState.waitingForNetwork, stored(t.id).state)
        failure(Script(failing(ResponsesClient.Failure.Http(503))), t.id)
        assertEquals(CoachTurnState.waitingForNetwork, stored(t.id).state)
    }

    @Test fun droppedConnectionIsTransient() {
        // iOS URLError.networkConnectionLost; a refused certificate is not retried.
        listOf(java.io.EOFException(), javax.net.ssl.SSLException("synthetic"), java.net.ProtocolException()).forEach {
            assertTrue(CoachEngine.isTransient(it))
        }
        assertEquals(false, CoachEngine.isTransient(javax.net.ssl.SSLHandshakeException("synthetic")))
        assertEquals(false, CoachEngine.isTransient(javax.net.ssl.SSLPeerUnverifiedException("synthetic")))
        assertEquals(false, CoachEngine.isTransient(javax.net.ssl.SSLKeyException("synthetic")))
    }

    @Test fun roundLimitStops() {
        val t = turn()
        val script = Script(*Array(8) { result(call("get_context", "{}", "context$it")) })
        assertEquals(CoachError.LimitExceeded, failure(script, t.id))
        assertEquals(8, script.inputs.size)
        assertEquals(CoachTurnState.needsRetry, stored(t.id).state)
    }

    @Test fun photoTurnReportsPreparingThenThinking() {
        val t = turn(photos = listOf(MealPhoto(UUID.randomUUID(), byteArrayOf(-1, -40, -1, -32, 1, 2, 3), at, PhotoRole.unspecified)))
        val script = Script(result(call("log_food", logFood)), result(text = "Logged **300** kcal."))
        val phases = mutableListOf<CoachActivity>()
        runBlocking { CoachEngine(db, script::infer, onActivity = { phases += it }).run(t.id) }
        assertEquals(listOf(CoachActivity.preparingPhotos, CoachActivity.thinking, CoachActivity.saving, CoachActivity.thinking), phases)
    }
}
