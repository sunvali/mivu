package com.yakov103.mivu.analysis

import com.sun.net.httpserver.HttpServer
import com.yakov103.mivu.coach.CoachInferenceInput
import com.yakov103.mivu.coach.CoachTools
import java.net.InetSocketAddress
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class ResponsesClientTest {
    private val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
    private var status = 200
    private var reply = ""
    private var location: String? = null
    private var seenBody = ""
    private val seenHeaders = mutableMapOf<String, String?>()
    private val client: ResponsesClient

    init {
        server.createContext("/") { ex ->
            seenBody = ex.requestBody.readBytes().decodeToString()
            listOf("Authorization", "Accept", "Content-Type").forEach { seenHeaders[it] = ex.requestHeaders.getFirst(it) }
            location?.let { ex.responseHeaders.add("Location", it) }
            val bytes = reply.toByteArray()
            ex.sendResponseHeaders(status, bytes.size.toLong())
            ex.responseBody.use { it.write(bytes) }
        }
        server.start()
        client = ResponsesClient("http://127.0.0.1:${server.address.port}/v1/")
    }

    @After fun stop() = server.stop(0)

    private fun fixture(name: String) = javaClass.classLoader!!.getResource("responses/$name")!!.readText().trimEnd() + "\n\n" // files omit the final blank line (whitespace check)

    private fun failure(block: suspend () -> Unit): ResponsesClient.Failure = try {
        runBlocking { block() }; fail("expected failure"); throw AssertionError()
    } catch (f: ResponsesClient.Failure) { f }

    private fun run(image: ByteArray? = null, mime: String? = null) =
        runBlocking { client.run("fixture-model", "hello", image, mime, "tok-secret") }

    @Test fun requestShapeAndHeaders() {
        reply = fixture("text-ok.sse")
        run()
        val body = JSONObject(seenBody)
        assertEquals(setOf("model", "input", "store", "stream"), body.keys().asSequence().toSet())
        assertEquals(false, body.getBoolean("store"))
        assertEquals(true, body.getBoolean("stream"))
        val content = body.getJSONArray("input").getJSONObject(0).getJSONArray("content")
        assertEquals("input_text", content.getJSONObject(0).getString("type"))
        assertEquals("Bearer tok-secret", seenHeaders["Authorization"])
        assertEquals("text/event-stream", seenHeaders["Accept"])
        assertEquals("application/json", seenHeaders["Content-Type"])
    }

    @Test fun imageBecomesDataUrl() {
        reply = fixture("text-ok.sse")
        run(byteArrayOf(1, 2, 3), "image/jpeg")
        val part = JSONObject(seenBody).getJSONArray("input").getJSONObject(0).getJSONArray("content").getJSONObject(1)
        assertEquals("input_image", part.getString("type"))
        assertEquals("data:image/jpeg;base64,AQID", part.getString("image_url"))
    }

    @Test fun textOk() { reply = fixture("text-ok.sse"); assertEquals("Synthetic result", run().text) }

    @Test fun terminalShapes() {
        reply = fixture("truncated.sse")
        assertEquals(ResponsesClient.Failure.IncompleteResponse, failure { run() })
        reply = fixture("incomplete.sse")
        assertEquals(ResponsesClient.Failure.IncompleteResponse, failure { run() })
        reply = fixture("failed-quota.sse")
        assertEquals(ResponsesClient.Failure.QuotaReached, failure { run() })
        reply = fixture("trailing.sse")
        assertTrue(failure { run() } is ResponsesClient.Failure.Malformed)
        reply = "data: {not json\n\n"
        assertTrue(failure { run() } is ResponsesClient.Failure.Malformed)
    }

    @Test fun httpStatuses() {
        status = 401
        assertEquals(ResponsesClient.Failure.Unauthorized, failure { run() })
        status = 500
        assertEquals(ResponsesClient.Failure.Http(500), failure { run() })
    }

    @Test fun redirectsAreNotFollowed() {
        status = 302
        location = "http://127.0.0.1:${server.address.port}/elsewhere"
        assertEquals(ResponsesClient.Failure.Http(302), failure { run() })
    }

    @Test fun invalidInputNeverSends() {
        assertEquals(ResponsesClient.Failure.InvalidInput, failure { client.run("m", "t", byteArrayOf(1), null, "tok") })
        assertEquals(ResponsesClient.Failure.InvalidInput, failure { client.run("m", "t", null, null, "bad token") })
        assertEquals("", seenBody)
    }

    @Test fun tokenNeverInFailureText() {
        reply = "data: {bad tok-secret\n\n"
        assertFalse(failure { run() }.toString().contains("tok-secret"))
        status = 401
        assertFalse(failure { run() }.toString().contains("tok-secret"))
    }

    @Test fun listsOnlyListedModels() {
        reply = """{"models":[{"slug":"a","display_name":"A","visibility":"list"},{"slug":"b","display_name":"B","visibility":"hide"}]}"""
        assertEquals(listOf(AvailableModel("a", "A")), runBlocking { client.models("tok") })
        assertEquals("Bearer tok", seenHeaders["Authorization"])
        reply = """{"models":[{"slug":"","display_name":"A","visibility":"list"}]}"""
        assertTrue(failure { client.models("tok") } is ResponsesClient.Failure.Malformed)
    }

    private fun sse(vararg events: String) = events.joinToString("") { e ->
        "event: ${JSONObject(e).getString("type")}\ndata: $e\n\n"
    }
    private val reasoning = """{"type":"reasoning","id":"rs_1","summary":[],"encrypted_content":"synthetic-opaque"}"""
    private val call = """{"type":"function_call","id":"fc_1","call_id":"call_1","name":"get_context","namespace":"mivu","arguments":"{}","status":"completed"}"""
    private fun completed(output: String) = """{"type":"response.completed","response":{"status":"completed","model":"fixture-model","output":[$output]}}"""
    private fun respond(vararg input: CoachInferenceInput) = runBlocking {
        client.respond("fixture-model", input.toList().ifEmpty { listOf(CoachInferenceInput.Message(CoachInferenceInput.Role.user, "Synthetic")) },
            CoachTools.declarations(), "tok-secret")
    }

    @Test fun streamWithToolCallsParses() {
        reply = sse("""{"type":"response.output_item.done","output_index":0,"item":$reasoning}""",
            """{"type":"response.output_item.done","output_index":1,"item":$call}""", completed("$reasoning,$call"))
        val result = respond(CoachInferenceInput.Message(CoachInferenceInput.Role.developer, "Synthetic rules"),
            CoachInferenceInput.FunctionOutput("call_0", "{}"))
        assertEquals("fixture-model", result.model)
        assertEquals("", result.text)
        assertEquals(listOf(com.yakov103.mivu.coach.CoachToolCall("fc_1", "call_1", "get_context", "mivu", "{}")), result.calls)
        val body = JSONObject(seenBody)
        assertEquals(setOf("model", "input", "store", "stream", "tools"), body.keys().asSequence().toSet())
        assertEquals("namespace", body.getJSONArray("tools").getJSONObject(0).getString("type"))
        assertEquals("function_call_output", body.getJSONArray("input").getJSONObject(1).getString("type"))
        // A call whose arguments are not a JSON object is refused.
        reply = sse(completed(call.replace("\"arguments\":\"{}\"", "\"arguments\":\"[]\"")))
        assertTrue(failure { respond() } is ResponsesClient.Failure.Malformed)
        // The probe path still needs text.
        reply = sse(completed(call))
        assertTrue(failure { run() } is ResponsesClient.Failure.Malformed)
    }

    @Test fun reasoningItemsAreKept() {
        // Final items only in done events, with an empty terminal output.
        val message = """{"type":"message","id":"msg_1","role":"assistant","status":"completed","content":[{"type":"output_text","text":"Synthetic reply"}]}"""
        reply = sse("""{"type":"response.output_item.done","output_index":0,"item":$reasoning}""",
            """{"type":"response.output_item.done","output_index":1,"item":$message}""", completed(""))
        val result = respond()
        assertEquals("Synthetic reply", result.text)
        assertEquals(2, result.outputItems.size)
        val kept = JSONObject(result.outputItems[0])
        assertEquals("reasoning", kept.getString("type"))
        assertEquals("synthetic-opaque", kept.getString("encrypted_content"))
        // Kept items replay as prior outputs unchanged.
        respond(CoachInferenceInput.Message(CoachInferenceInput.Role.user, "Synthetic"), CoachInferenceInput.PriorOutput(result.outputItems[0]))
        assertEquals("synthetic-opaque", JSONObject(seenBody).getJSONArray("input").getJSONObject(1).getString("encrypted_content"))
    }

    @Test fun respondBoundsInput() {
        val many = List(129) { CoachInferenceInput.Message(CoachInferenceInput.Role.user, "x") }
        assertEquals(ResponsesClient.Failure.InvalidInput, failure { client.respond("m", many, null, "tok") })
        assertEquals(ResponsesClient.Failure.InvalidInput,
            failure { client.respond("m", listOf(CoachInferenceInput.Message(CoachInferenceInput.Role.assistant, "x", listOf(byteArrayOf(-1, -40, -1, 0)))), null, "tok") })
        assertEquals("", seenBody)
    }
}
