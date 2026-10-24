package com.yakov103.mivu.coach

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.yakov103.mivu.diary.CoachCaptureContext
import com.yakov103.mivu.diary.CoachClarification
import com.yakov103.mivu.diary.CoachQuestion
import com.yakov103.mivu.diary.CoachReceipt
import com.yakov103.mivu.diary.CoachReply
import com.yakov103.mivu.diary.CoachSubmissionPayload
import com.yakov103.mivu.diary.CoachTurn
import com.yakov103.mivu.diary.CoachTurnState
import com.yakov103.mivu.diary.DayCompleteness
import com.yakov103.mivu.diary.DiaryDatabase
import com.yakov103.mivu.diary.DiaryMeal
import com.yakov103.mivu.diary.DiaryProfile
import com.yakov103.mivu.diary.FoodItem
import com.yakov103.mivu.diary.NutritionProvenance
import com.yakov103.mivu.diary.NutritionValues
import com.yakov103.mivu.diary.SwiftJson
import com.yakov103.mivu.diary.TrackingDay
import java.io.File
import java.time.Instant
import java.time.LocalDate
import java.util.UUID
import kotlinx.serialization.builtins.ListSerializer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/** Synthetic diaries only, as the iOS ChatHistoryFixture; context contents are never logged. */
class CoachContextTest {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val profile = DiaryProfile(UUID.randomUUID(), "Synthetic \"profile\" 🍎", "en", "UTC", "")
    private lateinit var db: DiaryDatabase
    private val at = Instant.parse("2026-10-24T12:00:00Z")
    private val edges = listOf("Synthetic", "é שלום 🍎", "\"quoted\"", "\\path/", "line\nbreak\t")

    @Before fun open() {
        File(context.filesDir, "profiles").deleteRecursively()
        db = DiaryDatabase.create(context, profile)
    }

    @After fun close() {
        db.close()
        File(context.filesDir, "profiles").deleteRecursively()
    }

    private fun day(i: Int) = TrackingDay(UUID.randomUUID(), LocalDate.of(2026, 1, 1).plusDays(i.toLong()).toString(), "UTC", at,
        DayCompleteness.unknown)
    private fun item(name: String = "Synthetic rice") = FoodItem(UUID.randomUUID(), name, 1.0, "serving",
        NutritionValues(100.0, 10.0, 5.0, 2.0), NutritionProvenance.estimate, "", true, emptyMap())
    private fun meal(day: TrackingDay, items: List<FoodItem> = listOf(item()), changed: Int? = null) =
        DiaryMeal(UUID.randomUUID(), day.id, at, at, 1, changed, null, items, emptyList(), emptyList())
    private fun turn(text: String = "Synthetic", assistant: String? = "Synthetic reply", day: TrackingDay? = null,
                     receipts: (UUID) -> List<CoachReceipt> = { emptyList() }, reply: CoachReply? = null,
                     question: CoachQuestion? = null): CoachTurn {
        val id = UUID.randomUUID()
        val manifest = reply?.let { CoachSubmissionPayload(id, text, emptyList(), CoachCaptureContext(at, "UTC"), reply = it).manifest }
        return CoachTurn(id, at, text, emptyList(), CoachTurnState.completed, assistant, receipts(id), "UTC", day?.id,
            emptyList(), submissionManifest = manifest, question = question)
    }

    private fun seed(days: List<TrackingDay>, meals: List<DiaryMeal> = emptyList(), turns: List<CoachTurn>) {
        db.replaceAll(db.snapshot().copy(revision = 5, days = days, meals = meals, coachTurns = turns, activeDayID = days.lastOrNull()?.id))
        db.snapshotReads = 0
    }

    private fun bytes(value: CoachContext) = coachJSON(CoachContext.serializer(), value).toByteArray().size

    @Test fun contextStaysWithin60000Bytes() {
        val days = List(30) { day(it) }
        val longName = "Synthetic " + "🍎".repeat(120)
        val meals = days.flatMap { d -> List(60) { meal(d, List(20) { item(longName) }) } }
        val turns = List(2_000) { i -> turn(edges[i % edges.size].repeat(300), "Bounded reply. ".repeat(100), days.last()) }
        seed(days, meals, turns)
        val built = db.coachInferenceContext(turns.last().id)
        assertTrue(bytes(built) <= 60_000)
        assertTrue(SwiftJson.encodeToString(ListSerializer(CoachContext.Meal.serializer()), built.meals).toByteArray().size <= 24_000)
        assertTrue(SwiftJson.encodeToString(ListSerializer(CoachContext.Turn.serializer()), built.recentTurns).toByteArray().size <= 8192)
        assertTrue(built.truncated)
        assertTrue(built.recentTurns.isNotEmpty() && built.meals.isNotEmpty())
        assertEquals(0, db.snapshotReads)
    }

    @Test fun fourteenDayWindow() {
        val days = List(20) { day(it) }
        val meals = days.map { meal(it) }
        val turns = listOf(turn(day = days.last()))
        seed(days, meals, turns)
        val built = db.coachInferenceContext(turns[0].id)
        assertEquals(days.takeLast(14), built.days)
        assertEquals(meals.takeLast(14).map { it.id }, built.meals.map { it.id })
        assertEquals(0, built.additionalMealCount)
        assertEquals(days.last().id, built.activeDayID)
    }

    @Test fun fortyMealCap() {
        val days = listOf(day(0))
        val meals = List(50) { meal(days[0]) }
        val turns = listOf(turn(day = days[0]))
        seed(days, meals, turns)
        val built = db.coachInferenceContext(turns[0].id)
        assertEquals(meals.takeLast(40).map { it.id }, built.meals.map { it.id })
        assertEquals(10, built.additionalMealCount)
        assertTrue(built.truncated)
    }

    @Test fun recentTurnsCapped() {
        val days = listOf(day(0))
        val earlier = List(30) { turn("Synthetic $it") }
        val current = turn("Current")
        val later = turn("Later")
        seed(days, turns = earlier + current + later)
        val short = db.coachInferenceContext(current.id)
        assertEquals(earlier.takeLast(12).map { it.id }, short.recentTurns.map { it.id })
        assertTrue(!short.truncated)

        val long = earlier.map { it.copy(text = "é".repeat(2_000), assistantText = "x".repeat(2_000)) }
        db.replaceAll(db.snapshot().copy(coachTurns = long + current + later))
        val bounded = db.coachInferenceContext(current.id)
        assertTrue(SwiftJson.encodeToString(ListSerializer(CoachContext.Turn.serializer()), bounded.recentTurns).toByteArray().size <= 8192)
        assertTrue(bounded.recentTurns.size < 12 && bounded.truncated)
        assertEquals(long.last().id, bounded.recentTurns.last().id)
        assertTrue(bounded.recentTurns.all { it.text.toByteArray().size <= 1024 && it.text.endsWith("…") })
    }

    @Test fun replyToMealResolves() {
        val days = listOf(day(0))
        val lunch = meal(days[0], listOf(item("Synthetic lunch"), item("Synthetic salad")))
        val toMeal = turn("Make it bigger", reply = CoachReply(CoachReply.Target.Meal(lunch.id), "Synthetic lunch"))
        val toItem = turn("Only the salad", reply = CoachReply(CoachReply.Target.Item(lunch.id, lunch.items[1].id), "Synthetic salad"))
        seed(days, listOf(lunch), listOf(toMeal, toItem))
        val meal = db.coachInferenceContext(toMeal.id).replyTo!!
        assertEquals(lunch.id, meal.meal?.id)
        assertEquals(lunch.items, meal.meal?.items)
        assertNull(meal.unavailable)
        val item = db.coachInferenceContext(toItem.id).replyTo!!
        assertEquals(lunch.id, item.meal?.id)
        assertNull(item.unavailable)
    }

    @Test fun replyToDeletedIsUnavailable() {
        val days = listOf(day(0))
        val lunch = meal(days[0])
        val gone = turn("Remove it", reply = CoachReply(CoachReply.Target.Meal(UUID.randomUUID()), "Deleted lunch"))
        val goneItem = turn("Fix it", reply = CoachReply(CoachReply.Target.Item(lunch.id, UUID.randomUUID()), "Deleted item"))
        val goneMessage = turn("About that", reply = CoachReply(CoachReply.Target.Message(UUID.randomUUID(), true), "Earlier reply"))
        seed(days, listOf(lunch), listOf(gone, goneItem, goneMessage))
        for (t in listOf(gone, goneItem, goneMessage)) {
            val reply = db.coachInferenceContext(t.id).replyTo!!
            assertEquals(true, reply.unavailable)
            assertNull(reply.meal)
            assertNull(reply.turn)
        }
    }

    @Test fun assistantSuffixListsSavedKeys() {
        val days = listOf(day(0))
        val lunch = meal(days[0])
        val saved = turn("Synthetic lunch", "Logged it.", receipts = { id ->
            listOf(
                CoachReceipt("$id/food/2026-01-01".uppercase(), id, days[0].id, lunch.id, lunch.items[0].id, committedRevision = 1, resultJSON = "{}"),
                CoachReceipt("$id/weight".uppercase(), id, days[0].id, weightID = UUID.randomUUID(), committedRevision = 1, resultJSON = "{}"),
            )
        })
        val photoOnly = turn("", null)
        val current = turn("And a coffee")
        seed(days, listOf(lunch), listOf(saved, photoOnly, current))
        val key = saved.receipts[0].operationKey
        val line = "[saved key=$key meal=${lunch.id.toString().uppercase()} item=${lunch.items[0].id.toString().uppercase()}]"
        assertEquals(line, db.coachInferenceContext(current.id).recentTurns[0].receipts)
        assertEquals(
            listOf(
                CoachInferenceInput.Message(CoachInferenceInput.Role.user, "Synthetic lunch"),
                CoachInferenceInput.Message(CoachInferenceInput.Role.assistant, "Logged it.\n$line"),
                CoachInferenceInput.Message(CoachInferenceInput.Role.user, "[photo]"),
            ),
            db.coachHistoryMessages(current.id),
        )
    }

    @Test fun focusNamesLastChangedMealAndPendingQuestion() {
        val days = listOf(day(0))
        val older = meal(days[0], changed = 2)
        val newer = meal(days[0], List(10) { item("Synthetic $it") }, changed = 4)
        val question = CoachQuestion(CoachClarification.confirm, listOf(CoachReply.Target.Meal(newer.id)), "")
        val asked = turn("Remove the snack", "Remove it?", question = question)
        val current = turn("Yes", day = days[0])
        seed(days, listOf(older, newer), listOf(asked, current))
        val focus = db.coachInferenceContext(current.id).focus!!
        assertEquals(newer.id, focus.lastChanged?.mealID)
        assertEquals(newer.items.take(8).map { it.name }, focus.lastChanged?.itemNames)
        assertEquals(question.copy(originalText = "Remove the snack"), focus.pendingQuestion)
    }

    @Test fun buildsWithoutFullSnapshot() {
        val days = listOf(day(0))
        val turns = List(10_000) { turn("Synthetic $it", day = days[0]) }
        seed(days, turns = turns)
        val started = System.nanoTime()
        db.coachInferenceContext(turns.last().id)
        db.coachHistoryMessages(turns.last().id)
        assertEquals(0, db.snapshotReads)
        assertTrue((System.nanoTime() - started) / 1_000_000 < 2_000)
    }
}
