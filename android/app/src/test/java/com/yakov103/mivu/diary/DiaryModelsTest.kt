package com.yakov103.mivu.diary

import java.util.UUID
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class DiaryModelsTest {
    private fun snapshotJson(name: String): JsonObject = SwiftJson.parseToJsonElement(
        javaClass.classLoader!!.getResource("archive/$name.json")!!.readText(),
    ).jsonObject["snapshot"]!!.jsonObject

    private fun decode(json: JsonElement) = SwiftJson.decodeFromJsonElement(DiarySnapshot.serializer(), json)
    private fun id(n: Int) = UUID.fromString("00000000-0000-0000-0000-%012d".format(n))
    private fun date(seconds: Double) = SwiftJson.decodeFromString(SwiftDate, seconds.toString())

    @Test fun decodesIosFullFixture() {
        val s = decode(snapshotJson("ios-v4-full"))
        assertEquals(12, s.revision)
        assertEquals(id(951), s.lineage!!.last())
        assertEquals("Synthetic Profile", s.profile.name)
        assertEquals(ProfileAbout.Pace.gentle, s.profile.about!!.pace)
        assertEquals(ProfileAbout.Sex.female, s.profile.about.sex)
        assertEquals(date(800090000.5), s.days[1].closedAt)
        assertEquals(DayCompleteness.untracked, s.days[3].completeness)

        val meal = s.meals[0]
        assertEquals(5, meal.changedRevision)
        assertEquals(MealTimePrecision.exact, meal.timePrecision)
        assertEquals("apple-intelligence", meal.items[2].estimatedBy)
        assertNull(meal.items[0].estimatedBy)
        assertEquals(mapOf("kcal" to NutritionProvenance.identifiedSource), meal.items[3].nutrientSources)
        assertEquals(2.5, meal.items[1].nutritionBasis!!.protein!!, 0.0)
        assertNull(meal.items[0].nutrition.carbs)
        assertArrayEquals(byteArrayOf(1, 2, 3), meal.photos[0].data)
        assertEquals(PhotoRole.after, meal.photos[2].role)
        assertEquals(SubmissionState.cancelled, meal.submissions[6].state)
        assertEquals(id(1), meal.submissions[3].proposal!!.profileID)

        val acceptances = s.meals.drop(1).map { it.submissions[0].manualAcceptance!! }
        assertEquals(ManualNutritionOperation.append, acceptances[1].operation)
        assertEquals(1, acceptances[1].expectedMealRevision)
        assertEquals(
            listOf(
                ManualNutritionTarget.Recorded(id(10), "2026-10-11", "UTC"),
                ManualNutritionTarget.Active(id(11), "2026-10-12", "Asia/Jerusalem", confirmPrevious = true),
                ManualNutritionTarget.NewCurrent(id(12), "2026-10-13", "Asia/Jerusalem", previousActiveDayID = id(11)),
            ),
            acceptances.map { it.target },
        )

        assertEquals(1, s.weights[0].revision)
        assertEquals("lb", s.weights[1].unit)
        assertEquals(2000.0, s.goals[0].targets.kcal!!, 0.0)
        assertEquals(68.0, s.goals[0].goalWeightKg!!, 0.0)
        assertEquals(60.5, s.workouts[0].exercises[0].sets[0].loadKg!!, 0.0)
        assertNull(s.workouts[0].exercises[0].sets[1].loadKg)
        assertEquals(WorkoutBurnSource.modelEstimate, s.workouts[1].burnSource)
        assertEquals(WorkoutKind.other, s.workouts[2].kind)

        val turn = s.coachTurns[0]
        assertEquals(true, turn.incomplete)
        assertArrayEquals(byteArrayOf(4, 5, 6), turn.photos[0].data)
        assertEquals("abababababababababababababababababababababababababababababababab", turn.receipts[0].commandFingerprint)
        assertEquals(CoachDestination.values().toList(), turn.receipts.mapNotNull { it.destination })
        assertEquals(id(85), turn.receipts[4].goalID)
        assertEquals(CoachClarification.portion, turn.question!!.kind)
        assertEquals(
            listOf(
                CoachReply.Target.Message(id(111), fromPip = true),
                CoachReply.Target.Meal(id(20)),
                CoachReply.Target.Item(mealID = id(20), itemID = id(40)),
                CoachReply.Target.Day(id(10)),
                CoachReply.Target.Weight(id(81)),
                CoachReply.Target.Workout(id(90)),
            ),
            turn.question.candidates,
        )
        val manifest = turn.submissionManifest!!
        assertEquals("787c798e39a5bc1910355bae6d0cd87a36b2e10fd0202a83e3bb6b005da83472", manifest.attachments[0].contentFingerprint)
        assertEquals(date(800000305.0), manifest.context.previousDayConfirmedAt)
        assertEquals(CoachReply(CoachReply.Target.Message(id(111), fromPip = true), "Synthetic excerpt"), manifest.reply)
        assertEquals(2, s.coachTurns[2].pendingMealRevision)
        assertEquals(CoachTurnState.values().toSet(), s.coachTurns.map { it.state }.toSet())
        assertEquals(CoachClarification.values().toList(), s.coachTurns.mapNotNull { it.question?.kind })
    }

    @Test fun reEncodeIsSemanticallyEqual() {
        val original = snapshotJson("ios-v4-full")
        val decoded = decode(original)
        val encoded = SwiftJson.encodeToJsonElement(DiarySnapshot.serializer(), decoded)
        assertEquals(normalized(original), normalized(encoded))
        assertEquals(decoded, decode(encoded)) // MealPhoto compares bytes by content
    }

    @Test fun profileWithoutAboutDecodes() {
        val json = snapshotJson("ios-v4-full")
        val profile = JsonObject(json["profile"]!!.jsonObject - "about")
        assertNull(decode(JsonObject(json + ("profile" to profile))).profile.about)
    }

    @Test fun olderFixturesDefaultMissingProgressKeys() {
        for (name in listOf("ios-v1", "ios-v2")) {
            val s = decode(snapshotJson(name))
            assertEquals(emptyList<GoalRecord>(), s.goals)
            assertEquals(emptyList<WorkoutSession>(), s.workouts)
            assertEquals(emptyList<CoachTurn>(), s.coachTurns)
            assertEquals(emptyList<UUID>(), s.deletedWeightIDs)
            assertEquals(emptyList<UUID>(), s.deletedWorkoutIDs)
            assertEquals(listOf(1, 1), s.weights.map { it.revision })
            assertEquals(listOf(MealTimePrecision.exact, MealTimePrecision.exact), s.weights.map { it.timePrecision })
        }
        val v3 = decode(snapshotJson("ios-v3"))
        assertEquals(11, v3.coachTurns.size)
        assertEquals(listOf(id(901)), v3.deletedWeightIDs)
    }

    private fun normalized(e: JsonElement): JsonElement = when (e) {
        is JsonObject -> JsonObject(e.mapValues { normalized(it.value) })
        is JsonArray -> JsonArray(e.map(::normalized))
        is JsonPrimitive -> when {
            e.isString -> JsonPrimitive(e.content.uppercase().takeIf { runCatching { UUID.fromString(e.content) }.isSuccess && e.content.length == 36 } ?: e.content)
            else -> e.content.toDoubleOrNull()?.let(::JsonPrimitive) ?: e
        }
    }
}
