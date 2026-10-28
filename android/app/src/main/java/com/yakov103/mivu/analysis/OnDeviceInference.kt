package com.yakov103.mivu.analysis

import com.yakov103.mivu.coach.CoachContext
import com.yakov103.mivu.coach.CoachInferenceInput
import com.yakov103.mivu.coach.CoachInferenceResult
import com.yakov103.mivu.coach.CoachToolCall
import com.yakov103.mivu.coach.CoachTools
import com.yakov103.mivu.diary.SwiftJson
import java.time.ZoneId
import java.util.UUID
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

// Port of ios/Mivu/Analysis/AppleLocalInference.swift and AppleInference.result: one small-model generation turns the
// Coach message into a single ChatGPT-shaped log_food / correct_item call, so CoachEngine is unchanged.

/** What the on-device model extracts from one message; unknown fields are ignored, missing numbers are 0. */
@Serializable
data class LocalTurn(val intent: Intent, val foods: List<Food> = emptyList(), val editFood: String? = null, val editQuantity: Double? = null) {
    init { require(editQuantity?.isFinite() != false) }

    @Suppress("EnumEntryName") // entry names are the model's JSON values
    enum class Intent { log, edit, other }

    @Serializable
    data class Food(
        val name: String,
        val searchName: String = "",
        val quantity: Double = 1.0,
        val unit: String = "",
        val kcal: Double = 0.0,
        val carbs: Double = 0.0,
        val protein: Double = 0.0,
        val fat: Double = 0.0,
        val kcalPer100g: Double = 0.0,
        val carbsPer100g: Double = 0.0,
        val proteinPer100g: Double = 0.0,
        val fatPer100g: Double = 0.0,
    ) {
        // "1e999" parses to Infinity, which cannot be written back as JSON.
        init { require(listOf(quantity, kcal, carbs, protein, fat, kcalPer100g, carbsPer100g, proteinPer100g, fatPer100g).all { it.isFinite() }) }
    }
}

interface OnDeviceModel {
    suspend fun turn(text: String, images: List<ByteArray>): LocalTurn

    /** 1-based number of the option that is the same food, or 0 for none. */
    suspend fun pick(phrase: String, options: List<NutritionTable.Food>): Int
}

interface FoodTable {
    fun search(phrase: String): List<NutritionTable.Food>
    fun portionGrams(code: Int, unit: String): Double?
}

object OnDeviceInference {
    const val MODEL = "gemini-nano"

    private val lenient = Json { ignoreUnknownKeys = true }

    suspend fun respond(input: List<CoachInferenceInput>, tools: JsonObject?, model: OnDeviceModel, table: FoodTable): CoachInferenceResult {
        // Only Coach turns run on-device; onboarding targets use the formula estimate instead.
        if (tools == null) throw ResponsesClient.Failure.InvalidInput
        // Once the save step has run, CoachEngine words the reply from its own receipts.
        if (input.any { it is CoachInferenceInput.FunctionOutput }) return result("Done.", emptyList())

        var context: CoachContext? = null
        var texts = mutableListOf<String>()
        var images = mutableListOf<ByteArray>()
        for (item in input) {
            if (item !is CoachInferenceInput.Message) continue
            // The first marker is CoachEngine's; later ones can be food names inside the context itself.
            if (item.role == CoachInferenceInput.Role.developer && MARKER in item.text) {
                context = SwiftJson.decodeFromString(CoachContext.serializer(), item.text.substringAfter(MARKER))
                texts = mutableListOf(); images = mutableListOf() // Earlier user messages are history, not this capture.
            } else if (item.role == CoachInferenceInput.Role.user) {
                texts += item.text; images += item.images
            }
        }
        context ?: throw ResponsesClient.Failure.InvalidInput
        val message = texts.joinToString("\n")
        // The small model sees only the message: shown saved foods, it logs them again.
        val turn = model.turn(message, images)
        val messageWords = NutritionTable.words(message)
        // Without a photo, a food counts only when the message names it.
        val foods = turn.foods.filter { images.isNotEmpty() || NutritionTable.words(it.name).any { w -> w in messageWords } }

        // "It" is the meal the conversation last changed; date-only meal times tie, so eatenAt is only the fallback.
        val complete = context.meals.filter { it.omittedItemCount == 0 }
        val latest = context.focus?.lastChanged?.let { changed -> complete.firstOrNull { it.id == changed.mealID } }
            ?: complete.maxByOrNull { it.eatenAt }
        // A named food must match a saved one; "make it three" names none and is safe only for a single-item meal.
        // Only words the message says count: on-device the model invents names ("chocolate" for "make it three").
        val named = NutritionTable.words(turn.editFood ?: "").intersect(messageWords)
        val target = if (named.isEmpty()) latest?.items?.singleOrNull()
        else latest?.items?.maxByOrNull { NutritionTable.words(it.name).intersect(named).size }
            ?.takeIf { NutritionTable.words(it.name).any { w -> w in named } }
        val quantity = turn.editQuantity
        if (turn.intent == LocalTurn.Intent.edit && latest != null && target != null && quantity != null && quantity > 0) {
            return result("", listOf("correct_item" to buildJsonObject {
                put("meal_id", latest.id.toString()); put("item_id", target.id.toString())
                put("expected_revision", latest.revision); put("quantity", quantity)
            }))
        }
        // An edit that names no saved food is usually a bare food mention such as "coke zero".
        if (turn.intent != LocalTurn.Intent.other && foods.isNotEmpty()) {
            val date = context.days.firstOrNull { it.id == context.activeDayID }?.localDate
                ?: context.capturedAt.atZone(ZoneId.of(context.captureTimeZoneID)).toLocalDate().toString()
            val items = JsonArray(foods.map { item(it, model, table) })
            return result("", listOf("log_food" to buildJsonObject { put("target_local_date", date); put("items", items) }))
        }
        // CoachEngine replaces text-only replies with its recorded summary.
        return result("Nothing to change.", emptyList())
    }

    private suspend fun item(food: LocalTurn.Food, model: OnDeviceModel, table: FoodTable): JsonObject {
        val weighed = food.unit.lowercase() in setOf("g", "gram", "grams", "ml", "milliliter", "milliliters")
        fun rounded(value: Double) = Math.round(value.coerceIn(0.0, 100_000.0) * 10) / 10.0
        fun item(kcal: Double, carbs: Double, protein: Double, fat: Double) = buildJsonObject {
            put("name", food.name); put("quantity", food.quantity); put("unit", food.unit)
            put("kcal", kcal); put("carbs", carbs); put("protein", protein); put("fat", fat)
        }
        // Numbers come from the USDA table when the on-device model confirms a match and a portion weight exists.
        tableMatch(food, weighed, model, table)?.let { (match, grams) ->
            val scale = grams / 100
            return item(rounded(match.kcal * scale), rounded(match.carbs * scale), rounded(match.protein * scale), rounded(match.fat * scale))
        }
        fun value(total: Double, per100: Double) = rounded(if (weighed) per100 * food.quantity / 100 else total)
        val carbs = value(food.carbs, food.carbsPer100g)
        val protein = value(food.protein, food.proteinPer100g)
        val fat = value(food.fat, food.fatPer100g)
        val fromMacros = Math.round(4 * (carbs + protein) + 9 * fat).toDouble()
        // Calories cannot sit far below what the macros imply; alcohol only raises them, so no upper bound.
        val kcal = value(food.kcal, food.kcalPer100g).let { if (it < 0.7 * fromMacros) fromMacros else it }
        return item(kcal, carbs, protein, fat)
    }

    /** The matched table entry and total grams, or null to keep the model's estimate. */
    private suspend fun tableMatch(food: LocalTurn.Food, weighed: Boolean, model: OnDeviceModel, table: FoodTable): Pair<NutritionTable.Food, Double>? {
        var options = runCatching { table.search(food.searchName) }.getOrDefault(emptyList())
        if (options.isEmpty()) options = runCatching { table.search(food.name) }.getOrDefault(emptyList())
        if (options.isEmpty()) return null
        val amount = food.quantity.let { if (it % 1.0 == 0.0) it.toLong().toString() else it.toString() }
        val choice = try {
            model.pick("$amount ${food.unit} ${food.name}", options)
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            return null // A failed pick keeps the estimate rather than failing the turn.
        }
        val match = options.getOrNull(choice - 1) ?: return null
        // shortcut: ml counts as grams, close for drinks; use FNDDS "fl oz" portions if density matters.
        // Only a weighed amount or a portion naming the person's own unit is trusted; synonyms and default servings
        // measured worse than the model's estimate (e.g. a 60 g default "cookie" serving).
        val portion = runCatching { table.portionGrams(match.code, food.unit) }.getOrNull()?.times(food.quantity)
        val grams = (if (weighed) food.quantity else portion) ?: return null
        return if (grams > 0) match to grams else null
    }

    /** Output items use the ChatGPT item shape that [CoachInferenceInput.PriorOutput] already validates. */
    private fun result(text: String, calls: List<Pair<String, JsonObject>>): CoachInferenceResult {
        val toolCalls = calls.map { (name, args) ->
            val callID = UUID.randomUUID().toString()
            CoachToolCall("fc_$callID", callID, name, CoachTools.NAMESPACE, args.toString())
        }
        val items: List<JsonElement> = if (toolCalls.isEmpty()) listOf(buildJsonObject {
            put("type", "message"); put("role", "assistant")
            put("content", buildJsonArray { add(buildJsonObject { put("type", "output_text"); put("text", text) }) })
        }) else toolCalls.map {
            buildJsonObject {
                put("type", "function_call"); put("id", it.id); put("call_id", it.callID); put("name", it.name)
                put("namespace", CoachTools.NAMESPACE); put("arguments", it.arguments); put("status", "completed")
            }
        }
        return CoachInferenceResult(MODEL, text, toolCalls, items.map { it.toString() })
    }

    /** Trust boundary for model text: the JSON object, optionally in a ```json fence; anything else is Malformed. */
    fun parseTurn(json: String): LocalTurn = decode(json, LocalTurn.serializer())

    /** `{"option": n}` with n in 0..5. */
    fun parsePick(json: String): Int {
        val option = decode(json, Pick.serializer()).option
        if (option !in 0..5) throw ResponsesClient.Failure.Malformed("pick")
        return option
    }

    @Serializable private class Pick(val option: Int)

    private fun <T> decode(json: String, serializer: kotlinx.serialization.KSerializer<T>): T {
        val body = json.trim().removePrefix("```json").removePrefix("```").removeSuffix("```").trim()
        try {
            return lenient.decodeFromString(serializer, body)
        } catch (_: SerializationException) {
            throw ResponsesClient.Failure.Malformed("model output")
        } catch (_: IllegalArgumentException) {
            throw ResponsesClient.Failure.Malformed("model output")
        }
    }

    private const val MARKER = "Context: "
}
