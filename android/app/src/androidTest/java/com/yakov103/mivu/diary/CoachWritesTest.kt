package com.yakov103.mivu.diary

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.yakov103.mivu.coach.CoachContext
import com.yakov103.mivu.coach.CoachError
import com.yakov103.mivu.coach.CoachManualEdit
import com.yakov103.mivu.coach.CoachWrite
import com.yakov103.mivu.coach.CoachWriteMode
import com.yakov103.mivu.coach.commandFingerprint
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
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

/** Synthetic diaries only; ports the iOS Coach write, receipt and undo rules (DiaryDatabaseCoachMutations.swift). */
class CoachWritesTest {
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

    private fun food(name: String = "Synthetic apple", kcal: Double = 95.0) = FoodItem(UUID.randomUUID(), name, 1.0, "piece",
        NutritionValues(kcal = kcal), NutritionProvenance.estimate, "Synthetic", true, emptyMap())
    private fun photo() = MealPhoto(UUID.randomUUID(), byteArrayOf(1, 2, 3), at, PhotoRole.unspecified)

    private fun turn(text: String = "Synthetic lunch", photos: List<MealPhoto> = emptyList()): CoachTurn {
        val h = db.head()
        return db.captureCoachSubmission(CoachSubmissionPayload(UUID.randomUUID(), text, photos,
            CoachCaptureContext(at, "UTC", h.activeDayID, h.previousDayConfirmedAt, h.activeConversationSegmentID)), h.revision)
    }

    private fun apply(vararg writes: CoachWrite, turn: CoachTurn = turn()) = db.applyCoachWrites(turn.id, writes.toList(), at = at)
    private fun manual(edit: CoachManualEdit) = CoachWrite.Manual(edit)
    private fun meal(id: UUID) = db.read { it.meal(id) }!!
    private fun logged(vararg items: FoodItem = arrayOf(food())): DiaryMeal =
        meal(apply(CoachWrite.Food(today, items.toList(), null)).single().mealID!!)

    @Test fun logFoodCreatesMealAndReceipt() {
        val t = turn()
        val write = CoachWrite.Food(today, listOf(food()), null)
        val receipt = db.applyCoachWrites(t.id, listOf(write), at = at).single()
        assertEquals("${t.id.swift}/food/$today", receipt.operationKey)
        assertEquals(write.commandFingerprint(), receipt.commandFingerprint)
        assertEquals(db.head().activeDayID, receipt.dayID)
        assertEquals(db.head().revision.toInt(), receipt.committedRevision)
        val stored = meal(receipt.mealID!!)
        assertEquals(1, stored.revision)
        assertEquals(listOf("Synthetic apple"), stored.items.map { it.name })
        val result = SwiftJson.decodeFromString(CoachContext.Meal.serializer(), receipt.resultJSON)
        assertEquals(stored.id, result.id)
        assertEquals(SubmissionState.saved, result.state)
        assertEquals(listOf(receipt), db.coachTurn(t.id)!!.receipts)
    }

    @Test fun replaySameKeyReturnsPriorReceipt() {
        val t = turn()
        val write = CoachWrite.Food(today, listOf(food()), null)
        val first = db.applyCoachWrites(t.id, listOf(write), at = at)
        val head = db.head()
        assertEquals(first, db.applyCoachWrites(t.id, listOf(write), at = at))
        assertEquals(head, db.head())
        // Same key, different command: refused as iOS does.
        throws<CoachError.InvalidArguments> { db.applyCoachWrites(t.id, listOf(CoachWrite.Food(today, listOf(food("Synthetic pear")), null)), at = at) }
        assertEquals(head, db.head())
    }

    @Test fun batchFailsAtomically() {
        val t = turn()
        val head = db.head()
        val missing = CoachWrite.Correction(UUID.randomUUID(), food(), 1)
        throws<DiaryError.NotFound> { db.applyCoachWrites(t.id, listOf(CoachWrite.Food(today, listOf(food()), null), missing), at = at) }
        assertEquals(head, db.head())
        assertTrue(db.snapshot().meals.isEmpty())
        assertTrue(db.coachTurn(t.id)!!.receipts.isEmpty())
        // Duplicate targets are refused before anything runs.
        val write = CoachWrite.Food(today, listOf(food()), null)
        throws<CoachError.InvalidArguments> { db.applyCoachWrites(t.id, listOf(write, write), at = at) }
    }

    @Test fun replayOnlyRefusesNewWrites() {
        val t = turn()
        val write = CoachWrite.Food(today, listOf(food()), null)
        val first = db.applyCoachWrites(t.id, listOf(write), at = at)
        val head = db.head()
        val added = manual(CoachManualEdit.Coverage("2026-10-01", DayCompleteness.untracked))
        throws<CoachError.InvalidArguments> { db.applyCoachWrites(t.id, listOf(write, added), CoachWriteMode.replayOnly, at) }
        throws<CoachError.InvalidArguments> { db.validateCoachWrites(t.id, listOf(added), CoachWriteMode.replayOnly, at) }
        assertEquals(head, db.head())
        assertEquals(first, db.applyCoachWrites(t.id, listOf(write), CoachWriteMode.replayOnly, at))
    }

    @Test fun pendingMealFoodKeepsOnePhotoCopy() {
        val p = photo()
        val h = db.head()
        val capture = db.captureProjection("Synthetic plate", listOf(p), false, h.activeDayID!!, at, expectedRevision = h.revision)
        val sub = capture.submissions.single()
        val pending = CoachTurn(sub.id, at, "Synthetic plate", listOf(p), CoachTurnState.captured, null, emptyList(), "UTC", h.activeDayID,
            listOf(p.id), pendingMealID = capture.id, pendingMealRevision = 0)
        db.replaceAll(db.snapshot().let { it.copy(coachTurns = it.coachTurns + pending) })
        val receipt = db.applyCoachWrites(pending.id, listOf(CoachWrite.Food(today, listOf(food()), null)), at = at).single()
        val saved = meal(capture.id)
        assertEquals(capture.id, receipt.mealID)
        assertEquals(1, saved.revision)
        assertEquals(listOf(p.id), saved.photos.map { it.id })
        assertEquals(SubmissionState.saved, saved.submissions.single().state)
        val stored = db.coachTurn(pending.id)!!
        assertTrue(stored.photos.isEmpty())
        assertEquals(1, stored.pendingMealRevision)
    }

    @Test fun receiptCapIsSixteen() {
        val t = turn()
        val writes = (1..17).map { manual(CoachManualEdit.Coverage("2026-09-%02d".format(it), DayCompleteness.untracked)) }
        throws<CoachError.LimitExceeded> { db.applyCoachWrites(t.id, writes, at = at) }
        assertEquals(16, db.applyCoachWrites(t.id, writes.take(16), at = at).size)
    }

    @Test fun correctItemQuantity() {
        val original = logged()
        val item = original.items.single()
        val receipt = apply(CoachWrite.Correction(original.id, item.copy(quantity = 2.0), original.revision)).single()
        val stored = meal(original.id)
        assertEquals(2, stored.revision)
        assertEquals(190.0, stored.items.single().nutrition.kcal!!, 1e-9)
        assertEquals(item.id, receipt.itemID)
        assertTrue(receipt.operationKey.endsWith("/correct/${original.id.swift}/${item.id.swift}"))
        assertTrue("\"targetLocalDate\":\"$today\"" in receipt.resultJSON)
    }

    @Test fun undoRestoresPriorState() {
        val original = logged()
        val receipt = apply(CoachWrite.Correction(original.id, original.items.single().copy(quantity = 3.0), original.revision)).single()
        db.undoCoachChange(receipt.operationKey)
        assertEquals(original.items, meal(original.id).items)
        assertTrue(db.read { it.coachUndo(receipt.operationKey) }!!.undone)
        throws<DiaryError.StaleRevision> { db.undoCoachChange(receipt.operationKey) }
        // An undone log_food removes the meal, through the undo_change tool too.
        val t = turn()
        val logReceipt = db.applyCoachWrites(t.id, listOf(CoachWrite.Food(today, listOf(food("Synthetic pear")), null)), at = at).single()
        val undo = apply(manual(CoachManualEdit.Undo(logReceipt.operationKey))).single()
        assertNull(db.read { it.meal(logReceipt.mealID!!) })
        assertTrue("\"deleted\":true" in undo.resultJSON)
    }

    @Test fun undoRefusedAfterLaterEdit() {
        val original = logged()
        val item = original.items.single()
        val first = apply(CoachWrite.Correction(original.id, item.copy(quantity = 2.0), original.revision)).single()
        val edited = meal(original.id)
        apply(CoachWrite.Correction(original.id, edited.items.single().copy(quantity = 4.0), edited.revision))
        val t = turn()
        val head = db.head()
        throws<DiaryError.StaleRevision> { db.undoCoachChange(first.operationKey) }
        throws<DiaryError.StaleRevision> { apply(manual(CoachManualEdit.Undo(first.operationKey)), turn = t) }
        assertEquals(head, db.head())
    }

    @Test fun receiptResultJsonValidatesInArchive() {
        val original = logged()
        apply(CoachWrite.Correction(original.id, original.items.single().copy(quantity = 2.0), original.revision),
            manual(CoachManualEdit.Coverage("2026-10-01", DayCompleteness.untracked)), manual(CoachManualEdit.Open(CoachDestination.backup)))
        val snapshot = db.snapshot()
        snapshot.coachTurns.flatMap { it.receipts }.forEach { assertTrue(strictJsonContainer(it.resultJSON)) }
        val bytes = ByteArrayOutputStream().also { DiaryArchive.encode(snapshot, it) }.toByteArray()
        assertEquals(snapshot, DiaryArchive.decode(ByteArrayInputStream(bytes), profile.id))
    }

    @Test fun editItemAndAppendFood() {
        val original = logged()
        val item = original.items.single()
        val edited = item.copy(nutrition = NutritionValues(kcal = 120.0))
        apply(manual(CoachManualEdit.Item(original.id, edited, original.revision, null, setOf("kcal"), item)))
        assertEquals(120.0, meal(original.id).items.single().nutrition.kcal!!, 1e-9)
        val appended = apply(manual(CoachManualEdit.Append(original.id, listOf(food("Synthetic tea", 5.0)), 2))).single()
        assertEquals(listOf("Synthetic apple", "Synthetic tea"), meal(original.id).items.map { it.name })
        assertTrue(db.read { it.coachUndo(appended.operationKey) } != null)
    }

    @Test fun acceptReview() {
        val t = turn()
        val receipt = db.applyCoachWrites(t.id, listOf(CoachWrite.Food(today, listOf(food()), null, reviewFirst = true)), at = at).single()
        val pending = meal(receipt.mealID!!)
        assertEquals(0, pending.revision)
        assertEquals(SubmissionState.awaitingReview, pending.submissions.single().state)
        assertNull(db.read { it.coachUndo(receipt.operationKey) }) // review keeps its own flow
        apply(manual(CoachManualEdit.Accept(pending.id, t.id, 0)))
        assertEquals(1, meal(pending.id).revision)
    }

    @Test fun moveMealAndSetCoverage() {
        val original = logged()
        val receipt = apply(manual(CoachManualEdit.Move(original.id, "2026-10-23", original.revision, original.dayID))).single()
        val moved = meal(original.id)
        assertEquals(receipt.dayID, moved.dayID)
        assertEquals("2026-10-23", db.read { it.day(moved.dayID) }!!.localDate)
        apply(manual(CoachManualEdit.Coverage("2026-10-23", DayCompleteness.untracked)))
        assertEquals(DayCompleteness.untracked, db.read { it.day(moved.dayID) }!!.completeness)
    }

    @Test fun deleteMealAndReplay() {
        val original = logged()
        val t = turn()
        val write = manual(CoachManualEdit.DeleteMeal(original.id, original.revision))
        val receipt = db.applyCoachWrites(t.id, listOf(write), at = at)
        assertNull(db.read { it.meal(original.id) })
        assertTrue(db.read { it.isTombstoned(DiaryDatabase.Tombstone.meal, original.id) })
        assertEquals(receipt, db.applyCoachWrites(t.id, listOf(write), at = at))
    }

    @Test fun deleteItemAndScaleMeal() {
        val original = logged(food(), food("Synthetic bread", 105.0))
        apply(manual(CoachManualEdit.DeleteItem(original.id, original.items[1].id, original.revision)))
        assertEquals(listOf("Synthetic apple"), meal(original.id).items.map { it.name })
        apply(manual(CoachManualEdit.ScaleMeal(original.id, 190.0, 2)))
        assertEquals(2.0, meal(original.id).items.single().quantity, 1e-9)
        throws<DiaryError.InvalidData> { apply(manual(CoachManualEdit.DeleteItem(original.id, original.items[0].id, 3))) }
    }

    @Test fun attachAndDeletePhotos() {
        val withPhoto = turn(photos = listOf(photo()))
        val logged = db.applyCoachWrites(withPhoto.id, listOf(CoachWrite.Food(today, listOf(food()), null)), at = at).single()
        val photoID = withPhoto.photoIDs.single()
        assertEquals(listOf(photoID), meal(logged.mealID!!).photos.map { it.id })
        assertTrue(db.coachTurn(withPhoto.id)!!.photos.isEmpty()) // the copy moved into the meal
        val other = logged(food("Synthetic soup"))
        val second = turn(photos = listOf(photo()))
        val secondPhoto = second.photoIDs.single()
        db.applyCoachWrites(second.id, listOf(manual(CoachManualEdit.Attach(other.id, listOf(secondPhoto), PhotoRole.before, other.revision))), at = at)
        assertEquals(PhotoRole.before, meal(other.id).photos.single().role)
        assertTrue(meal(other.id).photos.single().data.contentEquals(byteArrayOf(1, 2, 3)))
        apply(manual(CoachManualEdit.DeletePhoto(other.id, secondPhoto, other.revision)))
        assertTrue(meal(other.id).photos.isEmpty())
        assertTrue(secondPhoto !in db.coachTurn(second.id)!!.photoIDs)
    }

    @Test fun retryMealRequeuesPausedTurn() {
        val paused = turn()
        val receipt = db.applyCoachWrites(paused.id, listOf(CoachWrite.Food(today, listOf(food()), null)), at = at).single()
        db.transaction(null) { it.failCoachTurn(paused.id, CoachTurnState.needsRetry) }
        val queued = apply(manual(CoachManualEdit.Retry(receipt.mealID!!, 1))).single()
        assertEquals(CoachTurnState.captured, db.coachTurn(paused.id)!!.state)
        assertTrue("\"turnID\":\"${paused.id.swift}\"" in queued.resultJSON)
    }

    @Test fun startDayAndOpenSettings() {
        val t = turn()
        val receipt = apply(manual(CoachManualEdit.StartDay(db.head().revision.toInt())), turn = t).single()
        assertEquals(db.head().activeDayID, receipt.dayID)
        val open = apply(manual(CoachManualEdit.Open(CoachDestination.connection))).single()
        assertEquals(CoachDestination.connection, open.destination)
        assertEquals("{\"completed\":false,\"destination\":\"connection\"}", open.resultJSON)
    }
}
