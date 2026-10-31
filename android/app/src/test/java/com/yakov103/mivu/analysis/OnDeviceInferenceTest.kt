package com.yakov103.mivu.analysis

import com.yakov103.mivu.coach.CoachContext
import com.yakov103.mivu.coach.CoachInferenceInput
import com.yakov103.mivu.coach.CoachInferenceInput.Role
import com.yakov103.mivu.coach.CoachTools
import com.yakov103.mivu.coach.coachJSON
import com.yakov103.mivu.diary.DayCompleteness
import com.yakov103.mivu.diary.DiaryProfile
import com.yakov103.mivu.diary.FoodItem
import com.yakov103.mivu.diary.NutritionProvenance
import com.yakov103.mivu.diary.NutritionValues
import com.yakov103.mivu.diary.TrackingDay
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.double
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

// Ports ios/MivuTests/AppleInferenceTests.swift (local* cases) against a fake model and a fake table.
class OnDeviceInferenceTest {
    private val day = TrackingDay(UUID.randomUUID(), "2026-10-29", "UTC", Instant.parse("2026-10-29T00:00:00Z"), DayCompleteness.unknown)
    private val tools = Json.parseToJsonElement("""{"type":"namespace","name":"mivu"}""").jsonObject

    private fun item(name: String, quantity: Double = 1.0) = FoodItem(UUID.randomUUID(), name, quantity, "piece", NutritionValues(100.0, 10.0, 5.0, 2.0),
        NutritionProvenance.estimate, "", false, emptyMap())

    private fun meal(vararg items: FoodItem, eatenAt: String = "2026-10-29T12:00:00Z", omitted: Int = 0) =
        CoachContext.Meal(UUID.randomUUID(), day.id, 3, Instant.parse(eatenAt), items = items.toList(), omittedItemCount = omitted)

    private fun context(meals: List<CoachContext.Meal> = emptyList(), focus: CoachContext.Focus? = null) = CoachContext(
        DiaryProfile(UUID.randomUUID(), "Synthetic", "en", "UTC", ""), Instant.parse("2026-10-29T12:30:00Z"), "UTC", day.id, listOf(day), meals,
        emptyList(), emptyList(), focus = focus,
    )

    // Built the way CoachEngine builds it: rules, then the Context: message, then the captured text.
    private fun input(text: String, context: CoachContext = context(), images: List<ByteArray> = emptyList()) = listOf(
        CoachInferenceInput.Message(Role.developer, "rules. "),
        CoachInferenceInput.Message(Role.developer, "Context: " + coachJSON(CoachContext.serializer(), context)),
        CoachInferenceInput.Message(Role.user, text, images),
    )

    private class Model(val turn: LocalTurn, val choose: (String, List<NutritionTable.Food>) -> Int = { _, _ -> 0 }) : OnDeviceModel {
        val prompts = mutableListOf<String>()
        override suspend fun turn(text: String, images: List<ByteArray>): LocalTurn { prompts += text; return turn }
        override suspend fun pick(phrase: String, options: List<NutritionTable.Food>): Int = choose(phrase, options)
    }

    private class Table(val foods: List<NutritionTable.Food> = emptyList(), val portions: Map<String, Double> = emptyMap()) : FoodTable {
        override fun search(phrase: String) = foods.filter { f -> NutritionTable.words(phrase).any { it in NutritionTable.words(f.description) } }
        override fun portionGrams(code: Int, unit: String) = portions[unit]
    }

    private fun food(name: String, quantity: Double = 1.0, unit: String = "piece", search: String = name, kcal: Double = 0.0, carbs: Double = 0.0,
                     protein: Double = 0.0, fat: Double = 0.0, per100: List<Double> = listOf(0.0, 0.0, 0.0, 0.0)) =
        LocalTurn.Food(name, search, quantity, unit, kcal, carbs, protein, fat, per100[0], per100[1], per100[2], per100[3])

    private fun run(text: String, turn: LocalTurn, ctx: CoachContext = context(), table: FoodTable = Table(), images: List<ByteArray> = emptyList(),
                    pick: (String, List<NutritionTable.Food>) -> Int = { _, _ -> 0 }) =
        runBlocking { OnDeviceInference.respond(input(text, ctx, images), tools, Model(turn, pick), table) }

    private fun args(r: com.yakov103.mivu.coach.CoachInferenceResult) = Json.parseToJsonElement(r.calls.single().arguments).jsonObject
    private fun items(r: com.yakov103.mivu.coach.CoachInferenceResult) = args(r)["items"]!!.jsonArray.map { it.jsonObject }
    private fun JsonObject.num(key: String) = getValue(key).jsonPrimitive.double

    @Test fun resultsUseTheSharedReplayableItemShape() {
        val call = run("200g chicken", LocalTurn(LocalTurn.Intent.log, listOf(food("chicken", 200.0, "g", kcal = 1.0))))
        assertEquals("gemini-nano", call.model)
        val c = call.calls.single()
        assertEquals(CoachTools.NAMESPACE, c.namespace); assertEquals("log_food", c.name); assertEquals("fc_" + c.callID, c.id)
        val fn = Json.parseToJsonElement(call.outputItems.single()).jsonObject
        assertEquals("function_call", fn["type"]!!.jsonPrimitive.content); assertEquals("completed", fn["status"]!!.jsonPrimitive.content)
        assertEquals(CoachTools.NAMESPACE, fn["namespace"]!!.jsonPrimitive.content)
        val answer = run("thanks", LocalTurn(LocalTurn.Intent.other))
        val msg = Json.parseToJsonElement(answer.outputItems.single()).jsonObject
        assertEquals("message", msg["type"]!!.jsonPrimitive.content)
        assertEquals("output_text", msg["content"]!!.jsonArray.single().jsonObject["type"]!!.jsonPrimitive.content)
        assertTrue(answer.calls.isEmpty())
    }

    @Test fun logsANewMealThenCorrectsItsPortion() {
        val eggs = LocalTurn.Food("Boiled egg", "Boiled egg", 2.0, "egg", 155.0, 1.0, 13.0, 11.0, 155.0, 1.0, 13.0, 11.0)
        val toast = food("Toast", unit = "slice", kcal = 80.0, carbs = 14.0, protein = 3.0, fat = 1.0)
        val logged = run("Two boiled eggs", LocalTurn(LocalTurn.Intent.log, listOf(eggs, toast)))
        // Toast is not named in the message, so the grounding check keeps it out.
        assertEquals(listOf("Boiled egg"), items(logged).map { it["name"]!!.jsonPrimitive.content })
        assertEquals(155.0, items(logged).single().num("kcal"), 0.0)
        assertEquals("2026-10-29", args(logged)["target_local_date"]!!.jsonPrimitive.content)

        val egg = item("Boiled egg", 2.0)
        val saved = meal(egg)
        val prompts = Model(LocalTurn(LocalTurn.Intent.edit, editFood = "eggs", editQuantity = 3.0))
        val edited = runBlocking { OnDeviceInference.respond(input("Actually it was 3 eggs", context(listOf(saved))), tools, prompts, Table()) }
        val a = args(edited)
        assertEquals("correct_item", edited.calls.single().name)
        assertEquals(saved.id.toString(), a["meal_id"]!!.jsonPrimitive.content); assertEquals(egg.id.toString(), a["item_id"]!!.jsonPrimitive.content)
        assertEquals(3.0, a.num("expected_revision"), 0.0); assertEquals(3.0, a.num("quantity"), 0.0)
        assertEquals(listOf("Actually it was 3 eggs"), prompts.prompts) // only the message, so saved foods cannot be copied
    }

    @Test fun weighedAmountsUsePerHundredGramValues() {
        // The serving total repeats the per-100 g figure, the mistake measured on-device.
        val chicken = food("Grilled chicken breast", 200.0, "g", kcal = 165.0, protein = 31.0, fat = 3.6, per100 = listOf(165.0, 0.0, 31.0, 3.6))
        val item = items(run("200g grilled chicken breast", LocalTurn(LocalTurn.Intent.edit, listOf(chicken)))).single()
        assertEquals(330.0, item.num("kcal"), 0.0); assertEquals(62.0, item.num("protein"), 0.0)
    }

    @Test fun nutritionComesFromTheTableForSlicesAndWeighedAmounts() {
        val pizza = NutritionTable.Food(1, "Pizza with pepperoni, stuffed crust", 296.0, 0.0, 0.0, 0.0)
        val chicken = NutritionTable.Food(2, "Chicken breast, grilled without sauce, skin eaten", 206.0, 0.0, 0.0, 0.0)
        val picks = mutableListOf<String>()
        val r = run("2 slices of pepperoni pizza and 200g grilled chicken breast",
            LocalTurn(LocalTurn.Intent.log, listOf(food("pepperoni pizza", 2.0, "slice"), food("grilled chicken breast", 200.0, "g"))),
            table = Table(listOf(pizza, chicken), mapOf("slice" to 164.0)),
            pick = { phrase, options -> picks += phrase; options.indexOfFirst { it.description.startsWith(if ("pizza" in phrase) "Pizza" else "Chicken") } + 1 })
        assertEquals(listOf(970.9, 412.0), items(r).map { it.num("kcal") })
        assertEquals("2 slice pepperoni pizza", picks.first())
    }

    @Test fun logsNamedFoodWithTableNumbers() {
        val chicken = NutritionTable.Food(2, "Chicken breast, grilled", 165.0, 0.0, 31.0, 3.6)
        val r = run("200g chicken breast", LocalTurn(LocalTurn.Intent.log, listOf(food("chicken breast", 200.0, "g"))),
            table = Table(listOf(chicken)), pick = { _, _ -> 1 })
        assertEquals("gemini-nano", r.model)
        assertEquals(330.0, items(r).single().num("kcal"), 0.0); assertEquals(200.0, items(r).single().num("quantity"), 0.0)
    }

    @Test fun unitWithoutAMatchingPortionKeepsTheModelEstimate() {
        val cookie = NutritionTable.Food(3, "Cookie, chocolate chip", 480.0, 0.0, 0.0, 0.0)
        val r = run("a chocolate chip cookie", LocalTurn(LocalTurn.Intent.log, listOf(food("chocolate chip cookie", unit = "piece", kcal = 80.0, carbs = 10.0, protein = 1.0, fat = 4.0))),
            table = Table(listOf(cookie)), pick = { _, _ -> 1 })
        assertEquals(80.0, items(r).single().num("kcal"), 0.0)
    }

    @Test fun aFailedPickKeepsTheEstimate() {
        val cookie = NutritionTable.Food(3, "Cookie, chocolate chip", 480.0, 0.0, 0.0, 0.0)
        val r = run("a cookie", LocalTurn(LocalTurn.Intent.log, listOf(food("cookie", kcal = 80.0, carbs = 10.0))),
            table = Table(listOf(cookie)), pick = { _, _ -> error("model gone") })
        assertEquals(80.0, items(r).single().num("kcal"), 0.0)
    }

    @Test fun aPausedOrBusyPickFailsTheTurnSoItWaits() {
        val cookie = NutritionTable.Food(3, "Cookie, chocolate chip", 480.0, 0.0, 0.0, 0.0)
        for (failure in listOf(OnDeviceFailure.Paused, OnDeviceFailure.Busy)) {
            val error = runCatching { run("a cookie", LocalTurn(LocalTurn.Intent.log, listOf(food("cookie", kcal = 80.0))),
                table = Table(listOf(cookie)), pick = { _, _ -> throw failure }) }.exceptionOrNull()
            assertEquals(failure, error)
        }
    }

    @Test fun caloriesNeverFallBelowWhatTheMacrosImply() {
        val coke = food("Coca cola", unit = "can", kcal = 3.0, carbs = 35.0, per100 = listOf(1.0, 10.6, 0.0, 0.0))
        assertEquals(140.0, items(run("a can of coca cola", LocalTurn(LocalTurn.Intent.log, listOf(coke)))).single().num("kcal"), 0.0)
    }

    @Test fun calorieFloor() {
        val r = run("a snack", LocalTurn(LocalTurn.Intent.log, listOf(food("snack", kcal = 10.0, carbs = 20.0))))
        assertEquals(80.0, items(r).single().num("kcal"), 0.0)
    }

    @Test fun unnamedEditChangesTheOnlyFoodInTheLatestMeal() {
        val coke = item("coke zero"); val only = meal(coke)
        // Measured on the owner's iPhone: "make it three" names no food and the model invents one.
        val r = run("make it three", LocalTurn(LocalTurn.Intent.edit, editFood = "chocolate", editQuantity = 3.0), context(listOf(only)))
        assertEquals(coke.id.toString(), args(r)["item_id"]!!.jsonPrimitive.content); assertEquals(3.0, args(r).num("quantity"), 0.0)

        // After a second same-day meal, "it" is the meal the conversation last changed (date-only times tie).
        val pizza = item("pepperoni pizza"); val second = meal(pizza)
        val focus = CoachContext.Focus(CoachContext.Focus.LastChanged(second.id, listOf("pepperoni pizza"), "2026-10-29", 3))
        val again = run("make it 4", LocalTurn(LocalTurn.Intent.edit, editFood = "ice cream", editQuantity = 4.0), context(listOf(only, second), focus))
        assertEquals(second.id.toString(), args(again)["meal_id"]!!.jsonPrimitive.content)
        // Without a focus the newest eatenAt wins.
        val older = meal(coke, eatenAt = "2026-10-29T08:00:00Z"); val newer = meal(pizza, eatenAt = "2026-10-29T13:00:00Z")
        assertEquals(newer.id.toString(), args(run("make it 4", LocalTurn(LocalTurn.Intent.edit, editQuantity = 4.0), context(listOf(older, newer))))["meal_id"]!!.jsonPrimitive.content)
    }

    @Test fun editNeedsNamedOrSingleItem() {
        val two = meal(item("coke zero"), item("pizza"))
        val none = run("make it 3", LocalTurn(LocalTurn.Intent.edit, editQuantity = 3.0), context(listOf(two)))
        assertEquals("Nothing to change.", none.text); assertTrue(none.calls.isEmpty())
        val one = run("make it 3", LocalTurn(LocalTurn.Intent.edit, editQuantity = 3.0), context(listOf(meal(item("coke zero")))))
        assertEquals(3.0, args(one).num("quantity"), 0.0); assertEquals("correct_item", one.calls.single().name)
    }

    @Test fun turnsStillWorkWhenAFoodNameContainsTheContextMarker() {
        val bar = meal(item("Context: protein bar"))
        val r = run("make it 2", LocalTurn(LocalTurn.Intent.edit, editQuantity = 2.0), context(listOf(bar)))
        assertEquals(2.0, args(r).num("quantity"), 0.0)
        val logged = run("Context: protein bar", LocalTurn(LocalTurn.Intent.log, listOf(food("Context: protein bar", unit = "bar", kcal = 200.0, carbs = 20.0, protein = 10.0, fat = 8.0))))
        assertEquals(200.0, items(logged).single().num("kcal"), 0.0)
    }

    @Test fun editOfAFoodNotInTheLatestMealChangesNothing() {
        val r = run("make the latte 2", LocalTurn(LocalTurn.Intent.edit, editFood = "latte", editQuantity = 2.0), context(listOf(meal(item("Boiled egg")))))
        assertTrue(r.calls.isEmpty()); assertEquals("Nothing to change.", r.text)
    }

    @Test fun dropsUngroundedFoodsWithoutPhotos() {
        val r = run("thanks", LocalTurn(LocalTurn.Intent.log, listOf(food("banana", kcal = 100.0))))
        assertEquals("Nothing to change.", r.text); assertTrue(r.calls.isEmpty())
        // A photo grounds the food even when the message does not name it.
        assertEquals(1, items(run("this", LocalTurn(LocalTurn.Intent.log, listOf(food("banana", kcal = 100.0))), images = listOf(byteArrayOf(1)))).size)
    }

    @Test fun functionOutputRepliesDone() {
        val r = runBlocking {
            OnDeviceInference.respond(input("x") + CoachInferenceInput.FunctionOutput("a", "{}"), tools, Model(LocalTurn(LocalTurn.Intent.other)), Table())
        }
        assertEquals("Done.", r.text); assertTrue(r.calls.isEmpty())
    }

    @Test fun onboardingWithoutToolsIsRejected() {
        try { runBlocking { OnDeviceInference.respond(input("x"), null, Model(LocalTurn(LocalTurn.Intent.other)), Table()) }; fail() }
        catch (_: ResponsesClient.Failure.InvalidInput) {}
    }

    @Test fun parseTurnFencedAndMalformed() {
        val turn = OnDeviceInference.parseTurn("```json\n{\"intent\":\"log\",\"extra\":1,\"foods\":[{\"name\":\"egg\",\"kcal\":-5}]}\n```")
        assertEquals(LocalTurn.Intent.log, turn.intent)
        val r = run("egg", turn)
        assertEquals(0.0, items(r).single().num("kcal"), 0.0)
        for (bad in listOf("{\"foods\":[]}", "{\"intent\":\"cook\"}", "not json", "", "[]", "{\"intent\":\"log\",\"foods\":[{\"name\":\"a\",\"kcal\":1e999}]}",
            "{\"intent\":\"log\",\"foods\":[{\"kcal\":1}]}")) {
            try { OnDeviceInference.parseTurn(bad); fail(bad) } catch (_: ResponsesClient.Failure.Malformed) {}
        }
    }

    @Test fun parsePickAcceptsZeroToFiveOnly() {
        assertEquals(3, OnDeviceInference.parsePick("{\"option\": 3}"))
        assertEquals(0, OnDeviceInference.parsePick("```json\n{\"option\":0}\n```"))
        for (bad in listOf("{\"option\":6}", "{\"option\":-1}", "{\"option\":1.5}", "{}", "3")) {
            try { OnDeviceInference.parsePick(bad); fail(bad) } catch (_: ResponsesClient.Failure.Malformed) {}
        }
    }
}
