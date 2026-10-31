@file:UseSerializers(SwiftUUID::class)

package com.yakov103.mivu.diary

import android.database.SQLException
import android.database.sqlite.SQLiteDatabase
import com.yakov103.mivu.coach.CoachManualEdit
import com.yakov103.mivu.coach.CoachWrite
import com.yakov103.mivu.coach.count
import java.time.Instant
import java.util.UUID
import kotlinx.serialization.Serializable
import kotlinx.serialization.UseSerializers

// Port of ios/Mivu/Diary/DiaryCoachDeletedUndo.swift: what a destructive Coach write removed is held briefly in the derived
// tables coach_undo_deleted and coach_undo_deleted_photo, so Undo can recreate it under new IDs. Tombstones stay, so the
// held copy is never a record: totals, exports and backups read the record tables only.

private const val WINDOW_MS = 600_000L // iOS coachDeletedUndoSeconds
private const val SPACE_MARGIN = 1_048_576L

/** What a delete removed. Photo bytes are not part of it: they sit in coach_undo_deleted_photo. */
@Serializable
internal sealed interface HeldDelete {
    @Serializable data class Meal(val meal: DiaryMeal) : HeldDelete
    @Serializable data class Photo(val mealID: UUID, val photo: MealPhoto) : HeldDelete
    @Serializable data class Weight(val weight: WeightEntry) : HeldDelete
    @Serializable data class Workout(val workout: WorkoutSession) : HeldDelete
}

/** A [record] and the bytes of the [photos] it names. */
internal class Held(val record: HeldDelete, val photos: List<MealPhoto> = emptyList())

internal sealed interface Restored {
    data class Meal(val id: UUID) : Restored
    data class Weight(val id: UUID) : Restored
    data class Workout(val id: UUID) : Restored
}

/** Erases copies past the window. */
internal fun SQLiteDatabase.purgeDeletedUndo(now: Instant) =
    execSQL("DELETE FROM coach_undo_deleted WHERE createdAt < ?", arrayOf(now.toEpochMilli() - WINDOW_MS))

/** With [beforeCapture], also erases the copies older than the newest turn, which a capture makes the turn before: Undo by voice lasts one more message. */
internal fun DiaryDatabase.Tx.purgeDeletedUndo(now: Instant, beforeCapture: Boolean) {
    exec("DELETE FROM coach_undo_deleted WHERE createdAt < ?", listOf(now.toEpochMilli() - WINDOW_MS))
    if (beforeCapture) exec("DELETE FROM coach_undo_deleted WHERE turnID IN (SELECT id FROM coach_turn WHERE ordinal < " +
        "(SELECT MAX(ordinal) FROM coach_turn))", emptyList())
}

/** Housekeeping in its own transaction, so a failure here (even a full phone) never reaches the write that follows. */
internal fun DiaryDatabase.purgeDeletedUndoApart(now: Instant, beforeCapture: Boolean = false) {
    try { transaction(null) { it.purgeDeletedUndo(now, beforeCapture) } } catch (_: SQLException) {} catch (_: DiaryError) {} // a constraint failure arrives as InvalidData
}

/** Nothing for writes that delete nothing; an undo of a logged meal deletes the whole meal. */
internal fun DiaryDatabase.Tx.deletedSnapshot(write: CoachWrite): Held? = when (write) {
    is CoachWrite.DeleteWeight -> Held(HeldDelete.Weight(weight(write.id)))
    is CoachWrite.DeleteWorkout -> Held(HeldDelete.Workout(workout(write.id)))
    is CoachWrite.Manual -> when (val e = write.edit) {
        is CoachManualEdit.DeleteMeal -> mealSnapshot(e.mealID)
        is CoachManualEdit.DeletePhoto -> mealRecord(e.mealID).photos.firstOrNull { it.id == e.photoID }
            ?.let { Held(HeldDelete.Photo(e.mealID, it.copy(data = ByteArray(0))), listOf(it)) }
        is CoachManualEdit.Undo -> coachUndo(e.operationKey)?.takeIf { it.before == null }?.let { mealSnapshot(it.mealID) }
        else -> null
    }
    else -> null
}

/** A meal without foods has nothing to bring back, so it gets no Undo. */
private fun DiaryDatabase.Tx.mealSnapshot(id: UUID): Held? {
    val meal = mealRecord(id)
    if (meal.items.isEmpty()) return null
    // Submissions and capture links are history, not restored.
    return Held(HeldDelete.Meal(meal.copy(submissions = emptyList(), photos = meal.photos.map { it.copy(data = ByteArray(0)) })), meal.photos)
}

/**
 * Keeps [held] for Undo; false when the phone has no room for it, so the delete goes ahead without Undo, as Coach deletes are
 * never blocked by Undo bookkeeping.
 */
internal fun DiaryDatabase.Tx.holdDelete(key: String, turnID: UUID, held: Held, at: Instant, freeBytes: Long): Boolean {
    if (held.photos.sumOf { it.data.size } * 2L + SPACE_MARGIN > freeBytes) return false
    exec("INSERT OR IGNORE INTO coach_undo_deleted (operationKey, turnID, payload, createdAt) VALUES (?, ?, ?, ?)",
        listOf(key, turnID.swift, SwiftJson.encodeToString(HeldDelete.serializer(), held.record).toByteArray(), at.toEpochMilli()))
    for (photo in held.photos) exec("INSERT INTO coach_undo_deleted_photo (id, parent, bytes) VALUES (?, ?, ?)", listOf("$key/${photo.id.swift}", key, photo.data))
    return true
}

internal fun DiaryDatabase.Tx.isHeldDelete(key: String) = count("SELECT COUNT(*) FROM coach_undo_deleted WHERE operationKey = ?", listOf(key)) == 1

/** The card offers Undo only until the next message or ten minutes; an undone copy still reads as undone. */
internal fun DiaryDatabase.Tx.deletedUndoState(key: String, now: Instant): CoachUndoState? = query(
    "SELECT d.undone, d.createdAt, EXISTS(SELECT 1 FROM coach_turn t JOIN coach_turn n ON n.ordinal > t.ordinal WHERE t.id = d.turnID) " +
        "FROM coach_undo_deleted d WHERE d.operationKey = ?", listOf(key),
) {
    when {
        !it.moveToFirst() -> null
        it.getLong(0) != 0L -> CoachUndoState.Undone
        now.toEpochMilli() - it.getLong(1) <= WINDOW_MS && it.getInt(2) == 0 -> CoachUndoState.Available
        else -> null
    }
}

/** Asking Pip may still undo from the very next message, after the card's button has gone. */
internal fun DiaryDatabase.Tx.deletedUndoUsable(key: String, now: Instant, turn: CoachTurn): Boolean = count(
    "SELECT COUNT(*) FROM coach_undo_deleted d JOIN coach_turn t ON t.id = d.turnID JOIN coach_turn c ON c.id = ? " +
        "WHERE d.operationKey = ? AND d.undone = 0 AND d.createdAt >= ? " +
        "AND NOT EXISTS (SELECT 1 FROM coach_turn m WHERE m.ordinal > t.ordinal AND m.ordinal < c.ordinal)",
    listOf(turn.id.swift, key, (now.toEpochMilli() - WINDOW_MS).toString()),
) == 1

/** Recreates the held record under new IDs, so tombstones never shrink; never overwrites what exists now. */
internal fun DiaryDatabase.Tx.undoDeleted(key: String): Restored {
    val (payload, undone) = query("SELECT payload, undone FROM coach_undo_deleted WHERE operationKey = ?", listOf(key)) {
        if (!it.moveToFirst()) throw DiaryError.NotFound
        it.getBlob(0) to it.getLong(1)
    }
    if (undone != 0L) throw DiaryError.StaleRevision
    val restored = when (val held = SwiftJson.decodeFromString(HeldDelete.serializer(), payload.decodeToString())) {
        is HeldDelete.Meal -> {
            val photos = held.meal.photos.map { it.copy(data = heldPhotoBytes(key, it.id)) }
            val meal = held.meal.copy(id = UUID.randomUUID(), photos = photos)
            saveMeal(meal)
            Restored.Meal(meal.id)
        }
        // Adding a photo overwrites nothing, so it goes back whatever the meal's revision; a gone meal is refused.
        is HeldDelete.Photo -> {
            val meal = mealRecord(held.mealID)
            // A new ID, so a paused turn that replays its delete_photo still finds the photo gone.
            saveMeal(meal.copy(photos = meal.photos + held.photo.copy(id = UUID.randomUUID(), data = heldPhotoBytes(key, held.photo.id))))
            Restored.Meal(meal.id)
        }
        is HeldDelete.Weight -> {
            if (held.weight.dayID?.let { weightOn(it) } != null) throw DiaryError.StaleRevision
            val weight = held.weight.copy(id = UUID.randomUUID())
            putWeight(weight)
            Restored.Weight(weight.id)
        }
        is HeldDelete.Workout -> {
            val workout = held.workout.copy(id = UUID.randomUUID())
            putWorkout(workout)
            Restored.Workout(workout.id)
        }
    }
    exec("UPDATE coach_undo_deleted SET undone = 1 WHERE operationKey = ?", listOf(key))
    return restored
}

/** When the earliest copy still open to Undo expires, or null; the Coach screen hides that Undo button then. */
fun DiaryDatabase.heldUndoExpiry(now: Instant = Instant.now()): Instant? = read { tx ->
    tx.query("SELECT MIN(createdAt) FROM coach_undo_deleted WHERE undone = 0 AND createdAt > ?", listOf((now.toEpochMilli() - WINDOW_MS).toString())) {
        if (it.moveToFirst() && !it.isNull(0)) Instant.ofEpochMilli(it.getLong(0) + WINDOW_MS) else null
    }
}
