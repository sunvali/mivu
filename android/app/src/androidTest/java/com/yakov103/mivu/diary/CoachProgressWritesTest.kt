package com.yakov103.mivu.diary

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.yakov103.mivu.coach.CoachManualEdit
import com.yakov103.mivu.coach.CoachNutrientEdit
import com.yakov103.mivu.coach.CoachWrite
import java.io.File
import java.time.Instant
import java.util.UUID
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test

/** Synthetic diaries only: weight, workout, goal and preference Coach writes (DiaryDatabaseCoachMutations.swift). */
class CoachProgressWritesTest {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val profile = DiaryProfile(UUID.randomUUID(), "Synthetic", "en", "UTC", "")
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

    private inline fun <reified E : Throwable> throws(block: () -> Unit) {
        try { block(); fail("expected ${E::class.simpleName}") } catch (e: Throwable) { if (e !is E) throw e }
    }

    private fun turn(): CoachTurn {
        val h = db.head()
        return db.captureCoachSubmission(CoachSubmissionPayload(UUID.randomUUID(), "Synthetic progress", emptyList(),
            CoachCaptureContext(at, "UTC", h.activeDayID, h.previousDayConfirmedAt, h.activeConversationSegmentID)), h.revision)
    }

    private fun apply(vararg writes: CoachWrite, turn: CoachTurn = turn()) = db.applyCoachWrites(turn.id, writes.toList(), at = at)
    private val draft = WorkoutDraft(WorkoutKind.strength, 30, listOf(WorkoutExercise("Synthetic squat", listOf(WorkoutSet(5, 60.0)))))

    @Test fun weightLogAndCorrect() {
        val logged = apply(CoachWrite.Weight(today, 70.0, "kg", null)).single()
        val id = logged.weightID!!
        assertEquals(db.head().activeDayID, logged.dayID)
        assertNull(db.read { it.coachUndo(logged.operationKey) }) // iOS keeps undo for food only
        // A second log for the date corrects the existing entry, and needs its revision.
        throws<DiaryError.StaleRevision> { apply(CoachWrite.Weight(today, 72.0, "kg", null)) }
        val corrected = apply(CoachWrite.Weight(today, 71.0, "kg", 1)).single()
        assertTrue(corrected.operationKey.endsWith("/correct_weight/${id.swift}"))
        val stored = db.read { it.weight(id) }
        assertEquals(71.0, stored.value, 0.0)
        assertEquals(2, stored.revision)
        val t = turn()
        val delete = CoachWrite.DeleteWeight(id, 2)
        val deleted = db.applyCoachWrites(t.id, listOf(delete), at = at)
        assertTrue(db.read { it.isTombstoned(DiaryDatabase.Tombstone.weight, id) })
        assertEquals(deleted, db.applyCoachWrites(t.id, listOf(delete), at = at))
    }

    @Test fun workoutLogEditDelete() {
        val logged = apply(CoachWrite.Workout(today, draft)).single()
        val id = logged.workoutID!!
        apply(CoachWrite.EditWorkout(id, draft.copy(durationMinutes = 45), 1))
        assertEquals(45, db.read { it.workout(id) }.durationMinutes)
        throws<DiaryError.StaleRevision> { apply(CoachWrite.DeleteWorkout(id, 1)) }
        apply(CoachWrite.DeleteWorkout(id, 2))
        assertTrue(db.read { it.isTombstoned(DiaryDatabase.Tombstone.workout, id) })
    }

    @Test fun setGoals() {
        val created = apply(CoachWrite.Manual(CoachManualEdit.Goals(today, listOf(CoachNutrientEdit("kcal", 2000.0)), null, false, null, null))).single()
        assertEquals(1, db.read { it.exactGoal(today) }!!.revision)
        throws<DiaryError.StaleRevision> {
            apply(CoachWrite.Manual(CoachManualEdit.Goals(today, listOf(CoachNutrientEdit("fat", 70.0)), null, false, null, null)))
        }
        apply(CoachWrite.Manual(CoachManualEdit.Goals(today, listOf(CoachNutrientEdit("protein", 120.0)), 80.0, false, true, 1)))
        val goal = db.read { it.exactGoal(today) }!!
        assertEquals(created.goalID, goal.id)
        assertEquals(NutritionValues(kcal = 2000.0, protein = 120.0), goal.targets)
        assertEquals(80.0, goal.goalWeightKg!!, 0.0)
        assertTrue(goal.exerciseCreditEnabled)
        assertEquals(2, goal.revision)
    }

    @Test fun updatePreferences() {
        val t = turn()
        val receipt = db.applyCoachWrites(t.id, listOf(CoachWrite.Manual(CoachManualEdit.Preferences("Asia/Jerusalem", "Synthetic vegetarian",
            db.head().revision.toInt()), "synthetic-patch")), at = at).single()
        assertEquals("Asia/Jerusalem", db.head().profile.timeZoneID)
        assertEquals("Synthetic vegetarian", db.head().profile.preferences)
        assertNull(receipt.dayID)
        assertTrue("\"diaryRevision\":${db.head().revision}" in receipt.resultJSON)
    }
}
