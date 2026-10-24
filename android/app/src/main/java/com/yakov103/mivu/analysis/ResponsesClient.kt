package com.yakov103.mivu.analysis

import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.util.Base64
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runInterruptible
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject

data class AvailableModel(val slug: String, val displayName: String)

data class ProbeResult(val text: String)

private const val ITEM_LIMIT = 1_048_576
private const val TOTAL_LIMIT = 8_388_608

/** Lists models and runs one streamed Responses request under the ChatGPT plan token. */
class ResponsesClient(private val base: String = "https://api.openai.com/v1/") {
    // Messages are fixed local text: the token and provider bodies never reach them.
    sealed class Failure(message: String) : Exception(message) {
        object InvalidInput : Failure("invalid input")
        object Unauthorized : Failure("unauthorized")
        object Forbidden : Failure("forbidden")
        data class Http(val code: Int) : Failure("http $code")
        data class Malformed(val reason: String) : Failure("malformed response: $reason")
        object IncompleteResponse : Failure("incomplete response")
        object ResponseFailed : Failure("response failed")
        object QuotaReached : Failure("quota reached")
        object UsageUnavailable : Failure("usage unavailable")
        object LimitExceeded : Failure("limit exceeded")
    }

    suspend fun models(accessToken: String): List<AvailableModel> = runInterruptible(Dispatchers.IO) {
        open("models", accessToken).use { conn ->
            val body = readLimited(conn.inputStream)
            try {
                val models = JSONObject(body).getJSONArray("models")
                val all = (0 until models.length()).map { models.getJSONObject(it) }
                all.forEach { require(it.getString("slug").isNotEmpty() && it.getString("display_name").isNotEmpty()) }
                all.filter { it.getString("visibility") == "list" }
                    .map { AvailableModel(it.getString("slug"), it.getString("display_name")) }
            } catch (_: JSONException) {
                throw Failure.Malformed("catalog")
            } catch (_: IllegalArgumentException) {
                throw Failure.Malformed("catalog")
            }
        }
    }

    suspend fun run(model: String, text: String, image: ByteArray?, mime: String?, accessToken: String): ProbeResult {
        if (model.isBlank() || model.toByteArray().size > 256 || text.toByteArray().size > 65_536) throw Failure.InvalidInput
        if ((image == null) != (mime == null) || (image != null && image.size > 5_242_880) ||
            (mime != null && !Regex("image/[a-z0-9.+-]+").matches(mime))
        ) throw Failure.InvalidInput
        val content = JSONArray().put(JSONObject().put("type", "input_text").put("text", text))
        if (image != null) {
            val url = "data:$mime;base64," + Base64.getEncoder().encodeToString(image)
            content.put(JSONObject().put("type", "input_image").put("image_url", url))
        }
        val body = JSONObject().put("model", model).put("store", false).put("stream", true)
            .put("input", JSONArray().put(JSONObject().put("type", "message").put("role", "user").put("content", content)))
            .toString().toByteArray()
        return runInterruptible(Dispatchers.IO) {
            open("responses", accessToken, body).use { conn -> ProbeResult(SseParser().parse(conn.inputStream)) }
        }
    }

    private fun open(path: String, token: String, post: ByteArray? = null): HttpURLConnection {
        if (token.isEmpty() || token.any { it.isWhitespace() }) throw Failure.InvalidInput
        val conn = URL(base + path).openConnection() as HttpURLConnection
        try {
            conn.instanceFollowRedirects = false
            conn.connectTimeout = 60_000
            conn.readTimeout = 60_000
            conn.setRequestProperty("Authorization", "Bearer $token")
            if (post != null) {
                conn.requestMethod = "POST"
                conn.doOutput = true
                conn.setRequestProperty("Content-Type", "application/json")
                conn.setRequestProperty("Accept", "text/event-stream")
                conn.outputStream.use { it.write(post) }
            }
            when (val code = conn.responseCode) {
                200 -> return conn
                401 -> throw Failure.Unauthorized
                403 -> throw Failure.Forbidden
                429 -> throw Failure.QuotaReached
                else -> throw Failure.Http(code)
            }
        } catch (e: Throwable) {
            conn.disconnect()
            throw e
        }
    }

    private fun readLimited(input: InputStream): String {
        val out = ByteArrayOutputStream()
        val buf = ByteArray(8192)
        while (true) {
            val n = input.read(buf)
            if (n < 0) break
            if (out.size() + n > ITEM_LIMIT) throw Failure.LimitExceeded
            out.write(buf, 0, n)
        }
        return out.toByteArray().toString(Charsets.UTF_8)
    }

    private inline fun <T> HttpURLConnection.use(block: (HttpURLConnection) -> T): T =
        try { block(this) } finally { disconnect() }
}

/** Line-based SSE reader mirroring the iOS event validation; only text-producing events are accepted. */
private class SseParser {
    private val line = ByteArrayOutputStream()
    private val data = StringBuilder()
    private var eventName: String? = null
    private var total = 0
    private var skipLF = false
    private var text: String? = null
    private val doneItems = mutableMapOf<Int, JSONObject>()
    private val doneIds = mutableSetOf<String>()
    private var doneBytes = 0

    fun parse(input: InputStream): String {
        val buffered = input.buffered()
        while (true) {
            val b = buffered.read()
            if (b < 0) break
            if (++total > TOTAL_LIMIT) throw ResponsesClient.Failure.LimitExceeded
            if (skipLF) { skipLF = false; if (b == 10) continue }
            if (b == 10 || b == 13) { processLine(); line.reset(); skipLF = b == 13 }
            else {
                if (line.size() >= ITEM_LIMIT) throw ResponsesClient.Failure.LimitExceeded
                line.write(b)
            }
        }
        if (line.size() > 0 || data.isNotEmpty() || eventName != null) throw ResponsesClient.Failure.IncompleteResponse
        return text ?: throw ResponsesClient.Failure.IncompleteResponse
    }

    private fun bad(reason: String) = ResponsesClient.Failure.Malformed(reason)

    private fun processLine() {
        val s = try {
            Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
                .decode(ByteBuffer.wrap(line.toByteArray())).toString()
        } catch (_: java.nio.charset.CharacterCodingException) { throw bad("eventUTF8") }
        if (s.isEmpty()) {
            if (data.isNotEmpty()) processEvent(data.toString())
            data.setLength(0); eventName = null
            return
        }
        if (s.startsWith(":")) return
        val name = s.substringBefore(':')
        val value = if (':' in s) s.substringAfter(':').removePrefix(" ") else ""
        when (name) {
            "data" -> {
                if (data.length + value.length + 1 > ITEM_LIMIT) throw ResponsesClient.Failure.LimitExceeded
                data.append(value).append('\n')
            }
            "event" -> eventName = value
        }
    }

    private fun processEvent(raw: String) {
        if (raw == "[DONE]\n") {
            if (text == null) throw ResponsesClient.Failure.IncompleteResponse
            return
        }
        val obj = try { JSONObject(raw) } catch (_: JSONException) { throw bad("eventJSON") }
        val type = obj.optString("type", "")
        if (type.isEmpty() || obj.opt("type") !is String) throw bad("eventType")
        if (eventName != null && eventName != type) throw bad("eventNameMismatch")
        if (type == "error" || type == "response.failed") {
            val err = obj.optJSONObject("response")?.optJSONObject("error") ?: obj.optJSONObject("error")
            throw when (err?.optString("code") ?: obj.optString("code")) {
                "subscription_sharing_usage_limit_exceeded" -> ResponsesClient.Failure.QuotaReached
                "subscription_sharing_usage_unavailable", "subscription_sharing_user_unavailable" -> ResponsesClient.Failure.UsageUnavailable
                else -> ResponsesClient.Failure.ResponseFailed
            }
        }
        if (type == "response.incomplete") throw ResponsesClient.Failure.IncompleteResponse
        if (text != null) throw bad("trailingEvent")
        if (type == "response.output_text.delta" && obj.opt("delta") !is String) throw bad("deltaSchema")
        if (type == "response.output_item.done") recordDone(obj)
        if (type == "response.completed") complete(obj)
    }

    private fun recordDone(obj: JSONObject) {
        val index = obj.opt("output_index") as? Int
        if (index == null || index !in 0 until 128) throw bad("doneItemIndex")
        val item = obj.optJSONObject("item")
        val id = item?.opt("id") as? String
        if (item == null || item.opt("type") !in listOf("message", "reasoning") || id.isNullOrEmpty() || id.length > 256 ||
            (item.has("status") && item.opt("status") != "completed")
        ) throw bad("doneItemSchema")
        if (index in doneItems || !doneIds.add(id)) throw bad("doneItemConflict")
        val size = item.toString().toByteArray().size
        if (size > ITEM_LIMIT || doneBytes + size > TOTAL_LIMIT) throw ResponsesClient.Failure.LimitExceeded
        doneBytes += size
        doneItems[index] = item
    }

    private fun complete(obj: JSONObject) {
        val response = obj.optJSONObject("response") ?: throw bad("completedEnvelope")
        if (response.opt("status") != "completed") throw bad("completedStatus")
        if (response.has("error") && !response.isNull("error")) throw bad("completedError")
        if ((response.opt("model") as? String).isNullOrEmpty()) throw bad("completedModel")
        val terminal = response.optJSONArray("output")
        if (terminal == null || terminal.length() > 128) throw bad("completedOutput")
        val output = (0 until terminal.length()).map { terminal.optJSONObject(it) ?: throw bad("completedOutput") }
        val items = if (output.isEmpty() && doneItems.isNotEmpty()) {
            // Some direct streams carry final items only in done events.
            if (doneItems.keys.sorted() != (0 until doneItems.size).toList()) throw bad("doneItemIndex")
            (0 until doneItems.size).map { doneItems.getValue(it) }
        } else {
            doneItems.forEach { (i, item) -> if (i >= output.size || canonical(item) != canonical(output[i])) throw bad("doneItemConflict") }
            output
        }
        if (items.any { it.opt("type") !in listOf("message", "reasoning") }) throw bad("outputType")
        val texts = mutableListOf<String>()
        for (item in items.filter { it.opt("type") == "message" }) {
            val content = item.optJSONArray("content") ?: throw bad("contentSchema")
            for (i in 0 until content.length()) {
                val part = content.optJSONObject(i) ?: throw bad("contentSchema")
                if (part.opt("type") == "output_text") texts += part.opt("text") as? String ?: throw bad("contentSchema")
            }
        }
        val joined = texts.joinToString("\n")
        if (joined.toByteArray().size > 65_536) throw ResponsesClient.Failure.LimitExceeded
        if (joined.isBlank()) throw bad("emptyOutput")
        text = joined
    }
}

// Android's JSONObject has no order-insensitive equality; normalise to plain maps and lists.
private fun canonical(v: Any?): Any? = when (v) {
    is JSONObject -> v.keys().asSequence().associateWith { canonical(v.get(it)) }
    is JSONArray -> (0 until v.length()).map { canonical(v.get(it)) }
    JSONObject.NULL -> null
    else -> v
}
