package com.yakov103.mivu.diary

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.yakov103.mivu.coach.CoachEngine
import com.yakov103.mivu.coach.CoachError
import com.yakov103.mivu.coach.CoachInferenceResult
import com.yakov103.mivu.coach.CoachManualEdit
import com.yakov103.mivu.coach.CoachToolCall
import com.yakov103.mivu.coach.coachInferenceContext
import com.yakov103.mivu.coach.CoachWrite
import java.io.File
import java.time.Instant
import java.time.temporal.ChronoUnit
import java.util.UUID
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test

/** Synthetic diaries only; ports iOS CoachDeleteUndoTests: Coach deletes stay instant but keep a short-lived, unexported copy. */
class CoachDeleteUndoTest {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val profile = DiaryProfile(UUID.randomUUID(), "Synthetic", "en", "UTC", "")
    private lateinit var db: DiaryDatabase
    private var clock = Instant.now().truncatedTo(ChronoUnit.SECONDS)
    private val photoBytes = byteArrayOf(1, 2, 3)

    private val today get() = diaryDateLabel(clock, "UTC")

    @Before fun open() {
        File(context.filesDir, "profiles").deleteRecursively()
        db = DiaryDatabase.create(context, profile)
        db.startDay(clock, db.head().revision)
    }

    @After fun close() {
        db.close()
        File(context.filesDir, "profiles").deleteRecursively()
    }

    private inline fun <reified E : Throwable> throws(block: () -> Unit) {
        try { block(); fail("expected ${E::class.simpleName}") } catch (e: Throwable) { if (e !is E) throw e }
    }

    private fun food(name: String, kcal: Double) = FoodItem(UUID.randomUUID(), name, 1.0, "cup", NutritionValues(kcal = kcal),
        NutritionProvenance.estimate, "Synthetic", true, emptyMap())

    private fun turn(text: String = "Synthetic request", photos: List<MealPhoto> = emptyList()): CoachTurn {
        val h = db.head()
        return db.captureCoachSubmission(CoachSubmissionPayload(UUID.randomUUID(), text, photos,
            CoachCaptureContext(clock, "UTC", h.activeDayID, h.previousDayConfirmedAt, h.activeConversationSegmentID)), h.revision, clock)
    }

    private fun apply(vararg writes: CoachWrite, turn: CoachTurn = turn()) = db.applyCoachWrites(turn.id, writes.toList(), at = clock)
    private fun manual(edit: CoachManualEdit) = CoachWrite.Manual(edit)
    private fun meals() = db.snapshot().meals

    /** A saved two-food meal with one photo, logged through Coach. */
    private fun fixture(): DiaryMeal {
        val photo = MealPhoto(UUID.randomUUID(), photoBytes, clock, PhotoRole.unspecified)
        val receipt = apply(CoachWrite.Food(today, listOf(food("Rice", 200.0), food("Beans", 220.0)), null), turn = turn(photos = listOf(photo))).single()
        return meals().single { it.id == receipt.mealID }.also { assertArrayEquals(photoBytes, it.photos.single().data) }
    }

    private fun deleteMeal(meal: DiaryMeal) = apply(manual(CoachManualEdit.DeleteMeal(meal.id, meal.revision))).single()

    private fun undoState(receipt: CoachReceipt) =
        db.coachPage(CoachPageRequest.Latest, now = clock).exchanges.single { it.turn.id == receipt.turnID }.undo[receipt.operationKey]

    private fun count(table: String) = db.read { it.query("SELECT COUNT(*) FROM $table", emptyList()) { c -> c.moveToFirst(); c.getInt(0) } }

    private fun tombstoned(id: UUID) = db.read { it.isTombstoned(DiaryDatabase.Tombstone.meal, id) }

    private fun weightAndWorkout(dayID: UUID): Pair<WeightEntry, WorkoutSession> = db.transaction(null) { tx ->
        tx.setWeight(dayID, 70.0, "kg", null) to tx.createWorkout(dayID, WorkoutDraft(WorkoutKind.cardio, 30, emptyList(), null, null))
    }

    @Test fun deleteMealHoldsSnapshotWithPhotos() {
        val meal = fixture()
        val receipt = deleteMeal(meal)
        assertEquals(CoachUndoState.Available, undoState(receipt))
        // The held copy never reaches the diary read the archive, backup and report use.
        assertTrue(meals().isEmpty())
        assertTrue(db.snapshot().coachTurns.none { t -> t.photos.any { it.data.contentEquals(photoBytes) } })
        assertEquals(1, count("coach_undo_deleted_photo"))
    }

    @Test fun deleteWeightAndWorkoutHoldSnapshots() {
        val meal = fixture()
        val (weight, workout) = weightAndWorkout(meal.dayID)
        val receipts = apply(CoachWrite.DeleteWeight(weight.id, weight.revision), CoachWrite.DeleteWorkout(workout.id, workout.revision))
        assertEquals(2, receipts.size)
        receipts.forEach { assertEquals(CoachUndoState.Available, undoState(it)) }
        assertTrue(db.snapshot().weights.isEmpty() && db.snapshot().workouts.isEmpty())
    }

    @Test fun undoExpiresAfterTenMinutes() {
        val receipt = deleteMeal(fixture())
        clock = clock.plusSeconds(601)
        assertNull(undoState(receipt))
        throws<DiaryError.StaleRevision> { db.undoCoachChange(receipt.operationKey, clock) }
        assertTrue(meals().isEmpty())
    }

    @Test fun startupPurgesExpiredCopies() {
        clock = Instant.now().truncatedTo(ChronoUnit.SECONDS).minusSeconds(601)
        deleteMeal(fixture())
        assertEquals(1, count("coach_undo_deleted"))
        db.close()
        db = DiaryDatabase.open(context, profile.id)
        assertEquals(0, count("coach_undo_deleted"))
        assertEquals(0, count("coach_undo_deleted_photo"))
    }

    @Test fun buttonHidesAfterNextMessageButRowSurvivesOneTurn() {
        val receipt = deleteMeal(fixture())
        turn("Next message")
        assertNull(undoState(receipt))
        assertEquals(1, count("coach_undo_deleted"))
        turn("Message after that")
        assertEquals(0, count("coach_undo_deleted"))
        assertEquals(0, count("coach_undo_deleted_photo"))
    }

    @Test fun heldBytesLiveInTheProfilesOwnFile() {
        deleteMeal(fixture())
        // DiaryRepository removes the profile's whole folder, so the held photo goes with it.
        assertTrue(db.file.exists() && db.file.parentFile!!.name.equals(profile.id.toString(), ignoreCase = true))
        assertEquals(1, count("coach_undo_deleted_photo"))
    }

    @Test fun undoOfLoggedMealHoldsSnapshot() {
        val logged = apply(CoachWrite.Food(today, listOf(food("Apple", 95.0)), null)).single()
        val undo = apply(manual(CoachManualEdit.Undo(logged.operationKey))).single()
        assertTrue(meals().isEmpty())
        assertEquals(CoachUndoState.Available, undoState(undo))
    }

    @Test fun undoRestoresMealUnderNewIDWithPhotos() {
        val meal = fixture()
        val receipt = deleteMeal(meal)
        db.undoCoachChange(receipt.operationKey, clock)
        val restored = meals().single()
        assertTrue(restored.id != meal.id)
        assertEquals(meal.dayID, restored.dayID)
        assertEquals(listOf("Rice", "Beans"), restored.items.map { it.name })
        assertEquals(listOf(200.0, 220.0), restored.items.map { it.nutrition.kcal })
        assertArrayEquals(photoBytes, restored.photos.single().data)
        assertTrue(tombstoned(meal.id))
        assertEquals(CoachUndoState.Undone, undoState(receipt))
    }

    @Test fun undoRestoresPhotoToExistingMeal() {
        val meal = fixture()
        val receipt = apply(manual(CoachManualEdit.DeletePhoto(meal.id, meal.photos.single().id, meal.revision))).single()
        assertTrue(meals().single().photos.isEmpty())
        db.undoCoachChange(receipt.operationKey, clock)
        assertArrayEquals(photoBytes, meals().single().photos.single().data)
    }

    @Test fun photoUndoRefusedWhenMealGone() {
        val meal = fixture()
        val receipt = apply(manual(CoachManualEdit.DeletePhoto(meal.id, meal.photos.single().id, meal.revision))).single()
        db.deleteMeal(meal.id, db.head().revision)
        throws<DiaryError.NotFound> { db.undoCoachChange(receipt.operationKey, clock) }
    }

    @Test fun weightUndoRefusedWhenDayHasWeight() {
        val meal = fixture()
        val (weight, _) = weightAndWorkout(meal.dayID)
        val receipt = apply(CoachWrite.DeleteWeight(weight.id, weight.revision)).single()
        db.setWeight(meal.dayID, 71.0, "kg", null)
        throws<DiaryError.StaleRevision> { db.undoCoachChange(receipt.operationKey, clock) }
    }

    @Test fun weightAndWorkoutUndoRestore() {
        val meal = fixture()
        val (weight, workout) = weightAndWorkout(meal.dayID)
        val receipts = apply(CoachWrite.DeleteWeight(weight.id, weight.revision), CoachWrite.DeleteWorkout(workout.id, workout.revision))
        receipts.forEach { db.undoCoachChange(it.operationKey, clock) }
        val snapshot = db.snapshot()
        assertEquals(listOf(70.0), snapshot.weights.map { it.value })
        assertTrue(snapshot.weights.single().id != weight.id)
        assertEquals(listOf(30), snapshot.workouts.map { it.durationMinutes })
        assertTrue(snapshot.workouts.single().id != workout.id)
    }

    @Test fun secondUndoIsStale() {
        val receipt = deleteMeal(fixture())
        db.undoCoachChange(receipt.operationKey, clock)
        throws<DiaryError.StaleRevision> { db.undoCoachChange(receipt.operationKey, clock) }
        assertEquals(1, meals().size)
    }

    @Test fun voiceUndoWorksInTheNextMessage() {
        val receipt = deleteMeal(fixture())
        val undo = apply(manual(CoachManualEdit.Undo(receipt.operationKey)), turn = turn("Undo that")).single()
        assertEquals(1, meals().size)
        assertEquals(meals().single().id, undo.mealID)
    }

    @Test fun voiceUndoRefusedTwoMessagesLater() {
        val receipt = deleteMeal(fixture())
        turn("Something else")
        // The second message after the delete erased the copy, so the key is unknown.
        throws<CoachError.InvalidArguments> { apply(manual(CoachManualEdit.Undo(receipt.operationKey)), turn = turn("Undo that")) }
        assertTrue(meals().isEmpty())
    }

    @Test fun voiceUndoRunsThroughTheEngine() {
        clock = Instant.now().truncatedTo(ChronoUnit.SECONDS) // the engine writes at the real time
        val receipt = deleteMeal(fixture())
        val t = turn("Undo that")
        val call = CoachToolCall("fc_u", "call_u", "undo_change", "mivu", """{"operation_key":"${receipt.operationKey}"}""")
        val rounds = mutableListOf(
            CoachInferenceResult("fixture-model", "", listOf(call), listOf(buildJsonObject {
                put("type", "function_call"); put("id", call.id); put("call_id", call.callID); put("name", call.name)
                put("namespace", "mivu"); put("arguments", call.arguments); put("status", "completed")
            }.toString())),
            CoachInferenceResult("fixture-model", "Undone", emptyList(), emptyList()),
        )
        val done = runBlocking { CoachEngine(db, { _, _ -> rounds.removeAt(0) }).run(t.id) }
        assertEquals(1, done.receipts.size)
        assertEquals(1, meals().size)
    }

    @Test fun undoOfUndoRecreatesLoggedMeal() {
        val logged = apply(CoachWrite.Food(today, listOf(food("Apple", 95.0)), null)).single()
        val removal = apply(manual(CoachManualEdit.Undo(logged.operationKey))).single()
        assertTrue(meals().isEmpty())
        db.undoCoachChange(removal.operationKey, clock)
        assertEquals(listOf("Apple"), meals().flatMap { it.items }.map { it.name })
    }

    @Test fun deleteResultTellsTheModelHowToUndo() {
        val receipt = deleteMeal(fixture())
        assertTrue("\"undo_key\":\"${receipt.operationKey}\"" in receipt.resultJSON)
        assertTrue("\"undo_until\":\"next message\"" in receipt.resultJSON)
        // The receipt on disk is the one the model saw.
        assertEquals(receipt, db.coachTurn(receipt.turnID)!!.receipts.single { it.operationKey == receipt.operationKey })
    }

    @Test fun captureSurvivesAFailedUndoPurge() {
        deleteMeal(fixture())
        db.read { it.exec("CREATE TRIGGER block_purge BEFORE DELETE ON coach_undo_deleted BEGIN SELECT RAISE(ABORT, 'synthetic purge failure'); END", emptyList()) }
        clock = clock.plusSeconds(601)
        val next = turn("Next message")
        assertEquals(next.id, db.coachTurn(next.id)!!.id)
    }

    @Test fun deleteStillHappensWhenThePhoneHasNoRoomForTheCopy() {
        val meal = fixture()
        db.freeBytes = { 0 } // no room for the held photo
        val receipt = deleteMeal(meal)
        assertTrue(meals().isEmpty())
        assertNull(undoState(receipt))
        assertFalse("\"undo_key\"" in receipt.resultJSON)
    }

    @Test fun historyMarksMealsDeletedSince() {
        val apple = apply(CoachWrite.Food(today, listOf(food("Apple", 95.0)), null)).single()
        db.deleteMeal(apple.mealID!!, db.head().revision)
        val next = turn("Make it bigger")
        val id = apple.mealID!!.toString().uppercase()
        val line = db.coachInferenceContext(next.id).recentTurns.mapNotNull { it.receipts }.single { id in it }
        assertTrue(line, "meal=$id deleted" in line)
    }

    @Test fun historyLeavesLiveMealsUnmarked() {
        apply(CoachWrite.Food(today, listOf(food("Apple", 95.0)), null))
        val next = turn("Make it bigger")
        val lines = db.coachInferenceContext(next.id).recentTurns.mapNotNull { it.receipts }
        assertTrue(lines.isNotEmpty() && lines.none { "deleted" in it })
    }
}
