@file:Suppress("EnumEntryName") // entry names are the iOS raw values

package com.yakov103.mivu.coach

import com.yakov103.mivu.analysis.ResponsesClient
import com.yakov103.mivu.diary.blankLikeSwift
import java.util.Base64
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

// Port of ios/Mivu/Analysis/CoachInference.swift: CoachToolCall (:3), CoachInferenceResult (:11), CoachInferenceInput (:19-54).

/** A model function call; arguments are the raw JSON text. */
data class CoachToolCall(val id: String, val callID: String, val name: String, val namespace: String?, val arguments: String)

/** One model round; [outputItems] keeps every complete output item (reasoning included) as JSON for stateless replay. */
data class CoachInferenceResult(val model: String, val text: String, val calls: List<CoachToolCall>, val outputItems: List<String>)

sealed interface CoachInferenceInput {
    enum class Role { developer, user, assistant }
    data class Message(val role: Role, val text: String, val images: List<ByteArray> = emptyList()) : CoachInferenceInput {
        // ByteArray equality is by reference; compare image bytes by content like Swift Data.
        override fun equals(other: Any?) = other is Message && role == other.role && text == other.text &&
            images.size == other.images.size && images.indices.all { images[it].contentEquals(other.images[it]) }
        override fun hashCode() = listOf(role, text, images.map { it.contentHashCode() }).hashCode()
    }
    data class PriorOutput(val item: String) : CoachInferenceInput
    data class FunctionOutput(val callID: String, val output: String) : CoachInferenceInput

    /** The Responses input item; anything iOS refuses is InvalidInput. */
    fun json(): JsonObject = when (this) {
        is Message -> {
            if (text.utf8() > 65_536 || (text.blankLikeSwift() && images.isEmpty()) || (images.isNotEmpty() && role != Role.user) ||
                images.size > 8
            ) throw ResponsesClient.Failure.InvalidInput
            buildJsonObject {
                put("role", role.name)
                put("content", buildJsonArray {
                    add(buildJsonObject { put("type", if (role == Role.assistant) "output_text" else "input_text"); put("text", text) })
                    for (image in images) add(buildJsonObject {
                        put("type", "input_image")
                        put("image_url", "data:${imageMIME(image)};base64," + Base64.getEncoder().encodeToString(image))
                    })
                })
            }
        }
        is PriorOutput -> {
            val parsed = if (item.utf8() <= 1_048_576) runCatching { Json.parseToJsonElement(item) }.getOrNull() as? JsonObject else null
            val type = (parsed?.get("type") as? JsonPrimitive)?.takeIf { it.isString }?.content
            if (parsed == null || type !in setOf("message", "function_call", "reasoning")) throw ResponsesClient.Failure.InvalidInput
            parsed
        }
        is FunctionOutput -> {
            if (callID.isEmpty() || callID.utf8() > 256 || output.utf8() > 65_536) throw ResponsesClient.Failure.InvalidInput
            buildJsonObject { put("type", "function_call_output"); put("call_id", callID); put("output", output) }
        }
    }

    companion object {
        fun imageMIME(data: ByteArray): String {
            if (data.size > 5_242_880) throw ResponsesClient.Failure.InvalidInput
            fun starts(vararg prefix: Int) = data.size >= prefix.size && prefix.indices.all { data[it] == prefix[it].toByte() }
            if (starts(137, 80, 78, 71, 13, 10, 26, 10)) return "image/png"
            if (starts(255, 216, 255) && data.size >= 4) return "image/jpeg"
            throw ResponsesClient.Failure.InvalidInput
        }
    }
}

private fun String.utf8() = toByteArray(Charsets.UTF_8).size
