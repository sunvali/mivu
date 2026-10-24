package com.yakov103.mivu.coach

import com.yakov103.mivu.diary.CoachDestination
import com.yakov103.mivu.diary.CoachReceipt
import com.yakov103.mivu.diary.DayCompleteness
import com.yakov103.mivu.diary.FoodItem
import com.yakov103.mivu.diary.NutritionValues
import com.yakov103.mivu.diary.PhotoRole
import com.yakov103.mivu.diary.atMost
import com.yakov103.mivu.diary.blankLikeSwift
import com.yakov103.mivu.diary.fingerprint
import com.yakov103.mivu.diary.swift
import com.yakov103.mivu.diary.swiftUUID
import com.yakov103.mivu.diary.validLocalDate
import com.yakov103.mivu.diary.validZone
import com.yakov103.mivu.diary.validateItems
import java.util.UUID
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

// Port of ios/Mivu/Coach/CoachManualEdits.swift: CoachManualEdit (:10-55), manualSchemas (:58-87), parseManual (:88-232).

data class CoachNutrientEdit(val nutrient: String, val value: Double?)

sealed interface CoachManualEdit {
    data class Item(override val mealID: UUID, val item: FoodItem, val revision: Int, val submissionID: UUID?, val explicitNutrients: Set<String>, val original: FoodItem) : CoachManualEdit
    data class Append(override val mealID: UUID, val items: List<FoodItem>, val revision: Int) : CoachManualEdit
    data class Accept(override val mealID: UUID, val submissionID: UUID, val revision: Int) : CoachManualEdit
    data class Move(override val mealID: UUID, val date: String, val revision: Int, val originalDayID: UUID) : CoachManualEdit
    data class DeleteMeal(override val mealID: UUID, val revision: Int) : CoachManualEdit
    data class DeleteItem(override val mealID: UUID, val itemID: UUID, val revision: Int) : CoachManualEdit
    data class ScaleMeal(override val mealID: UUID, val targetKcal: Double, val revision: Int) : CoachManualEdit
    data class Attach(override val mealID: UUID, val photoIDs: List<UUID>, val role: PhotoRole, val revision: Int) : CoachManualEdit
    data class DeletePhoto(override val mealID: UUID, val photoID: UUID, val revision: Int) : CoachManualEdit
    data class Retry(override val mealID: UUID, val revision: Int) : CoachManualEdit
    data class Goals(val date: String, val targets: List<CoachNutrientEdit>, val weight: Double?, val clearWeight: Boolean, val exerciseCredit: Boolean?, val revision: Int?) : CoachManualEdit
    data class Preferences(val timezone: String?, val text: String?, val revision: Int) : CoachManualEdit
    data class StartDay(val revision: Int) : CoachManualEdit
    data class Coverage(val date: String, val completeness: DayCompleteness) : CoachManualEdit
    data class Undo(val operationKey: String) : CoachManualEdit
    data class Open(val destination: CoachDestination) : CoachManualEdit

    val mealID: UUID? get() = null

    val target: String get() = when (this) {
        is Item -> "edit_item/${mealID.swift}/${submissionID?.swift ?: "saved"}/${item.id.swift}"
        is Append -> "append_food/${mealID.swift}"
        is Accept -> "accept_review/${mealID.swift}/${submissionID.swift}"
        is Move -> "move_meal/${mealID.swift}"
        is DeleteMeal -> "delete_meal/${mealID.swift}"
        is DeleteItem -> "delete_item/${mealID.swift}/${itemID.swift}"
        is ScaleMeal -> "scale_meal/${mealID.swift}"
        is Attach -> "attach_photos/${mealID.swift}"
        is DeletePhoto -> "delete_photo/${mealID.swift}/${photoID.swift}"
        is Retry -> "retry_meal/${mealID.swift}"
        is Goals -> "set_goals/$date"
        is Preferences -> "update_preferences"
        is StartDay -> "start_day"
        is Coverage -> "set_day_coverage/$date"
        is Undo -> "undo/$operationKey"
        is Open -> "open_settings/${destination.name}"
    }
}

fun NutritionValues.set(edit: CoachNutrientEdit): NutritionValues = when (edit.nutrient) {
    "kcal" -> copy(kcal = edit.value)
    "carbs" -> copy(carbs = edit.value)
    "protein" -> copy(protein = edit.value)
    "fat" -> copy(fat = edit.value)
    else -> this
}

internal fun manualSchemas(food: Map<String, Any?>): List<Triple<String, String, Map<String, Any?>>> {
    val obj = CoachTools::obj
    val string = mapOf("type" to "string")
    val integer = mapOf("type" to "integer")
    val number = mapOf("type" to "number")
    val boolean = mapOf("type" to "boolean")
    val nutrients = mapOf("type" to "array", "items" to obj(mapOf(
        "nutrient" to mapOf("type" to "string", "enum" to listOf("kcal", "carbs", "protein", "fat")),
        "value" to mapOf("type" to listOf("number", "null"))), listOf("nutrient", "value")))
    val meal = mapOf("meal_id" to string, "expected_revision" to integer)
    fun mealObject(extra: Map<String, Any?>, required: List<String>) = obj(meal + extra, listOf("meal_id", "expected_revision") + required)
    return listOf(
        Triple("edit_item", "Patch only named fields on a retrieved saved or review item. Null name/quantity/unit means unchanged. nutrients lists only changed nutrient totals; a null value clears that nutrient. Preserve other items. Use review_submission_id for an unaccepted proposal; this does not accept it.", mealObject(mapOf("item_id" to string, "review_submission_id" to string, "name" to string, "quantity" to number, "unit" to string, "nutrients" to nutrients), listOf("item_id"))),
        Triple("append_food", "Append only new foods to an explicitly retrieved existing saved meal; never repeat its current foods. Group all additions to this meal into one call per turn; retries replay that first addition. Returns the committed meal. Use log_food for a new meal.", mealObject(mapOf("items" to mapOf("type" to "array", "items" to food)), listOf("items"))),
        Triple("accept_review", "Save an explicitly accepted retrieved meal proposal into totals. Use its submission ID and current meal revision. Never accept an estimate just because the user requests an edit.", mealObject(mapOf("submission_id" to string), listOf("submission_id"))),
        Triple("move_meal", "Move an existing retrieved meal's tracking date to target_local_date (yyyy-MM-dd), preserving active waking day and its original capture/eating time and precision. A 04:00 meal can belong to the previous waking day.", mealObject(mapOf("target_local_date" to string), listOf("target_local_date"))),
        Triple("delete_meal", "Delete an explicitly requested retrieved meal and its photos. Use its real ID/revision; never delete to compensate for eating.", mealObject(emptyMap(), emptyList())),
        Triple("delete_item", "Delete one explicitly requested food from a retrieved saved meal using its real item ID and meal revision. If it is the meal's only food, do not call this; for the only food use ask_clarification kind confirm with that meal.", mealObject(mapOf("item_id" to string), listOf("item_id"))),
        Triple("scale_meal", "Change the whole saved meal's portions proportionally so its known calories total target_kcal (ratio 0.1 to 3 of the current total). Use for requests like \"make this meal 650 kcal\" or \"I only ate about two thirds\"; use edit_item for one food. Needs a retrieved saved meal and its revision; refused for unaccepted estimates or meals with 0 known kcal.", mealObject(mapOf("target_kcal" to number), listOf("target_kcal"))),
        Triple("attach_photos", "Attach current turn's actual attachedPhotoIDs to a retrieved meal, preserving the original photo bytes. Choose before/after only when supplied. Does not change food totals; pair with explicit food edits when needed.", mealObject(mapOf("photo_ids" to mapOf("type" to "array", "items" to string), "role" to mapOf("type" to "string", "enum" to PhotoRole.entries.map { it.name })), listOf("photo_ids", "role"))),
        Triple("delete_photo", "Delete an explicitly requested photo using a retrieved meal's photo ID and revision. Removes retained copies, without deleting the food.", mealObject(mapOf("photo_id" to string), listOf("photo_id"))),
        Triple("retry_meal", "Requeue an existing paused meal capture without creating a new meal or food record. Uses original saved input. Only the later successful analysis can confirm food saved.", mealObject(emptyMap(), emptyList())),
        Triple("get_goals", "Read exact dated goal settings and the goal effective on local_date (yyyy-MM-dd), plus diary revision. Exact goal null means use null expected_revision to create a setting for that date.", obj(mapOf("local_date" to string), listOf("local_date"))),
        Triple("get_preferences", "Read complete saved dietary preferences and timezone plus diary revision before editing. Context preferences may be truncated; do not replace omitted text.", obj(emptyMap(), emptyList())),
        Triple("set_goals", "Apply only explicit user-requested target changes, never an inferred prescription. First get_goals for this effective_local_date. targets is a patch: omitted nutrients remain; null value unsets a target. Null goal_weight_kg keeps it; clear_goal_weight true unsets it. Unspecified exercise credit remains unchanged. Existing exact date requires expected_revision; new date uses null. Returns saved settings; creates no intake day.", obj(mapOf("effective_local_date" to string, "expected_revision" to integer, "targets" to nutrients, "goal_weight_kg" to number, "clear_goal_weight" to boolean, "exercise_credit_enabled" to boolean), listOf("effective_local_date", "targets"))),
        Triple("update_preferences", "Update explicitly requested preferences/timezone after reading complete get_preferences. Null fields preserve saved values; empty preferences clears them. expected_diary_revision protects unseen concurrent changes. Does not change historical day labels, credentials, or language.", obj(mapOf("expected_diary_revision" to integer, "timezone" to string, "preferences" to string), listOf("expected_diary_revision"))),
        Triple("start_day", "Explicitly start the current waking day from the persisted capture clock. Read fresh context for expected_diary_revision. Delayed captures cannot reverse a newer waking-day choice.", obj(mapOf("expected_diary_revision" to integer), listOf("expected_diary_revision"))),
        Triple("set_day_coverage", "Mark a local date skipped so it stays out of statistics, or count it again. Days close on their own at the waking-day rollover; this never closes or activates a day.", obj(mapOf("local_date" to string, "skipped" to boolean), listOf("local_date", "skipped"))),
        Triple("undo_change", "Undo one earlier Coach food change by the operation key from its [saved key=…] line: log_food, append_food, edit_item, correct_item, scale_meal or delete_item. Restores the meal exactly as it was before that change (an undone log_food removes the meal), refused if anything changed the meal since. Not for whole-meal deletes, weights, workouts, goals or settings.", obj(mapOf("operation_key" to string), listOf("operation_key"))),
        Triple("open_settings", "Offer a native Settings link for accounts, local profiles, secrets or Files backup. The user must tap and complete the native action; this tool never authorizes, deletes a profile, restores a backup or claims those actions succeeded.", obj(mapOf("destination" to mapOf("type" to "string", "enum" to CoachDestination.entries.map { it.name })), listOf("destination"))),
    )
}

private fun invalid(): Nothing = throw CoachError.InvalidArguments

internal fun parseManual(call: CoachToolCall, args: CoachTools.Args, meals: List<CoachContext.Meal>, receipts: List<CoachReceipt>): CoachCommand {
    fun string(key: String, maximum: Int = 500, allowEmpty: Boolean = false): String =
        args.text(key)?.takeIf { it.atMost(maximum) && (allowEmpty || !it.blankLikeSwift()) } ?: invalid()
    fun id(key: String): UUID = swiftUUID(string(key)) ?: invalid()
    fun optional(key: String) = args.present(key)
    fun revision(key: String = "expected_revision", allowZero: Boolean = false): Int {
        val value = CoachTools.number(args[key]) ?: invalid()
        if (Math.rint(value) != value || value < (if (allowZero) 0.0 else 1.0) || value >= 10_000_000) invalid()
        return value.toInt()
    }
    fun date(key: String): String = string(key).takeIf(::validLocalDate) ?: invalid()
    fun bool(key: String): Boolean? = if (!optional(key)) null else args.bool(key) ?: invalid()
    fun edits(key: String): List<CoachNutrientEdit> {
        if (!optional(key)) return emptyList()
        val rows = (args[key] as? JsonArray)?.takeIf { it.size <= 4 } ?: invalid()
        val names = mutableSetOf<String>()
        return rows.map { element ->
            val row = CoachTools.Args(element as? JsonObject ?: invalid())
            val name = row.text("nutrient")
            if (row.keys != setOf("nutrient", "value") || name == null || name !in setOf("kcal", "carbs", "protein", "fat") || !names.add(name)) invalid()
            if (row["value"] is JsonNull) return@map CoachNutrientEdit(name, null)
            CoachNutrientEdit(name, CoachTools.number(row["value"])?.takeIf { it in 0.0..10_000_000.0 } ?: invalid())
        }
    }
    val mealFields = setOf("meal_id", "expected_revision")
    val write: CoachManualEdit = when (call.name) {
        "get_goals" -> { args.keys(setOf("local_date"), setOf("local_date")); return CoachCommand.Goals(date("local_date")) }
        "get_preferences" -> { args.keys(emptySet(), emptySet()); return CoachCommand.Preferences }
        "edit_item" -> {
            args.keys(mealFields + setOf("item_id", "review_submission_id", "name", "quantity", "unit", "nutrients"), mealFields + "item_id")
            val mealID = id("meal_id")
            val itemID = id("item_id")
            val expected = revision(allowZero = true)
            val submission = if (optional("review_submission_id")) id("review_submission_id") else null
            val meal = meals.firstOrNull { it.id == mealID } ?: invalid()
            val source = if (submission != null) {
                meal.review?.takeIf { it.submissionID == submission }?.items ?: invalid()
            } else meal.items
            val original = source.firstOrNull { it.id == itemID } ?: invalid()
            var item = original
            if (optional("name")) item = item.copy(name = string("name"))
            if (optional("unit")) item = item.copy(unit = string("unit", maximum = 100))
            if (optional("quantity")) item = item.copy(quantity = CoachTools.number(args["quantity"]) ?: invalid())
            val nutrients = edits("nutrients")
            if (listOf("name", "unit", "quantity").none(::optional) && nutrients.isEmpty()) invalid()
            item = item.copy(nutrition = nutrients.fold(item.nutrition) { values, edit -> values.set(edit) })
            validateItems(listOf(item))
            CoachManualEdit.Item(mealID, item, expected, submission, nutrients.map { it.nutrient }.toSet(), original)
        }
        "append_food" -> {
            args.keys(mealFields + "items", mealFields + "items")
            CoachManualEdit.Append(id("meal_id"), CoachTools.foodItems(args["items"]), revision(allowZero = true))
        }
        "accept_review" -> {
            args.keys(mealFields + "submission_id", mealFields + "submission_id")
            CoachManualEdit.Accept(id("meal_id"), id("submission_id"), revision(allowZero = true))
        }
        "move_meal" -> {
            args.keys(mealFields + "target_local_date", mealFields + "target_local_date")
            val mealID = id("meal_id")
            val meal = meals.firstOrNull { it.id == mealID } ?: invalid()
            CoachManualEdit.Move(mealID, date("target_local_date"), revision(allowZero = true), meal.dayID)
        }
        "delete_meal" -> { args.keys(mealFields, mealFields); CoachManualEdit.DeleteMeal(id("meal_id"), revision(allowZero = true)) }
        "delete_item" -> {
            args.keys(mealFields + "item_id", mealFields + "item_id")
            val mealID = id("meal_id")
            val itemID = id("item_id")
            // A committed delete replays even though the food is already gone from context.
            val replay = receipts.any { it.operationKey.endsWith("/delete_item/${mealID.swift}/${itemID.swift}") }
            val deletable = meals.firstOrNull { it.id == mealID }?.let { meal -> meal.items.any { it.id == itemID } && meal.items.size > 1 } == true
            if (!replay && !deletable) invalid()
            CoachManualEdit.DeleteItem(mealID, itemID, revision(allowZero = true))
        }
        "scale_meal" -> {
            args.keys(mealFields + "target_kcal", mealFields + "target_kcal")
            val mealID = id("meal_id")
            val target = CoachTools.number(args["target_kcal"])
            if (meals.none { it.id == mealID } || target == null || target <= 0 || target > 10_000_000) invalid()
            CoachManualEdit.ScaleMeal(mealID, target, revision(allowZero = true))
        }
        "retry_meal" -> { args.keys(mealFields, mealFields); CoachManualEdit.Retry(id("meal_id"), revision(allowZero = true)) }
        "attach_photos" -> {
            args.keys(mealFields + setOf("photo_ids", "role"), mealFields + setOf("photo_ids", "role"))
            val values = (args["photo_ids"] as? JsonArray)?.map { (it as? JsonPrimitive)?.takeIf { p -> p.isString }?.content ?: invalid() }
            if (values == null || values.isEmpty() || values.size > 30) invalid()
            val role = PhotoRole.entries.firstOrNull { it.name == string("role") } ?: invalid()
            val ids = values.map { swiftUUID(it) ?: invalid() }
            if (ids.toSet().size != ids.size) invalid()
            CoachManualEdit.Attach(id("meal_id"), ids, role, revision(allowZero = true))
        }
        "delete_photo" -> {
            args.keys(mealFields + "photo_id", mealFields + "photo_id")
            CoachManualEdit.DeletePhoto(id("meal_id"), id("photo_id"), revision(allowZero = true))
        }
        "set_goals" -> {
            args.keys(setOf("effective_local_date", "expected_revision", "targets", "goal_weight_kg", "clear_goal_weight", "exercise_credit_enabled"), setOf("effective_local_date", "targets"))
            val targets = edits("targets")
            val clear = bool("clear_goal_weight") ?: false
            val weight = if (optional("goal_weight_kg")) {
                CoachTools.number(args["goal_weight_kg"])?.takeIf { it > 0 && it <= 10_000_000 && !clear } ?: invalid()
            } else null
            val credit = bool("exercise_credit_enabled")
            if (targets.isEmpty() && weight == null && !clear && credit == null) invalid()
            CoachManualEdit.Goals(date("effective_local_date"), targets, weight, clear, credit, if (optional("expected_revision")) revision() else null)
        }
        "update_preferences" -> {
            args.keys(setOf("expected_diary_revision", "timezone", "preferences"), setOf("expected_diary_revision"))
            val timezone = if (optional("timezone")) string("timezone").takeIf(::validZone) ?: invalid() else null
            val text = if (optional("preferences")) string("preferences", maximum = 10_000, allowEmpty = true) else null
            if (timezone == null && text == null) invalid()
            CoachManualEdit.Preferences(timezone, text, revision("expected_diary_revision", allowZero = true))
        }
        "start_day" -> {
            args.keys(setOf("expected_diary_revision"), setOf("expected_diary_revision"))
            CoachManualEdit.StartDay(revision("expected_diary_revision", allowZero = true))
        }
        "set_day_coverage" -> {
            args.keys(setOf("local_date", "skipped"), setOf("local_date", "skipped"))
            val skipped = bool("skipped") ?: invalid()
            CoachManualEdit.Coverage(date("local_date"), if (skipped) DayCompleteness.untracked else DayCompleteness.unknown)
        }
        "undo_change" -> {
            args.keys(setOf("operation_key"), setOf("operation_key"))
            val key = string("operation_key")
            // Swift's split drops empty pieces; a leading "/" fails the UUID check either way.
            val parts = key.split("/", limit = 2)
            val food = listOf("food/", "correct/", "edit_item/", "append_food/", "delete_item/", "scale_meal/")
            if (parts.size != 2 || swiftUUID(parts[0]) == null || food.none { parts[1].startsWith(it) }) invalid()
            CoachManualEdit.Undo(key)
        }
        "open_settings" -> {
            args.keys(setOf("destination"), setOf("destination"))
            CoachManualEdit.Open(CoachDestination.entries.firstOrNull { it.name == string("destination") } ?: invalid())
        }
        else -> throw CoachError.InvalidTool
    }
    val distinctPatches = setOf("edit_item", "set_goals", "update_preferences", "move_meal", "set_day_coverage", "attach_photos")
    val patchKey = if (call.name !in distinctPatches) null else {
        val patch = args.keys.filter { !it.startsWith("expected_") && args[it] !is JsonNull }.associateWith { args[it]!! }.toMutableMap<String, JsonElement>()
        for (key in listOf("nutrients", "targets")) {
            val rows = patch[key] as? JsonArray ?: continue
            if (rows.isEmpty()) patch.remove(key)
            else patch[key] = JsonArray(rows.sortedBy { ((it as JsonObject)["nutrient"] as? JsonPrimitive)?.content ?: "" })
        }
        (patch["photo_ids"] as? JsonArray)?.let { ids -> patch["photo_ids"] = JsonArray(ids.sortedBy { (it as JsonPrimitive).content }) }
        if ((patch["clear_goal_weight"] as? JsonPrimitive)?.let(CoachTools::bool) == false) patch.remove("clear_goal_weight")
        fingerprint(swiftJSONSerialization(JsonObject(patch)))
    }
    return CoachCommand.Write(CoachWrite.Manual(write, patchKey))
}
