package com.yakov103.mivu.coach

import com.yakov103.mivu.diary.CoachClarification
import com.yakov103.mivu.diary.CoachMealCandidate
import com.yakov103.mivu.diary.CoachReceipt
import com.yakov103.mivu.diary.CoachReply
import com.yakov103.mivu.diary.DayCompleteness
import com.yakov103.mivu.diary.FoodItem
import com.yakov103.mivu.diary.NutritionProvenance
import com.yakov103.mivu.diary.NutritionValues
import com.yakov103.mivu.diary.WorkoutBurnSource
import com.yakov103.mivu.diary.WorkoutDraft
import com.yakov103.mivu.diary.WorkoutExercise
import com.yakov103.mivu.diary.WorkoutKind
import com.yakov103.mivu.diary.WorkoutSession
import com.yakov103.mivu.diary.WorkoutSet
import com.yakov103.mivu.diary.atMost
import com.yakov103.mivu.diary.blankLikeSwift
import com.yakov103.mivu.diary.swift
import com.yakov103.mivu.diary.strictJsonContainer
import com.yakov103.mivu.diary.swiftUUID
import com.yakov103.mivu.diary.validLocalDate
import com.yakov103.mivu.diary.validateItems
import java.time.Instant
import java.time.OffsetDateTime
import java.util.UUID
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull

// Port of ios/Mivu/Coach/CoachTools.swift: CoachWrite (:6), CoachCommand (:47), declarations (:76-115), parse (:116-276).

/** A resumed turn that already committed writes may only replay them (iOS CoachEngine.run). */
@Suppress("EnumEntryName") // iOS case names
enum class CoachWriteMode { uninterrupted, replayOnly }

sealed interface CoachWrite {
    data class Manual(val edit: CoachManualEdit, val patchKey: String? = null) : CoachWrite
    data class Food(val date: String, val items: List<FoodItem>, val eatenAt: Instant?, val reviewFirst: Boolean = false) : CoachWrite
    data class Correction(val mealID: UUID, val item: FoodItem, val revision: Int) : CoachWrite
    data class Close(val date: String, val completeness: DayCompleteness) : CoachWrite
    data class Weight(val date: String, val value: Double, val unit: String, val revision: Int?) : CoachWrite
    data class CorrectWeight(val id: UUID, val value: Double, val unit: String, val revision: Int) : CoachWrite
    data class Workout(val date: String, val draft: WorkoutDraft) : CoachWrite
    data class EditWorkout(val id: UUID, val draft: WorkoutDraft, val revision: Int) : CoachWrite
    data class DeleteWeight(val id: UUID, val revision: Int) : CoachWrite
    data class DeleteWorkout(val id: UUID, val revision: Int) : CoachWrite

    val target: String get() = when (this) {
        is Manual -> edit.target + (patchKey?.let { "/$it" } ?: "")
        is Food -> "food/$date"
        is Correction -> "correct/${mealID.swift}/${item.id.swift}"
        is Close -> "close/$date"
        is Weight -> "weight/$date"
        is CorrectWeight -> "correct_weight/${id.swift}"
        is Workout -> "workout/$date"
        is EditWorkout -> "edit_workout/${id.swift}"
        is DeleteWeight -> "delete_weight/${id.swift}"
        is DeleteWorkout -> "delete_workout/${id.swift}"
    }
}

sealed interface CoachCommand {
    data class Clarification(val kind: CoachClarification, val candidates: List<CoachReply.Target>) : CoachCommand
    data class Goals(val date: String) : CoachCommand
    object Preferences : CoachCommand
    object Context : CoachCommand
    data class Meal(val id: UUID) : CoachCommand
    data class Meals(val date: String, val afterMealID: UUID?) : CoachCommand
    data class FindMeals(val query: String, val from: String?, val to: String?) : CoachCommand
    data class Lookup(val query: String) : CoachCommand
    data class Progress(val endingOn: String, val days: Int) : CoachCommand
    data class Workout(val id: UUID) : CoachCommand
    data class Write(val write: CoachWrite) : CoachCommand

    /** New foods remember the model that estimated them; edits keep the food's original source. */
    fun estimatedBy(model: String): CoachCommand {
        fun tag(items: List<FoodItem>) = items.map { it.copy(estimatedBy = model) }
        val write = (this as? Write)?.write
        return when {
            write is CoachWrite.Food -> Write(write.copy(items = tag(write.items)))
            write is CoachWrite.Manual && write.edit is CoachManualEdit.Append ->
                Write(write.copy(edit = write.edit.copy(items = tag(write.edit.items))))
            else -> this
        }
    }
}

/** Only declared operations cross the model-to-diary boundary. */
object CoachTools {
    const val NAMESPACE = "mivu"

    /** Swift-literal schema values (maps, lists, strings, numbers, booleans, null) as JSON. */
    internal fun json(value: Any?): JsonElement = when (value) {
        null -> JsonNull
        is JsonElement -> value
        is String -> JsonPrimitive(value)
        is Number -> JsonPrimitive(value)
        is Boolean -> JsonPrimitive(value)
        is List<*> -> JsonArray(value.map(::json))
        is Map<*, *> -> JsonObject(value.entries.associate { it.key as String to json(it.value) })
        else -> error("unsupported schema value")
    }

    /** Strict mode lists every key as required; optional ones accept null instead. */
    internal fun obj(properties: Map<String, Any?>, required: List<String>): Map<String, Any?> {
        val normalized = properties.mapValues { (key, value) ->
            if (key in required || value !is Map<*, *>) return@mapValues value
            val types = when (val type = value["type"]) { is List<*> -> type; null -> emptyList(); else -> listOf(type) }
            value + ("type" to if ("null" in types) types else types + "null")
        }
        return mapOf("type" to "object", "properties" to normalized, "required" to properties.keys.sorted(), "additionalProperties" to false)
    }

    fun declarations(): JsonObject {
        val string = mapOf("type" to "string")
        val number = mapOf("type" to listOf("number", "null"))
        val food = obj(mapOf("name" to string, "quantity" to mapOf("type" to "number"), "unit" to string,
            "kcal" to number, "carbs" to number, "protein" to number, "fat" to number,
            "evidence_id" to mapOf("type" to listOf("integer", "null"))), listOf("name", "quantity", "unit", "kcal", "carbs", "protein", "fat"))
        val integer = mapOf("type" to "integer")
        val unconfirmedTime = mapOf("type" to "string", "description" to "Use null when no time was supplied. A valid local date or ISO 8601 string is accepted for compatibility but ignored; it cannot change the requested tracking day or establish an exact time.")
        val exercise = obj(mapOf("name" to string, "sets" to mapOf("type" to "array", "items" to obj(mapOf("repetitions" to integer, "load_kg" to number), listOf("repetitions", "load_kg")))), listOf("name", "sets"))
        val workout = mapOf("kind" to mapOf("type" to "string", "enum" to WorkoutKind.entries.map { it.name }), "duration_minutes" to integer, "exercises" to mapOf("type" to "array", "items" to exercise), "estimated_burn_kcal" to number, "burn_source" to mapOf("type" to listOf("string", "null"), "enum" to listOf("userEstimate", "modelEstimate", null)), "performed_at" to unconfirmedTime)
        val schemas: List<Triple<String, String, Map<String, Any?>>> = listOf(
            Triple("ask_clarification", "Ask before logging only when food, serving, day or an existing record is genuinely ambiguous. Unknown exact grams or milliliters alone do not block a clearly labelled estimate from text, photos or a clear matching committed portion. Choose portion for an ambiguous serving, food for food identity, day for the recording date, meal or workout for an ambiguous existing record. Use this tool alone, before any writes in this turn. Add candidates (at most 4 real meal_id, optional item_id) when the choice is among known records. Use kind confirm with exactly one meal candidate (meal_id only) before deleting a whole meal. The app displays its own question; the user answers in a new turn.", obj(mapOf("kind" to mapOf("type" to "string", "enum" to CoachClarification.entries.map { it.name }), "candidates" to mapOf("type" to "array", "maxItems" to 4, "items" to obj(mapOf("meal_id" to string, "item_id" to string), listOf("meal_id")))), listOf("kind"))),
            Triple("get_progress", "Read actual progress for an inclusive 1, 7 or 30 calendar-day window. Real record IDs/revisions and omitted counts support historical corrections. Food remaining and estimated burn are separate; adherence means Within 10% of target.", obj(mapOf("ending_on" to string, "days" to mapOf("type" to "integer", "enum" to listOf(1, 7, 30))), listOf("ending_on", "days"))),
            Triple("get_workout", "Read a complete owned workout before replacement/edit. Oversized records are refused; never replace unseen sets.", obj(mapOf("workout_id" to string), listOf("workout_id"))),
            Triple("log_weight", "Log one weight per date. Corrections require expected_revision; historical correction after travel must use retrieved weight_id, preserving day and measured time. Model measured_at cannot confirm exact time. Current morning weight explicitly starts that waking day.", obj(mapOf("local_date" to string, "value" to mapOf("type" to "number"), "unit" to mapOf("type" to "string", "enum" to listOf("kg", "lb")), "weight_id" to string, "expected_revision" to integer, "measured_at" to unconfirmedTime), listOf("local_date", "value", "unit"))),
            Triple("log_workout", "Log one new session per turn/date; another session needs another turn. Timestamps are unconfirmed date-only. Estimated burn stays separate from food.", obj(workout + ("local_date" to string), listOf("local_date", "kind", "duration_minutes", "exercises"))),
            Triple("edit_workout", "Replace a complete retrieved workout using its real ID/revision. Preserve its day/time; include all existing sets that should remain.", obj(workout + mapOf("workout_id" to string, "expected_revision" to integer), listOf("workout_id", "expected_revision", "kind", "duration_minutes", "exercises"))),
            Triple("delete_workout", "Delete an owned workout with its actual revision.", obj(mapOf("workout_id" to string, "expected_revision" to integer), listOf("workout_id", "expected_revision"))),
            Triple("delete_weight", "Delete an owned weight with its actual revision.", obj(mapOf("weight_id" to string, "expected_revision" to integer), listOf("weight_id", "expected_revision"))),
            Triple("get_context", "Read actual bounded diary and capture clock. truncated and omittedMeals explicitly mark details not included.", obj(emptyMap(), emptyList())),
            Triple("get_meals_for_date", "Read at most 20 actual dated meal candidates across matching diary days. Use captured calendar date and original description to identify lunch; date-only noon is not evidence. hasMore and omissions cannot establish uniqueness. Retrieve get_meal before correction.", obj(mapOf("target_local_date" to string, "after_meal_id" to string), listOf("target_local_date"))),
            Triple("find_meals", "Search saved meals by food name, newest first, at most 10 candidates with their dates. Optional inclusive from_date/to_date local dates. Use for older references; call get_meal on the chosen meal before any edit or delete of it.", obj(mapOf("query" to string, "from_date" to string, "to_date" to string), listOf("query"))),
            Triple("get_meal", "Retrieve actual owner-scoped meal by UUID before correction. omittedItemCount marks unavailable details requiring manual review.", obj(mapOf("meal_id" to string), listOf("meal_id"))),
            Triple("lookup_nutrition", "Search retrieved nutrition evidence; unavailable means use clearly uncertain estimates.", obj(mapOf("query" to string), listOf("query"))),
            Triple("log_food", "Log all new foods for this turn/date once, keeping new intake distinct from earlier reviews. For a clear repeat, reuse the most recent matching committed quantity/unit as an uncertain estimate, never an unaccepted proposal. Explicit current amounts or labels and visible changed food or serving override history; a same-food photo without a measurable amount keeps a clear matching committed portion. Interpret photos with their description. For photo-only intake, estimate the visible serving first, then a labelled typical serving when identified but unmeasurable, without claiming unseen mixture ratios are verified. On a saved manual meal append only newly named foods, preserving every existing item; correct existing foods with correct_item. Nutrition numbers are portion totals; only retrieved evidence_id with grams replaces estimates. Direct chat remains date-only; exact time requires a manual UI capture. Set review_first true when the user wants a proposal before totals. Optional eaten_at is accepted for compatibility but cannot establish a confirmed time.", obj(mapOf("target_local_date" to string, "items" to mapOf("type" to "array", "items" to food), "eaten_at" to unconfirmedTime, "review_first" to mapOf("type" to "boolean")), listOf("target_local_date", "items"))),
            Triple("correct_item", "Correct only quantity on a retrieved actual item, preserving its nutrition basis and sources.", obj(mapOf("meal_id" to string, "item_id" to string, "expected_revision" to mapOf("type" to "integer"), "quantity" to mapOf("type" to "number")), listOf("meal_id", "item_id", "expected_revision", "quantity"))),
        ) + manualSchemas(food)
        val tools = schemas.map { (name, description, parameters) ->
            mapOf("type" to "function", "name" to name, "description" to description, "parameters" to parameters, "strict" to true)
        }
        return json(mapOf("type" to "namespace", "name" to NAMESPACE, "description" to "Private local diary and progress operations", "tools" to tools)) as JsonObject
    }

    /** Arguments as the model sent them; every rule is iOS's, and anything else is refused before any write. */
    internal class Args(private val values: JsonObject) {
        val keys get() = values.keys
        operator fun get(key: String): JsonElement? = values[key]
        fun present(key: String) = values[key].let { it != null && it !is JsonNull }
        fun keys(allowed: Set<String>, required: Set<String>) {
            if (!allowed.containsAll(keys) || !keys.containsAll(required)) throw CoachError.InvalidArguments
        }
        fun text(key: String): String? = (values[key] as? JsonPrimitive)?.takeIf { it.isString }?.content
        fun bool(key: String): Boolean? = values[key]?.let(::bool)
    }

    private fun invalid(): Nothing = throw CoachError.InvalidArguments
    internal fun bool(value: JsonElement): Boolean? = (value as? JsonPrimitive)?.takeIf { !it.isString && it !is JsonNull }?.booleanOrNull
    internal fun number(value: JsonElement?): Double? {
        val primitive = value as? JsonPrimitive ?: return null
        if (primitive.isString || primitive is JsonNull || bool(primitive) != null) return null
        return primitive.content.toDoubleOrNull()?.takeIf { it.isFinite() }
    }
    private fun rows(value: JsonElement?): List<Args>? =
        (value as? JsonArray)?.map { Args(it as? JsonObject ?: return null) }
    private fun utf8(text: String) = text.toByteArray(Charsets.UTF_8).size

    private fun wellFormedText(e: JsonElement): Boolean = when (e) {
        is JsonObject -> e.all { (key, value) -> wellFormed(key) && wellFormedText(value) }
        is JsonArray -> e.all(::wellFormedText)
        is JsonPrimitive -> !e.isString || wellFormed(e.content)
    }
    private fun wellFormed(text: String): Boolean {
        var i = 0
        while (i < text.length) {
            val c = text[i]
            if (Character.isHighSurrogate(c) && i + 1 < text.length && Character.isLowSurrogate(text[i + 1])) i += 2
            else if (Character.isSurrogate(c)) return false
            else i++
        }
        return true
    }

    private val isoInstant = Regex("""\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:?\d{2})""")

    fun parse(
        call: CoachToolCall,
        meals: List<CoachContext.Meal>,
        receipts: List<CoachReceipt>,
        workouts: List<WorkoutSession> = emptyList(),
        found: List<CoachMealCandidate> = emptyList(),
    ): CoachCommand {
        if (call.namespace != NAMESPACE || utf8(call.arguments) > 65_536) throw CoachError.InvalidTool
        // kotlinx parsing is lenient (True, 7d, +7); refuse what JSONSerialization refuses, including lone surrogates.
        val parsed = if (strictJsonContainer(call.arguments)) runCatching { Json.parseToJsonElement(call.arguments) }.getOrNull() else null
        val args = Args(parsed?.takeIf(::wellFormedText) as? JsonObject ?: throw CoachError.InvalidTool)
        fun string(name: String): String = args.text(name)?.takeIf { it.isNotEmpty() && utf8(it) <= 500 } ?: invalid()
        fun uuid(name: String): UUID = swiftUUID(string(name)) ?: invalid()
        fun date(name: String): String = string(name).takeIf(::validLocalDate) ?: invalid()
        fun integer(name: String, range: IntRange): Int {
            val value = number(args[name]) ?: invalid()
            if (Math.rint(value) != value || value < range.first || value > range.last) invalid()
            return value.toInt()
        }
        fun revision() = integer("expected_revision", 1..999_999)
        fun unconfirmedTime(name: String) {
            if (!args.present(name)) return
            val value = args.text(name) ?: invalid()
            // shortcut: ISO8601DateFormatter's internet date-time, with or without fractional seconds, by pattern plus a calendar check.
            val valid = validLocalDate(value) || isoInstant.matches(value) && runCatching {
                OffsetDateTime.parse(value.replace(Regex("""([+-]\d{2})(\d{2})$"""), "$1:$2"))
            }.isSuccess
            if (!valid) invalid()
        }
        fun draft(): WorkoutDraft {
            val kind = WorkoutKind.entries.firstOrNull { it.name == string("kind") } ?: invalid()
            val exerciseRows = rows(args["exercises"])?.takeIf { it.size <= 100 } ?: invalid()
            val exercises = exerciseRows.map { row ->
                val name = row.text("name")
                val sets = rows(row["sets"])
                if (row.keys != setOf("name", "sets") || name == null || name.blankLikeSwift() || !name.atMost(200) ||
                    sets == null || sets.size > 100) invalid()
                WorkoutExercise(name, sets.map { set ->
                    val reps = number(set["repetitions"])
                    if (!setOf("repetitions", "load_kg").containsAll(set.keys) || reps == null || Math.rint(reps) != reps || reps !in 1.0..10_000.0) invalid()
                    val load = if (set.present("load_kg")) number(set["load_kg"])?.takeIf { it in 0.0..100_000.0 } ?: invalid() else null
                    WorkoutSet(reps.toInt(), load)
                })
            }
            val burn = if (args.present("estimated_burn_kcal")) number(args["estimated_burn_kcal"])?.takeIf { it in 0.0..100_000.0 } ?: invalid() else null
            val source = if (args.present("burn_source")) {
                val value = args.text("burn_source")
                WorkoutBurnSource.entries.firstOrNull { it.name == value }?.takeIf { burn != null } ?: invalid()
            } else null
            unconfirmedTime("performed_at")
            return WorkoutDraft(kind, integer("duration_minutes", 1..1440), exercises, burn, source)
        }
        return when (call.name) {
            "ask_clarification" -> {
                args.keys(setOf("kind", "candidates"), setOf("kind"))
                val kind = CoachClarification.entries.firstOrNull { it.name == string("kind") } ?: invalid()
                val candidates = if (!args.present("candidates")) emptyList() else {
                    val list = rows(args["candidates"])?.takeIf { it.size <= 4 } ?: invalid()
                    list.map { row ->
                        // Meals found by search this turn are real records too; edits still require get_meal.
                        val id = row.text("meal_id")?.let(::swiftUUID)
                        val items = meals.firstOrNull { it.id == id }?.items?.map { it.id }
                            ?: found.firstOrNull { it.id == id }?.items?.map { it.id }
                        if (!setOf("meal_id", "item_id").containsAll(row.keys) || id == null || items == null) invalid()
                        if (!row.present("item_id")) return@map CoachReply.Target.Meal(id)
                        val item = row.text("item_id")?.let(::swiftUUID)?.takeIf { it in items } ?: invalid()
                        if (kind == CoachClarification.confirm) CoachReply.Target.Meal(id) else CoachReply.Target.Item(id, item)
                    }
                }
                // Removing a whole meal needs one explicit meal to name; a named food stands for its meal.
                if (kind == CoachClarification.confirm && candidates.size != 1) invalid()
                CoachCommand.Clarification(kind, candidates)
            }
            "get_progress" -> {
                args.keys(setOf("ending_on", "days"), setOf("ending_on", "days"))
                val days = integer("days", 1..30).takeIf { it in setOf(1, 7, 30) } ?: invalid()
                CoachCommand.Progress(date("ending_on"), days)
            }
            "get_workout" -> { args.keys(setOf("workout_id"), setOf("workout_id")); CoachCommand.Workout(uuid("workout_id")) }
            "log_weight" -> {
                args.keys(setOf("local_date", "value", "unit", "weight_id", "expected_revision", "measured_at"), setOf("local_date", "value", "unit"))
                val label = date("local_date")
                val unit = string("unit")
                val value = number(args["value"])
                if (value == null || value <= 0 || value > 1500 || unit !in setOf("kg", "lb")) invalid()
                unconfirmedTime("measured_at")
                if (args.present("weight_id")) return CoachCommand.Write(CoachWrite.CorrectWeight(uuid("weight_id"), value, unit, revision()))
                CoachCommand.Write(CoachWrite.Weight(label, value, unit, if (args.present("expected_revision")) revision() else null))
            }
            "log_workout", "edit_workout" -> {
                val fields = setOf("kind", "duration_minutes", "exercises", "estimated_burn_kcal", "burn_source", "performed_at")
                if (call.name == "log_workout") {
                    args.keys(fields + "local_date", setOf("local_date", "kind", "duration_minutes", "exercises"))
                    return CoachCommand.Write(CoachWrite.Workout(date("local_date"), draft()))
                }
                args.keys(fields + setOf("workout_id", "expected_revision"), setOf("workout_id", "expected_revision", "kind", "duration_minutes", "exercises"))
                val id = uuid("workout_id")
                val expected = revision()
                if (workouts.none { it.id == id && it.revision == expected } &&
                    receipts.none { it.workoutID == id && it.operationKey.endsWith("/edit_workout/" + id.swift) }) invalid()
                CoachCommand.Write(CoachWrite.EditWorkout(id, draft(), expected))
            }
            "delete_weight" -> {
                args.keys(setOf("weight_id", "expected_revision"), setOf("weight_id", "expected_revision"))
                CoachCommand.Write(CoachWrite.DeleteWeight(uuid("weight_id"), revision()))
            }
            "delete_workout" -> {
                args.keys(setOf("workout_id", "expected_revision"), setOf("workout_id", "expected_revision"))
                CoachCommand.Write(CoachWrite.DeleteWorkout(uuid("workout_id"), revision()))
            }
            "get_context" -> { args.keys(emptySet(), emptySet()); CoachCommand.Context }
            "get_meal" -> { args.keys(setOf("meal_id"), setOf("meal_id")); CoachCommand.Meal(uuid("meal_id")) }
            "lookup_nutrition" -> {
                args.keys(setOf("query"), setOf("query"))
                CoachCommand.Lookup(string("query").takeIf { utf8(it) <= 200 } ?: invalid())
            }
            "log_food" -> {
                args.keys(setOf("target_local_date", "items", "eaten_at", "review_first"), setOf("target_local_date", "items"))
                val items = foodItems(args["items"])
                // Validate legacy syntax without treating model output as owner-confirmed time.
                unconfirmedTime("eaten_at")
                val reviewFirst = if (args.present("review_first")) args.bool("review_first") ?: invalid() else false
                CoachCommand.Write(CoachWrite.Food(string("target_local_date"), items, null, reviewFirst))
            }
            "get_meals_for_date" -> {
                args.keys(setOf("target_local_date", "after_meal_id"), setOf("target_local_date"))
                val cursor = if (args.present("after_meal_id")) uuid("after_meal_id") else null
                CoachCommand.Meals(date("target_local_date"), cursor)
            }
            "find_meals" -> {
                args.keys(setOf("query", "from_date", "to_date"), setOf("query"))
                val query = string("query").takeIf { it.atMost(100) } ?: invalid()
                fun optionalDate(key: String) = if (args.present(key)) date(key) else null
                CoachCommand.FindMeals(query, optionalDate("from_date"), optionalDate("to_date"))
            }
            "correct_item" -> {
                args.keys(setOf("meal_id", "item_id", "expected_revision", "quantity"), setOf("meal_id", "item_id", "expected_revision", "quantity"))
                val mealID = uuid("meal_id")
                val itemID = uuid("item_id")
                val revision = number(args["expected_revision"])?.takeIf { it >= 0 && it < 1_000_000 && Math.rint(it) == it } ?: invalid()
                val meal = meals.firstOrNull { it.id == mealID } ?: invalid()
                if (meal.revision != revision.toInt() && receipts.none { it.mealID == mealID && it.itemID == itemID }) invalid()
                val item = meal.items.firstOrNull { it.id == itemID } ?: invalid()
                val quantity = number(args["quantity"]) ?: invalid()
                val corrected = item.copy(quantity = quantity).also { validateItems(listOf(it)) }
                CoachCommand.Write(CoachWrite.Correction(mealID, corrected, revision.toInt()))
            }
            else -> parseManual(call, args, meals, receipts)
        }
    }

    // shortcut: Android has no nutrition evidence source yet, so any evidence_id is refused as iOS refuses an unknown one.
    internal fun foodItems(raw: JsonElement?): List<FoodItem> {
        val list = rows(raw)?.takeIf { it.isNotEmpty() && it.size <= 200 } ?: invalid()
        return list.map { row ->
            val name = row.text("name")
            val quantity = number(row["quantity"])
            val unit = row.text("unit")
            if (!setOf("name", "quantity", "unit", "kcal", "carbs", "protein", "fat", "evidence_id").containsAll(row.keys) ||
                name == null || quantity == null || unit == null) invalid()
            fun nutrient(key: String): Double? = if (!row.present(key)) null else number(row[key]) ?: invalid()
            if (row.present("evidence_id")) invalid()
            FoodItem(UUID.randomUUID(), name, quantity, unit, NutritionValues(nutrient("kcal"), nutrient("carbs"), nutrient("protein"), nutrient("fat")),
                NutritionProvenance.estimate, "Unverified portion estimate", true, emptyMap()).also { validateItems(listOf(it)) }
        }
    }
}
