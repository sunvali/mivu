package com.yakov103.mivu.coach

import com.yakov103.mivu.diary.FoodItem
import com.yakov103.mivu.diary.SwiftJson
import com.yakov103.mivu.diary.WorkoutDraft
import com.yakov103.mivu.diary.WorkoutExercise
import com.yakov103.mivu.diary.fingerprint
import com.yakov103.mivu.diary.swift
import java.math.BigDecimal
import java.math.MathContext
import java.math.RoundingMode
import java.time.Instant
import kotlin.math.abs
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject

// Port of ios/Mivu/Coach/CoachWriteFingerprint.swift. The digest covers Foundation JSONSerialization bytes, so
// swiftJSONSerialization reproduces them: sorted keys, "\/" escapes and "%.17g" doubles (0.1 -> 0.10000000000000001).

fun CoachWrite.commandFingerprint(): String {
    fun nullable(value: Any?) = CoachTools.json(value)
    fun foods(items: List<FoodItem>) = items.map { item ->
        // The estimating model is a label, not the command: a retry by the other model must match its receipt.
        JsonObject(SwiftJson.encodeToJsonElement(FoodItem.serializer(), item).jsonObject - "id" - "estimatedBy")
    }
    fun workout(draft: WorkoutDraft) = mapOf("kind" to draft.kind.name, "duration" to draft.durationMinutes,
        "exercises" to draft.exercises.map { SwiftJson.encodeToJsonElement(WorkoutExercise.serializer(), it) },
        "burn" to nullable(draft.estimatedBurnKcal), "source" to nullable(draft.burnSource?.name))
    fun referenceSeconds(at: Instant) = (at.epochSecond - 978_307_200L) + at.nano / 1e9

    val arguments: Any? = when (this) {
        is CoachWrite.Food -> mapOf("date" to date, "items" to foods(items), "time" to nullable(eatenAt?.let(::referenceSeconds)), "review" to reviewFirst)
        // correct_item supplies quantity only; copied live nutrition is grounding, not new intent.
        is CoachWrite.Correction -> mapOf("quantity" to item.quantity, "revision" to revision)
        is CoachWrite.Close -> completeness.name
        is CoachWrite.Weight -> mapOf("value" to value, "unit" to unit, "revision" to nullable(revision))
        is CoachWrite.CorrectWeight -> mapOf("value" to value, "unit" to unit, "revision" to revision)
        is CoachWrite.Workout -> workout(draft)
        is CoachWrite.EditWorkout -> mapOf("workout" to workout(draft), "revision" to revision)
        is CoachWrite.DeleteWeight -> revision
        is CoachWrite.DeleteWorkout -> revision
        is CoachWrite.Manual -> {
            var result: Map<String, Any?> = when (val edit = edit) {
                is CoachManualEdit.Item -> buildMap {
                    put("revision", edit.revision); put("submission", nullable(edit.submissionID?.swift))
                    if (edit.item.name != edit.original.name) put("name", edit.item.name)
                    if (edit.item.unit != edit.original.unit) put("unit", edit.item.unit)
                    if (edit.item.quantity != edit.original.quantity) put("quantity", edit.item.quantity)
                    val n = edit.item.nutrition
                    for ((key, value) in listOf("kcal" to n.kcal, "carbs" to n.carbs, "protein" to n.protein, "fat" to n.fat)) {
                        if (key in edit.explicitNutrients) put(key, nullable(value))
                    }
                }
                is CoachManualEdit.Append -> mapOf("items" to foods(edit.items), "revision" to edit.revision)
                is CoachManualEdit.Accept -> mapOf("revision" to edit.revision)
                is CoachManualEdit.DeleteMeal -> mapOf("revision" to edit.revision)
                is CoachManualEdit.DeletePhoto -> mapOf("revision" to edit.revision)
                is CoachManualEdit.Retry -> mapOf("revision" to edit.revision)
                is CoachManualEdit.StartDay -> mapOf("revision" to edit.revision)
                is CoachManualEdit.DeleteItem -> mapOf("item" to edit.itemID.swift, "revision" to edit.revision)
                is CoachManualEdit.ScaleMeal -> mapOf("target" to edit.targetKcal, "revision" to edit.revision)
                is CoachManualEdit.Move -> mapOf("date" to edit.date, "revision" to edit.revision)
                is CoachManualEdit.Attach -> mapOf("photos" to edit.photoIDs.map { it.swift }.sorted(), "role" to edit.role.name, "revision" to edit.revision)
                is CoachManualEdit.Goals -> mapOf(
                    "targets" to edit.targets.sortedBy { it.nutrient }.map { mapOf("nutrient" to it.nutrient, "value" to nullable(it.value)) },
                    "weight" to nullable(edit.weight), "clear" to edit.clearWeight, "credit" to nullable(edit.exerciseCredit), "revision" to nullable(edit.revision))
                is CoachManualEdit.Preferences -> mapOf("timezone" to nullable(edit.timezone), "text" to nullable(edit.text), "revision" to edit.revision)
                is CoachManualEdit.Coverage -> mapOf("coverage" to edit.completeness.name)
                is CoachManualEdit.Undo, is CoachManualEdit.Open -> emptyMap()
            }
            // Parser patch keys preserve explicit supplied fields even when current values later match.
            patchKey?.let { key -> result = result.filterKeys { it in setOf("revision", "submission") } + ("patch" to key) }
            result
        }
    }
    val payload = mapOf("domain" to "mivu.coach.command.v1", "target" to target, "arguments" to arguments)
    return fingerprint(swiftJSONSerialization(CoachTools.json(payload)))
}

/** Foundation `JSONSerialization.data(withJSONObject:options: .sortedKeys)` text for [value]. */
internal fun swiftJSONSerialization(value: JsonElement): String = StringBuilder().also { write(value, it) }.toString()

private fun write(value: JsonElement, out: StringBuilder) {
    when (value) {
        is JsonObject -> {
            out.append('{')
            // Foundation's sortedKeys order ignores case first; Coach keys are lowercase ASCII.
            value.entries.sortedWith(compareBy({ it.key.lowercase() }, { it.key })).forEachIndexed { i, (key, element) ->
                if (i > 0) out.append(',')
                string(key, out); out.append(':'); write(element, out)
            }
            out.append('}')
        }
        is JsonArray -> {
            out.append('[')
            value.forEachIndexed { i, element -> if (i > 0) out.append(','); write(element, out) }
            out.append(']')
        }
        is JsonNull -> out.append("null")
        is JsonPrimitive -> when {
            value.isString -> string(value.content, out)
            value.content == "true" || value.content == "false" -> out.append(value.content)
            value.content.none { it == '.' || it == 'e' || it == 'E' } -> out.append(value.content) // integers stay integers
            else -> out.append(cDouble17g(value.content.toDouble()))
        }
    }
}

private fun string(text: String, out: StringBuilder) {
    out.append('"')
    for (c in text) {
        val escaped = when (c) {
            '"' -> "\\\""
            '\\' -> "\\\\"
            '/' -> "\\/"
            '\b' -> "\\b"
            '\u000C' -> "\\f"
            '\n' -> "\\n"
            '\r' -> "\\r"
            '\t' -> "\\t"
            else -> if (c < ' ') "\\u%04x".format(c.code) else null
        }
        if (escaped != null) out.append(escaped) else out.append(c)
    }
    out.append('"')
}

/** C `printf("%.17g")`, which Foundation uses for doubles. */
internal fun cDouble17g(value: Double): String {
    if (value == 0.0) return if (1 / value < 0) "-0" else "0"
    val rounded = BigDecimal(value).round(MathContext(17, RoundingMode.HALF_EVEN))
    val exponent = rounded.precision() - rounded.scale() - 1
    if (exponent in -4..16) return rounded.stripTrailingZeros().toPlainString()
    val digits = rounded.unscaledValue().abs().toString().trimEnd('0')
    val mantissa = digits.first() + if (digits.length > 1) "." + digits.substring(1) else ""
    return (if (value < 0) "-" else "") + mantissa + "e" + (if (exponent < 0) "-" else "+") + abs(exponent).toString().padStart(2, '0')
}
