package com.yakov103.mivu.coach

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.yakov103.mivu.diary.CoachCaptureContext
import com.yakov103.mivu.diary.CoachSubmissionPayload
import com.yakov103.mivu.diary.CoachTurn
import com.yakov103.mivu.diary.DiaryDatabase
import com.yakov103.mivu.diary.DiaryProfile
import com.yakov103.mivu.diary.FoodItem
import com.yakov103.mivu.diary.NutritionProvenance
import com.yakov103.mivu.diary.NutritionValues
import com.yakov103.mivu.diary.WorkoutDraft
import com.yakov103.mivu.diary.WorkoutKind
import com.yakov103.mivu.diary.applyCoachWrites
import com.yakov103.mivu.diary.captureCoachSubmission
import com.yakov103.mivu.diary.startDay
import java.io.File
import java.time.Instant
import java.util.UUID
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test

/** Synthetic diaries only: each Coach read tool's output, shaped like iOS. */
class CoachReadsTest {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val profile = DiaryProfile(UUID.randomUUID(), "Synthetic", "en", "UTC", "Synthetic preference")
    private lateinit var db: DiaryDatabase
    private val at = Instant.parse("2026-10-24T12:00:00Z")
    private val today = "2026-10-24"

    @Before fun open() {
        File(context.filesDir, "profiles").deleteRecursively()
        db = DiaryDatabase.create(context, profile)
        db.startDay(at, db.head().revision)
    }

    @After fun close() {
        db.close()
        File(context.filesDir, "profiles").deleteRecursively()
    }

    private fun turn(): CoachTurn {
        val h = db.head()
        return db.captureCoachSubmission(CoachSubmissionPayload(UUID.randomUUID(), "Synthetic read", emptyList(),
            CoachCaptureContext(at, "UTC", h.activeDayID, h.previousDayConfirmedAt, h.activeConversationSegmentID)), h.revision)
    }

    private fun food(name: String) = FoodItem(UUID.randomUUID(), name, 1.0, "piece", NutritionValues(95.0, 25.0, 0.5, 0.3),
        NutritionProvenance.estimate, "Synthetic", true, emptyMap())
    private fun write(vararg writes: CoachWrite) = db.applyCoachWrites(turn().id, writes.toList(), at = at)
    private fun read(command: CoachCommand): JsonElement = db.executeCoachRead(turn().id, command)
    private fun JsonElement.field(key: String) = jsonObject[key]!!

    @Test fun mealsForDatePageWithCursor() {
        repeat(25) { write(CoachWrite.Food(today, listOf(food("Synthetic apple $it")), null)) }
        val first = read(CoachCommand.Meals(today, null))
        assertEquals(20, first.field("meals").jsonArray.size)
        assertEquals("true", first.field("hasMore").jsonPrimitive.content)
        val cursor = UUID.fromString(first.field("nextAfterMealID").jsonPrimitive.content)
        val second = read(CoachCommand.Meals(today, cursor))
        assertEquals(5, second.field("meals").jsonArray.size)
        assertEquals("false", second.field("hasMore").jsonPrimitive.content)
    }

    @Test fun findMealAndGetMeal() {
        val mealID = write(CoachWrite.Food(today, listOf(food("Synthetic 100% rye")), null)).single().mealID!!
        write(CoachWrite.Food(today, listOf(food("Synthetic pear")), null))
        val found = read(CoachCommand.FindMeals("100%", null, null)).jsonArray
        assertEquals(mealID.toString().uppercase(), found.single().field("id").jsonPrimitive.content)
        assertEquals("Synthetic read", found.single().field("capturedDescription").jsonPrimitive.content)
        val meal = read(CoachCommand.Meal(mealID))
        assertEquals("Synthetic 100% rye", meal.field("items").jsonArray.single().field("name").jsonPrimitive.content)
    }

    @Test fun progressWorkoutAndContext() {
        write(CoachWrite.Food(today, listOf(food("Synthetic apple")), null), CoachWrite.Weight(today, 70.0, "kg", null))
        val workoutID = write(CoachWrite.Workout(today, WorkoutDraft(WorkoutKind.cardio, 20, emptyList()))).single().workoutID!!
        val progress = read(CoachCommand.Progress(today, 7))
        assertEquals("open", progress.field("daily").field("status").jsonPrimitive.content)
        assertEquals(95.0, progress.field("daily").field("foodTotals").field("kcal").jsonPrimitive.content.toDouble(), 0.0)
        assertEquals(1, progress.field("weights").jsonArray.size)
        assertEquals(1, progress.field("workouts").jsonArray.size)
        assertEquals(7, progress.field("period").field("dayCount").jsonPrimitive.content.toInt())
        assertEquals("insufficientData", progress.field("weight").field("plateau").jsonPrimitive.content)
        assertEquals("20", read(CoachCommand.Workout(workoutID)).field("durationMinutes").jsonPrimitive.content)
        assertEquals("Synthetic", read(CoachCommand.Context).field("profile").field("name").jsonPrimitive.content)
    }

    @Test fun goalsPreferencesAndLookup() {
        write(CoachWrite.Manual(CoachManualEdit.Goals("2026-10-01", listOf(CoachNutrientEdit("kcal", 2000.0)), null, false, null, null)))
        val goals = read(CoachCommand.Goals(today))
        assertTrue(goals.jsonObject["exact"] == null || goals.field("exact") is JsonNull)
        assertEquals("2026-10-01", goals.field("effective").field("effectiveLocalDate").jsonPrimitive.content)
        val preferences = read(CoachCommand.Preferences)
        assertEquals("Synthetic preference", preferences.field("profile").field("preferences").jsonPrimitive.content)
        assertEquals(db.head().revision.toString(), preferences.field("diaryRevision").jsonPrimitive.content)
        assertEquals("false", read(CoachCommand.Lookup("Synthetic apple")).field("available").jsonPrimitive.content)
        try { read(CoachCommand.Write(CoachWrite.Food(today, listOf(food("Synthetic")), null))); fail() } catch (_: CoachError.InvalidArguments) {}
    }
}
