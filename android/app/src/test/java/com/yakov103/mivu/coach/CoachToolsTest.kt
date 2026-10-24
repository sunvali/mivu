package com.yakov103.mivu.coach

import com.yakov103.mivu.diary.CoachClarification
import com.yakov103.mivu.diary.CoachMealCandidate
import com.yakov103.mivu.diary.CoachReceipt
import com.yakov103.mivu.diary.CoachReply
import com.yakov103.mivu.diary.DayCompleteness
import com.yakov103.mivu.diary.FoodItem
import com.yakov103.mivu.diary.MealTimePrecision
import com.yakov103.mivu.diary.NutritionProvenance
import com.yakov103.mivu.diary.NutritionValues
import com.yakov103.mivu.diary.SwiftJson
import com.yakov103.mivu.diary.WorkoutKind
import com.yakov103.mivu.diary.WorkoutSession
import java.time.Instant
import java.util.UUID
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class CoachToolsTest {
    private fun id(n: Int) = UUID.fromString("00000000-0000-0000-0000-%012d".format(n))
    private fun s(n: Int) = id(n).toString().uppercase()
    private fun food(n: Int, name: String) = FoodItem(id(n), name, 40.0, "g", NutritionValues(kcal = 150.0), NutritionProvenance.estimate,
        "Synthetic reference", true, emptyMap())

    private val meal = CoachContext.Meal(id(20), id(10), 3, Instant.EPOCH, MealTimePrecision.dateOnly,
        listOf(food(41, "Synthetic oats"), food(42, "Synthetic milk")),
        review = CoachContext.Meal.Review(id(50), 3, listOf(food(43, "Synthetic banana"))))
    private val workout = WorkoutSession(id(90), id(10), Instant.EPOCH, MealTimePrecision.dateOnly, 2, WorkoutKind.strength, 45, emptyList())

    private fun parse(name: String, arguments: String, meals: List<CoachContext.Meal> = listOf(meal),
                      receipts: List<CoachReceipt> = emptyList(), found: List<CoachMealCandidate> = emptyList(), namespace: String? = "mivu") =
        CoachTools.parse(CoachToolCall(name, name, name, namespace, arguments), meals, receipts, listOf(workout), found)

    private fun write(name: String, arguments: String) = (parse(name, arguments) as CoachCommand.Write).write
    private fun rejects(name: String, arguments: String, meals: List<CoachContext.Meal> = listOf(meal)) {
        assertThrows(name + arguments, CoachError.InvalidArguments::class.java) { parse(name, arguments, meals) }
    }

    private fun resource(name: String) = javaClass.classLoader!!.getResource("coach/$name")!!.readText()
    private fun canonical(e: JsonElement): JsonElement = when (e) {
        is JsonObject -> JsonObject(e.mapValues { canonical(it.value) }.toSortedMap())
        is JsonArray -> JsonArray(e.map(::canonical))
        else -> e
    }

    @Test fun declarationsMatchIosGolden() {
        val golden = SwiftJson.parseToJsonElement(resource("tools.json"))
        val ours = CoachTools.declarations()
        assertEquals(33, ours["tools"]!!.jsonArray.size) // 15 core + 18 manual, as iOS declares
        // Per tool first, so a mismatch names the tool.
        golden.jsonObject["tools"]!!.jsonArray.zip(ours["tools"]!!.jsonArray).forEach { (ios, android) ->
            assertEquals(ios.jsonObject["name"].toString(), canonical(ios).toString(), canonical(android).toString())
        }
        assertEquals(canonical(golden).toString(), canonical(ours).toString())
    }

    @Serializable private data class Case(val tool: String, val arguments: String, val target: String, val fingerprint: String)
    @Serializable private data class Fingerprints(val meals: List<CoachContext.Meal>, val workouts: List<WorkoutSession>, val cases: List<Case>)

    @Test fun fingerprintsMatchIosGolden() {
        val golden = SwiftJson.decodeFromString(Fingerprints.serializer(), resource("fingerprints.json"))
        assertEquals(26, golden.cases.size)
        for (case in golden.cases) {
            val command = CoachTools.parse(CoachToolCall(case.tool, case.tool, case.tool, "mivu", case.arguments),
                golden.meals, emptyList(), golden.workouts)
            val write = (command as CoachCommand.Write).write
            assertEquals(case.arguments, case.target, write.target)
            assertEquals(case.arguments, case.fingerprint, write.commandFingerprint())
        }
    }

    @Test fun unknownKeyRejected() {
        rejects("get_meal", """{"meal_id":"${s(20)}","extra":1}""")
        rejects("log_weight", """{"local_date":"2026-10-24","value":70,"unit":"kg","note":"x"}""")
        rejects("get_meal", "{}") // required key missing
        assertThrows(CoachError.InvalidTool::class.java) { parse("get_context", "{}", namespace = "other") }
        assertThrows(CoachError.InvalidTool::class.java) { parse("drop_tables", "{}") }
        assertThrows(CoachError.InvalidTool::class.java) { parse("get_context", "[]") }
    }

    @Test fun nonJsonArgumentsRejected() {
        val m = s(20)
        val calls = listOf(
            "set_day_coverage" to """{"local_date":"2026-10-22","skipped":True}""",
            "get_progress" to """{"ending_on":"2026-10-24","days":7d}""",
            "get_progress" to """{"ending_on":"2026-10-24","days":0x1p3}""",
            "get_progress" to """{"ending_on":"2026-10-24","days":+7}""",
            "move_meal" to """{"meal_id":"$m","expected_revision":3,"target_local_date":"\ud800"}""",
            "set_goals" to """{"effective_local_date":"2026-10-24","targets":[],"exercise_credit_enabled":TRUE}""",
        )
        for ((name, arguments) in calls) {
            val error = runCatching { parse(name, arguments) }.exceptionOrNull()
            assertEquals(arguments, CoachError.InvalidTool, error)
        }
    }

    @Test fun oversizedStringRejected() {
        rejects("lookup_nutrition", """{"query":"${"a".repeat(201)}"}""")
        assertEquals(CoachCommand.Lookup("a".repeat(200)), parse("lookup_nutrition", """{"query":"${"a".repeat(200)}"}"""))
        rejects("find_meals", """{"query":"${"é".repeat(251)}"}""") // 502 UTF-8 bytes
        rejects("log_food", """{"target_local_date":"${"2".repeat(501)}","items":[{"name":"x","quantity":1,"unit":"g","kcal":null,"carbs":null,"protein":null,"fat":null}]}""")
        val big = """{"query":"x","pad":"${"a".repeat(65_536)}"}"""
        assertThrows(CoachError.InvalidTool::class.java) { parse("lookup_nutrition", big) }
    }

    @Test fun progressDaysMustBe1_7_30() {
        for (days in listOf(1, 7, 30)) {
            assertEquals(CoachCommand.Progress("2026-10-24", days), parse("get_progress", """{"ending_on":"2026-10-24","days":$days}"""))
        }
        for (days in listOf("2", "31", "0", "7.5", "\"7\"", "true")) rejects("get_progress", """{"ending_on":"2026-10-24","days":$days}""")
        rejects("get_progress", """{"ending_on":"2026-02-30","days":7}""")
    }

    @Test fun clarificationAtMost4Candidates() {
        val one = """{"meal_id":"${s(20)}"}"""
        val four = parse("ask_clarification", """{"kind":"meal","candidates":[$one,$one,$one,$one]}""") as CoachCommand.Clarification
        assertEquals(4, four.candidates.size)
        rejects("ask_clarification", """{"kind":"meal","candidates":[$one,$one,$one,$one,$one]}""")
        assertEquals(CoachCommand.Clarification(CoachClarification.portion, emptyList()), parse("ask_clarification", """{"kind":"portion","candidates":null}"""))
        // confirm names exactly one meal; a named food stands for its meal.
        assertEquals(CoachCommand.Clarification(CoachClarification.confirm, listOf(CoachReply.Target.Meal(id(20)))),
            parse("ask_clarification", """{"kind":"confirm","candidates":[{"meal_id":"${s(20)}","item_id":"${s(41)}"}]}"""))
        rejects("ask_clarification", """{"kind":"confirm"}""")
        rejects("ask_clarification", """{"kind":"maybe"}""")
    }

    @Test fun candidateMustBeSeenThisTurn() {
        rejects("ask_clarification", """{"kind":"meal","candidates":[{"meal_id":"${s(99)}"}]}""")
        rejects("ask_clarification", """{"kind":"food","candidates":[{"meal_id":"${s(20)}","item_id":"${s(43)}"}]}""") // review item
        assertEquals(CoachCommand.Clarification(CoachClarification.food, listOf(CoachReply.Target.Item(id(20), id(41)))),
            parse("ask_clarification", """{"kind":"food","candidates":[{"meal_id":"${s(20)}","item_id":"${s(41).lowercase()}"}]}"""))
        val found = CoachMealCandidate(id(99), id(10), "2026-10-01", "UTC", 1, Instant.EPOCH, null,
            listOf(CoachMealCandidate.Item(id(98), "Synthetic soup", 1.0, "bowl")), 0, "Synthetic", false)
        assertEquals(CoachCommand.Clarification(CoachClarification.meal, listOf(CoachReply.Target.Item(id(99), id(98)))),
            parse("ask_clarification", """{"kind":"meal","candidates":[{"meal_id":"${s(99)}","item_id":"${s(98)}"}]}""", found = listOf(found)))
    }

    @Test fun readToolsParse() {
        assertEquals(CoachCommand.Context, parse("get_context", "{}"))
        assertEquals(CoachCommand.Preferences, parse("get_preferences", "{}"))
        assertEquals(CoachCommand.Goals("2026-10-24"), parse("get_goals", """{"local_date":"2026-10-24"}"""))
        assertEquals(CoachCommand.Meal(id(20)), parse("get_meal", """{"meal_id":"${s(20).lowercase()}"}"""))
        assertEquals(CoachCommand.Workout(id(90)), parse("get_workout", """{"workout_id":"${s(90)}"}"""))
        assertEquals(CoachCommand.Meals("2026-10-24", null), parse("get_meals_for_date", """{"target_local_date":"2026-10-24","after_meal_id":null}"""))
        assertEquals(CoachCommand.Meals("2026-10-24", id(20)), parse("get_meals_for_date", """{"target_local_date":"2026-10-24","after_meal_id":"${s(20)}"}"""))
        assertEquals(CoachCommand.FindMeals("soup", "2026-10-01", null), parse("find_meals", """{"query":"soup","from_date":"2026-10-01","to_date":null}"""))
        rejects("find_meals", """{"query":"soup","from_date":"10/01/2026"}""")
        rejects("get_meal", """{"meal_id":"not-a-uuid"}""")
    }

    @Test fun foodToolsParse() {
        val logged = write("log_food", """{"target_local_date":"2026-10-24","items":[{"name":"Synthetic rice","quantity":150,"unit":"g","kcal":210.5,"carbs":null,"protein":4,"fat":0.1}],"eaten_at":"2026-10-24T08:30:00+02:00","review_first":true}""")
            as CoachWrite.Food
        assertEquals(true, logged.reviewFirst)
        assertEquals(null, logged.eatenAt) // model time is never confirmed
        val item = logged.items.single()
        assertEquals(NutritionValues(kcal = 210.5, protein = 4.0, fat = 0.1), item.nutrition)
        assertEquals(NutritionProvenance.estimate, item.provenance)
        assertEquals("Unverified portion estimate", item.reference)
        val tagged = CoachCommand.Write(logged).estimatedBy("gpt-synthetic") as CoachCommand.Write
        assertEquals("gpt-synthetic", (tagged.write as CoachWrite.Food).items.single().estimatedBy)
        val row = """{"name":"x","quantity":1,"unit":"g","kcal":null,"carbs":null,"protein":null,"fat":null"""
        rejects("log_food", """{"target_local_date":"2026-10-24","items":[$row}],"review_first":"yes"}""")
        rejects("log_food", """{"target_local_date":"2026-10-24","items":[$row,"evidence_id":7}]}""") // no evidence on Android yet
        rejects("log_food", """{"target_local_date":"2026-10-24","items":[]}""")
        rejects("log_food", """{"target_local_date":"2026-10-24","items":[$row,"brand":"x"}]}""")
        rejects("log_food", """{"target_local_date":"2026-10-24","items":[$row}],"eaten_at":"tomorrow"}""")
        val correction = write("correct_item", """{"meal_id":"${s(20)}","item_id":"${s(41)}","expected_revision":3,"quantity":80}""") as CoachWrite.Correction
        assertEquals(80.0, correction.item.quantity, 0.0)
        assertEquals(NutritionValues(kcal = 150.0), correction.item.nutrition) // nutrition basis is preserved
        rejects("correct_item", """{"meal_id":"${s(20)}","item_id":"${s(41)}","expected_revision":2,"quantity":80}""")
    }

    @Test fun weightAndWorkoutToolsParse() {
        assertEquals(CoachWrite.Weight("2026-10-24", 70.3, "kg", null),
            write("log_weight", """{"local_date":"2026-10-24","value":70.3,"unit":"kg","weight_id":null,"expected_revision":null,"measured_at":null}"""))
        assertEquals(CoachWrite.CorrectWeight(id(80), 155.5, "lb", 2),
            write("log_weight", """{"local_date":"2026-10-24","value":155.5,"unit":"lb","weight_id":"${s(80)}","expected_revision":2}"""))
        rejects("log_weight", """{"local_date":"2026-10-24","value":1501,"unit":"kg"}""")
        rejects("log_weight", """{"local_date":"2026-10-24","value":70,"unit":"stone"}""")
        val logged = write("log_workout", """{"local_date":"2026-10-24","kind":"strength","duration_minutes":45,"exercises":[{"name":"Synthetic squat","sets":[{"repetitions":8,"load_kg":60.5}]}],"estimated_burn_kcal":250,"burn_source":"userEstimate"}""")
            as CoachWrite.Workout
        assertEquals(60.5, logged.draft.exercises.single().sets.single().loadKg!!, 0.0)
        rejects("log_workout", """{"local_date":"2026-10-24","kind":"strength","duration_minutes":45,"exercises":[],"burn_source":"userEstimate"}""")
        rejects("log_workout", """{"local_date":"2026-10-24","kind":"strength","duration_minutes":0,"exercises":[]}""")
        rejects("edit_workout", """{"workout_id":"${s(90)}","expected_revision":1,"kind":"cardio","duration_minutes":30,"exercises":[]}""") // unseen revision
        assertEquals(CoachWrite.DeleteWorkout(id(90), 2), write("delete_workout", """{"workout_id":"${s(90)}","expected_revision":2}"""))
        assertEquals(CoachWrite.DeleteWeight(id(80), 2), write("delete_weight", """{"weight_id":"${s(80)}","expected_revision":2}"""))
    }

    @Test fun manualEditToolsParse() {
        val edit = write("edit_item", """{"meal_id":"${s(20)}","expected_revision":3,"item_id":"${s(41)}","nutrients":[{"nutrient":"kcal","value":null}]}""") as CoachWrite.Manual
        val item = edit.edit as CoachManualEdit.Item
        assertEquals(null, item.item.nutrition.kcal)
        assertEquals(setOf("kcal"), item.explicitNutrients)
        assertTrue(edit.target.startsWith("edit_item/${s(20)}/saved/${s(41)}/"))
        rejects("edit_item", """{"meal_id":"${s(20)}","expected_revision":3,"item_id":"${s(41)}"}""") // nothing to change
        rejects("edit_item", """{"meal_id":"${s(20)}","expected_revision":3,"item_id":"${s(41)}","nutrients":[{"nutrient":"kcal","value":1},{"nutrient":"kcal","value":2}]}""")
        rejects("delete_item", """{"meal_id":"${s(20)}","expected_revision":3,"item_id":"${s(41)}"}""", listOf(meal.copy(items = meal.items.take(1))))
        rejects("attach_photos", """{"meal_id":"${s(20)}","expected_revision":3,"photo_ids":["${s(31)}","${s(31)}"],"role":"after"}""")
        rejects("set_goals", """{"effective_local_date":"2026-10-24","targets":[],"goal_weight_kg":68,"clear_goal_weight":true}""")
        rejects("set_goals", """{"effective_local_date":"2026-10-24","targets":[]}""")
        rejects("update_preferences", """{"expected_diary_revision":1,"timezone":"Mars/Base"}""")
        assertEquals(CoachManualEdit.Coverage("2026-10-22", DayCompleteness.untracked),
            (write("set_day_coverage", """{"local_date":"2026-10-22","skipped":true}""") as CoachWrite.Manual).edit)
        rejects("undo_change", """{"operation_key":"${s(110)}/weight/2026-10-24"}""")
        assertEquals("undo/${s(110)}/food/2026-10-24", write("undo_change", """{"operation_key":"${s(110)}/food/2026-10-24"}""").target)
        rejects("open_settings", """{"destination":"billing"}""")
        // Patch keys ignore expected_* guards and null fields, so a retry with the same intent matches.
        assertEquals(write("move_meal", """{"meal_id":"${s(20)}","expected_revision":3,"target_local_date":"2026-10-23"}""").target,
            write("move_meal", """{"target_local_date":"2026-10-23","expected_revision":4,"meal_id":"${s(20)}"}""").target)
    }
}
