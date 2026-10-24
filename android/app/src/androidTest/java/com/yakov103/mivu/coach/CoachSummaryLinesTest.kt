package com.yakov103.mivu.coach

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.yakov103.mivu.diary.CoachCaptureContext
import com.yakov103.mivu.diary.CoachReceipt
import com.yakov103.mivu.diary.CoachSubmissionPayload
import com.yakov103.mivu.diary.CoachTurn
import com.yakov103.mivu.diary.DayCompleteness
import com.yakov103.mivu.diary.DiaryDatabase
import com.yakov103.mivu.diary.DiaryMeal
import com.yakov103.mivu.diary.DiaryProfile
import com.yakov103.mivu.diary.FoodItem
import com.yakov103.mivu.diary.MealPhoto
import com.yakov103.mivu.diary.NutritionProvenance
import com.yakov103.mivu.diary.NutritionValues
import com.yakov103.mivu.diary.PhotoRole
import com.yakov103.mivu.diary.WorkoutDraft
import com.yakov103.mivu.diary.WorkoutKind
import com.yakov103.mivu.diary.applyCoachWrites
import com.yakov103.mivu.diary.captureCoachSubmission
import com.yakov103.mivu.diary.startDay
import java.io.File
import java.time.Instant
import java.util.UUID
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test

/**
 * Synthetic diaries only. Expected lines are copied from iOS `coachReceiptSummary` (DiaryDatabaseQueries.swift:390-460) and its
 * tests (CoachUndoTests:112, CoachScaleMealTests:115, CoachReceiptFeedbackTests:177, CoachEngineTests:523); one receipt kind each.
 */
class CoachSummaryLinesTest {
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

    private fun food(name: String, kcal: Double? = 95.0) = FoodItem(UUID.randomUUID(), name, 1.0, "piece", NutritionValues(kcal = kcal),
        NutritionProvenance.estimate, "Synthetic", true, emptyMap())
    private fun photo(id: UUID = UUID.randomUUID()) = MealPhoto(id, byteArrayOf(1, 2, 3), at, PhotoRole.unspecified)

    private fun turn(photos: List<MealPhoto> = emptyList()): CoachTurn {
        val h = db.head()
        return db.captureCoachSubmission(CoachSubmissionPayload(UUID.randomUUID(), "Synthetic request", photos,
            CoachCaptureContext(at, "UTC", h.activeDayID, h.previousDayConfirmedAt, h.activeConversationSegmentID)), h.revision)
    }

    private fun apply(vararg writes: CoachWrite, turn: CoachTurn = turn()): List<CoachReceipt> = db.applyCoachWrites(turn.id, writes.toList(), at = at)
    private fun manual(edit: CoachManualEdit) = CoachWrite.Manual(edit)
    private fun meal(id: UUID): DiaryMeal = db.read { it.meal(id) }!!
    private fun log(vararg items: FoodItem): CoachReceipt = apply(CoachWrite.Food(today, items.toList(), null)).single()
    private fun summary(receipt: CoachReceipt) = db.coachCommittedSummary(receipt.turnID)

    @Test fun undoOfLogSaysRemoved() {
        val logged = log(food("Synthetic apple"), food("Synthetic pear"))
        assertEquals("Removed Synthetic apple, Synthetic pear.", summary(apply(manual(CoachManualEdit.Undo(logged.operationKey))).single()))
    }

    @Test fun undoOfEditSaysUndid() {
        val m = meal(log(food("Synthetic pasta"), food("Synthetic sauce")).mealID!!)
        val scaled = apply(manual(CoachManualEdit.ScaleMeal(m.id, 380.0, m.revision))).single()
        assertEquals("Undid the change to Synthetic pasta, Synthetic sauce.", summary(apply(manual(CoachManualEdit.Undo(scaled.operationKey))).single()))
    }

    @Test fun scaleShowsBeforeAndAfter() {
        val one = meal(log(food("Synthetic rice", 400.0), food("Synthetic herbs", null)).mealID!!)
        assertEquals("Updated Synthetic rice, Synthetic herbs: 400 → 200 kcal. Synthetic herbs has no calories set, so it isn't counted.",
            summary(apply(manual(CoachManualEdit.ScaleMeal(one.id, 200.0, one.revision))).single()))
        val two = meal(log(food("Synthetic rice", 400.0), food("Synthetic herbs", null), food("Synthetic salt", null)).mealID!!)
        assertEquals("Updated Synthetic rice, Synthetic herbs, Synthetic salt: 400 → 200 kcal. Synthetic herbs, Synthetic salt have no " +
            "calories set, so they aren't counted.", summary(apply(manual(CoachManualEdit.ScaleMeal(two.id, 200.0, two.revision))).single()))
    }

    @Test fun moveSaysShortDate() {
        val m = meal(log(food("Synthetic apple")).mealID!!)
        val moved = apply(manual(CoachManualEdit.Move(m.id, "2026-10-23", m.revision, m.dayID))).single()
        assertEquals("Moved to ${CoachReplyLines.shortDate("2026-10-23")}.", summary(moved))
    }

    @Test fun attachPhotosCounts() {
        val one = meal(log(food("Synthetic soup")).mealID!!)
        val t1 = turn(listOf(photo()))
        assertEquals("Added the photo.", summary(apply(manual(CoachManualEdit.Attach(one.id, t1.photoIDs, PhotoRole.before, one.revision)), turn = t1).single()))
        val two = meal(log(food("Synthetic salad")).mealID!!)
        val t2 = turn(listOf(photo(), photo()))
        assertEquals("Added 2 photos.", summary(apply(manual(CoachManualEdit.Attach(two.id, t2.photoIDs, PhotoRole.after, two.revision)), turn = t2).single()))
    }

    @Test fun deletePhotoConfirms() {
        val m = meal(log(food("Synthetic soup")).mealID!!)
        val shared = UUID.randomUUID()
        val first = turn(listOf(photo(shared)))
        val again = turn(listOf(photo(shared))) // a second copy of the same photo, attached after the delete
        apply(manual(CoachManualEdit.Attach(m.id, listOf(shared), PhotoRole.unspecified, m.revision)), turn = first)
        val deleted = apply(manual(CoachManualEdit.DeletePhoto(m.id, shared, meal(m.id).revision))).single()
        assertEquals("Removed the photo.", summary(deleted))
        apply(manual(CoachManualEdit.Attach(m.id, listOf(shared), PhotoRole.unspecified, meal(m.id).revision)), turn = again)
        assertEquals("Check the meal's photos.", summary(deleted))
    }

    @Test fun weightAndWorkout() {
        val receipts = apply(CoachWrite.Weight(today, 70.0, "kg", null), CoachWrite.Workout("2026-10-23", WorkoutDraft(WorkoutKind.cardio, 45, emptyList())))
        assertEquals("Weight saved: **70 kg**. Workout saved: cardio, 45 minutes.", summary(receipts.first()))
    }

    @Test fun goalsUpdated() {
        val set = apply(manual(CoachManualEdit.Goals(today, listOf(CoachNutrientEdit("kcal", 2000.0)), null, false, null, null))).single()
        assertEquals("Your goals are updated.", summary(set))
    }

    @Test fun dayMarkedSkippedAndCounted() {
        val skipped = apply(manual(CoachManualEdit.Coverage("2026-10-23", DayCompleteness.untracked))).single()
        val counted = apply(manual(CoachManualEdit.Coverage("2026-10-22", DayCompleteness.complete))).single()
        assertEquals("Marked ${CoachReplyLines.shortDate("2026-10-23")} as skipped.", summary(skipped))
        assertEquals("Marked ${CoachReplyLines.shortDate("2026-10-22")} as counted.", summary(counted))
    }

    @Test fun deletedRecordsSayDeleted() {
        val logged = log(food("Synthetic apple"))
        apply(manual(CoachManualEdit.DeleteMeal(logged.mealID!!, 1)))
        assertEquals("This meal was deleted.", summary(logged))

        val m = meal(log(food("Synthetic toast"), food("Synthetic jam")).mealID!!)
        val corrected = apply(CoachWrite.Correction(m.id, m.items[1].copy(quantity = 2.0), m.revision)).single()
        val after = meal(m.id)
        apply(manual(CoachManualEdit.DeleteItem(m.id, m.items[1].id, after.revision)))
        assertEquals("This item was deleted.", summary(corrected))

        val weight = apply(CoachWrite.Weight(today, 70.0, "kg", null)).single()
        apply(CoachWrite.DeleteWeight(weight.weightID!!, 1))
        assertEquals("This weight was deleted.", summary(weight))

        val workout = apply(CoachWrite.Workout(today, WorkoutDraft(WorkoutKind.cardio, 30, emptyList()))).single()
        apply(CoachWrite.DeleteWorkout(workout.workoutID!!, 1))
        assertEquals("This workout was deleted.", summary(workout))
    }
}
