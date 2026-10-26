@file:UseSerializers(SwiftDate::class, SwiftUUID::class)
@file:Suppress("EnumEntryName") // entry names match the tombstone table suffixes

package com.yakov103.mivu.diary

import android.content.Context
import android.database.Cursor
import android.database.DatabaseUtils
import android.database.sqlite.SQLiteConstraintException
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteDatabaseLockedException
import android.database.sqlite.SQLiteDoneException
import android.os.ParcelFileDescriptor
import androidx.annotation.VisibleForTesting
import java.io.Closeable
import java.io.File
import java.io.InputStream
import java.security.MessageDigest
import java.time.Instant
import java.util.UUID
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.UseSerializers
import kotlinx.serialization.builtins.ListSerializer

// Port of the row layout in ios/Mivu/Diary/DiaryDatabase.swift (`write`/`rows`) and the transaction rule in
// DiaryDatabaseMutations.swift. Each record is one row of SwiftJson ordered by `ordinal`; photo bytes sit beside it.

/** The single `head` row: everything in a DiarySnapshot that is not a record list. */
@Serializable
data class Head(
    val revision: Long,
    val lineage: List<UUID>? = null,
    val profile: DiaryProfile,
    val activeDayID: UUID? = null,
    val previousDayConfirmedAt: Instant? = null,
    val activeConversationSegmentID: UUID? = null,
)

private val RECORD_TABLES = listOf(
    "day", "meal", "submission", "item", "photo", "weight", "goal", "workout", "coach_turn", "coach_photo",
    "tombstone_meal", "tombstone_weight", "tombstone_workout",
)
private val PARENTS = mapOf(
    "meal" to "day(id)", "submission" to "meal(id) ON DELETE CASCADE", "item" to "meal(id) ON DELETE CASCADE",
    "photo" to "meal(id) ON DELETE CASCADE", "weight" to "day(id)", "workout" to "day(id)",
    "coach_photo" to "coach_turn(id) ON DELETE CASCADE",
)
private const val MAX_REVISION = 10_000_000L
private const val MAX_COACH_TURNS = 10_000L // iOS appendCapture

/** One `coach_undo` row: [before] is null when undoing deletes the meal the change created. */
data class CoachUndo(val mealID: UUID, val afterRevision: Int, val afterState: String, val before: List<FoodItem>?, val undone: Boolean)

private class Row(val id: String, val parent: String?, val payload: ByteArray)

/**
 * One profile's diary. Keep a single instance per profile per process: transactions are serialized by this
 * instance's connection, and a second connection on the same file only sees [DiaryError.Busy].
 */
class DiaryDatabase private constructor(private val db: SQLiteDatabase, private val profileID: UUID, internal val file: File) :
    Closeable {

    enum class Tombstone { meal, weight, workout }

    companion object {
        fun open(context: Context, profileID: UUID): DiaryDatabase =
            open(File(context.filesDir, "profiles/${profileID.key}/diary.sqlite"), profileID)

        /** Opens (or creates) [profileID]'s diary at [file], e.g. a temporary folder that is moved into place later. */
        internal fun open(file: File, profileID: UUID): DiaryDatabase {
            file.parentFile!!.mkdirs()
            // DELETE journal, as iOS: a commit leaves the whole diary in this one file, so a device-transfer copy
            // never depends on an un-checkpointed -wal sidecar.
            val params = SQLiteDatabase.OpenParams.Builder()
                .addOpenFlags(SQLiteDatabase.CREATE_IF_NECESSARY)
                .setJournalMode("DELETE")
                .setSynchronousMode("FULL")
                .build()
            val db = SQLiteDatabase.openDatabase(file, params)
            try {
                db.setForeignKeyConstraintsEnabled(true)
                if (db.version == 0) {
                    db.beginTransactionNonExclusive()
                    try {
                        for (table in RECORD_TABLES) {
                            val parent = PARENTS[table]?.let { ", parent TEXT${if (table == "weight") "" else " NOT NULL"} REFERENCES $it" } ?: ""
                            val bytes = if (table.isPhotos) ", bytes BLOB NOT NULL" else ""
                            db.execSQL("CREATE TABLE $table (id TEXT PRIMARY KEY, ordinal INTEGER NOT NULL$parent, payload BLOB NOT NULL$bytes)")
                        }
                        db.execSQL("CREATE TABLE head (id INTEGER PRIMARY KEY CHECK(id = 1), payload BLOB NOT NULL)")
                        db.version = 1
                        db.setTransactionSuccessful()
                    } finally { db.endTransaction() }
                }
                if (db.version != 1) throw DiaryError.InvalidData("database version")
                // Outside the version gate, as iOS: existing diaries gain it too. Derived Coach state, never archived; a
                // replace (import/restore) deletes its turns and so drops every undo row on purpose.
                db.execSQL("CREATE TABLE IF NOT EXISTS coach_undo (operationKey TEXT PRIMARY KEY, turnID TEXT NOT NULL " +
                    "REFERENCES coach_turn(id) ON DELETE CASCADE, mealID TEXT NOT NULL, afterRevision INTEGER NOT NULL, " +
                    "afterState TEXT NOT NULL, beforePayload BLOB, undone INTEGER NOT NULL DEFAULT 0)")
                // Coach timeline pages seek by ordinal, so a 10,000-turn diary reads only the page's rows.
                db.execSQL("CREATE INDEX IF NOT EXISTS coach_turn_ordinal ON coach_turn(ordinal)")
                // iOS DiaryDatabaseMigration.swift:73-79: child and ordinal lookups read only their rows, so a day's or a
                // year's reads scale with what they return, not with the whole diary.
                for (table in listOf("meal", "submission", "item", "photo", "weight", "workout", "coach_photo")) {
                    db.execSQL("CREATE INDEX IF NOT EXISTS ${table}_parent_ordinal ON $table(parent, ordinal, id)")
                }
                for (table in listOf("day", "meal", "weight", "workout", "tombstone_meal", "tombstone_weight", "tombstone_workout")) {
                    db.execSQL("CREATE INDEX IF NOT EXISTS ${table}_ordinal ON $table(ordinal, id)")
                }
                // The payload JSON holds the date (iOS has a column); the expression matches the goal queries' text exactly.
                db.execSQL("CREATE INDEX IF NOT EXISTS goal_date ON goal(json_extract(CAST(payload AS TEXT), '$.effectiveLocalDate'))")
                // Derived Coach conversations for history and seek (CoachSegments.kt), rebuilt from coach_turn, never archived.
                db.execSQL("CREATE TABLE IF NOT EXISTS coach_segment (segmentID TEXT PRIMARY KEY, trackingDayID TEXT, " +
                    "displayLocalDate TEXT NOT NULL, displayTimeZoneID TEXT NOT NULL, firstTurnID TEXT NOT NULL, firstCapturedAt TEXT NOT NULL, " +
                    "firstOrdinal INTEGER NOT NULL, lastOrdinal INTEGER NOT NULL, preview TEXT NOT NULL)")
                db.execSQL("CREATE INDEX IF NOT EXISTS coach_segment_last ON coach_segment(lastOrdinal, segmentID)")
                db.execSQL("CREATE INDEX IF NOT EXISTS coach_segment_date_last ON coach_segment(displayLocalDate, lastOrdinal, segmentID)")
                val lagging = db.rawQuery("SELECT (SELECT MAX(ordinal) FROM coach_turn) IS NOT (SELECT MAX(lastOrdinal) FROM coach_segment)", null)
                    .use { it.moveToFirst() && it.getInt(0) == 1 }
                return DiaryDatabase(db, profileID, file).also { diary ->
                    // A failed rebuild only leaves history incomplete; the diary itself still opens.
                    if (lagging) runCatching { diary.immediate { diary.Tx(diary.head()).rebuildCoachSegments() } }
                        .onFailure { if (it is CancellationException) throw it }
                }
            } catch (e: Throwable) { db.close(); throw e }
        }

        /** A new, empty diary at revision 0 with a one-entry lineage, as iOS `DiaryStore.createProfile`. */
        fun create(context: Context, profile: DiaryProfile): DiaryDatabase = open(context, profile.id).also {
            try {
                it.replace(requireEmpty = true) {
                    DiarySnapshot(1, 0, profile, emptyList(), emptyList(), emptyList(), deletedMealIDs = emptyList(),
                        lineage = listOf(UUID.randomUUID()))
                }
            } catch (e: Throwable) { it.close(); throw e }
        }
    }

    /** One revisioned write. The revision and lineage advance at commit only if something was written. */
    inner class Tx internal constructor(head: Head) {
        internal var changed = false
        var head: Head = head
            set(value) { if (value != field) { field = value; changed = true } }

        // Validation sees the revision this transaction will commit, so receipts may carry it.
        private val pending get() = head.copy(revision = head.revision + 1)

        fun snapshot(): DiarySnapshot = readSnapshot(head)
        fun day(id: UUID): TrackingDay? = days(id).firstOrNull()
        fun meal(id: UUID): DiaryMeal? = meals(id).firstOrNull()
        fun coachTurn(id: UUID): CoachTurn? = turns(id).firstOrNull()
        /** The turn row alone: photo metadata and bytes are not read. */
        fun coachTurnWithoutPhotos(id: UUID): CoachTurn? = records("coach_turn", CoachTurn.serializer(), "id = ?", id).firstOrNull()?.second
        fun isLive(kind: Tombstone, id: UUID): Boolean = exists(kind.name, id)
        fun isTombstoned(kind: Tombstone, id: UUID): Boolean = exists("tombstone_${kind.name}", id)
        fun days(): List<TrackingDay> = this@DiaryDatabase.days()
        /**
         * One day's meals for list screens, as iOS `readModel`: photos carry their ID and metadata with empty `data`;
         * read the bytes one photo at a time with [photoBytes].
         */
        fun dayMeals(dayID: UUID): List<DiaryMeal> =
            meals("parent = ?", "parent IN (SELECT id FROM meal WHERE parent = ?)", dayID, photoData = null)
        /** One meal for a detail screen, with photo metadata only, as [dayMeals]. */
        fun mealWithoutPhotoBytes(id: UUID): DiaryMeal? = meals("id = ?", "parent = ?", id, photoData = null).firstOrNull()
        fun goals(): List<GoalRecord> = records("goal", GoalRecord.serializer()).map { it.second }
        fun dayWorkouts(dayID: UUID): List<WorkoutSession> = records("workout", WorkoutSession.serializer(), "parent = ?", dayID).map { it.second }
        fun dayWeight(dayID: UUID): WeightEntry? = records("weight", WeightEntry.serializer(), "parent = ?", dayID).firstOrNull()?.second
        fun coachTurnsWithoutPhotos(): List<CoachTurn> = this@DiaryDatabase.coachTurnsWithoutPhotos()
        /** At most [limit] rows of [table] matching [where], in [order]: the bounded reads Coach context uses. */
        internal fun <T> boundedRecords(table: String, serializer: KSerializer<T>, where: String?, args: List<String>, order: String, limit: Int): List<T> =
            records(table, serializer, where, args.toTypedArray(), order, limit).map { it.second }
        /** A raw read in this transaction; row queries must carry a LIMIT. */
        internal fun <T> query(sql: String, args: List<String>, body: (Cursor) -> T): T = db.rawQuery(sql, args.toTypedArray()).use(body)
        /** A raw write to derived tables only (they carry no revision). */
        internal fun exec(sql: String, args: List<Any?>) = db.execSQL(sql, args.toTypedArray())
        fun submissionParent(id: UUID): UUID? =
            records("submission", MealSubmission.serializer(), "id = ?", id).firstOrNull()?.first?.parent?.let(UUID::fromString)

        /**
         * iOS `saveUndo`: the meal's items before a Coach change (empty: the change created it, so undo deletes it), keyed by
         * the write's operation key. Only saved meals; the first snapshot for a key wins. Writes no revision.
         */
        fun saveUndo(key: String, turnID: UUID, mealID: UUID, before: List<FoodItem>) {
            val meal = mealWithoutPhotoBytes(mealID) ?: throw DiaryError.NotFound
            if ((meal.submissions.lastOrNull()?.state ?: SubmissionState.saved) != SubmissionState.saved) return // review keeps its own flow
            val payload = if (before.isEmpty()) null else SwiftJson.encodeToString(ListSerializer(FoodItem.serializer()), before).toByteArray()
            db.execSQL("INSERT OR IGNORE INTO coach_undo (operationKey, turnID, mealID, afterRevision, afterState, beforePayload) " +
                "VALUES (?, ?, ?, ?, ?, ?)", arrayOf(key, turnID.key, mealID.key, meal.revision.toLong(), undoState(meal), payload))
        }

        /** iOS `coachUndo`: the stored snapshot for [key], or null. */
        fun coachUndo(key: String): CoachUndo? = db.rawQuery(
            "SELECT mealID, afterRevision, afterState, beforePayload, undone FROM coach_undo WHERE operationKey = ?", arrayOf(key),
        ).use {
            if (!it.moveToFirst()) return null
            val mealID = runCatching { UUID.fromString(it.getString(0)) }.getOrElse { throw DiaryError.InvalidData("coach undo") }
            val before = if (it.isNull(3)) null else decode(it.getBlob(3), ListSerializer(FoodItem.serializer()))
            CoachUndo(mealID, it.getInt(1), it.getString(2), before, it.getLong(4) != 0L)
        }

        /** Marks [key]'s snapshot used; the caller's meal write commits it. */
        internal fun markUndone(key: String) = db.execSQL("UPDATE coach_undo SET undone = 1 WHERE operationKey = ?", arrayOf(key))

        /** iOS `undoState`: captures, photos and moves keep the revision, so the day, submissions and photos count too. */
        internal fun undoState(meal: DiaryMeal): String =
            "${meal.revision}/${meal.dayID.key}/" + meal.submissions.map { it.id.key }.sorted().joinToString(",") + "/" +
                meal.photos.map { it.id.key }.sorted().joinToString(",")

        /** Import-style rewrite: every record row and the head's non-revision fields come from [snapshot]. */
        internal fun write(snapshot: DiarySnapshot) {
            snapshot.validate()
            writeRows(snapshot)
            rebuildCoachSegments()
            head = head.copy(profile = snapshot.profile, activeDayID = snapshot.activeDayID,
                previousDayConfirmedAt = snapshot.previousDayConfirmedAt,
                activeConversationSegmentID = snapshot.activeConversationSegmentID)
            changed = true
        }

        fun putDay(day: TrackingDay) {
            // Manual acceptances name their day's date and zone: re-check the meals that target this day.
            val targeting = records("submission", MealSubmission.serializer())
                .filter { (_, sub) -> sub.manualAcceptance?.let { targetDay(it.target).first == day.id } == true }
                .mapNotNull { it.first.parent }.distinct().mapNotNull { meal(UUID.fromString(it)) }
            verify(pending, days = days().filter { it.id != day.id } + day, meals = targeting)
            put("day", day.id.key, day, TrackingDay.serializer())
            changed = true
        }

        /** Upserts the meal row and replaces its items, photos and submissions. */
        fun putMeal(meal: DiaryMeal) {
            alive(Tombstone.meal, meal.id)
            // Coach turns may resolve photo IDs through this meal: dropping one they use must not strand them.
            val kept = meal.photos.map { it.id }.toSet()
            val dropped = records("photo", MealPhoto.serializer(), "parent = ?", meal.id).map { it.second.id }.filter { it !in kept }
            val users = if (dropped.isEmpty()) emptyList() else coachTurnsWithoutPhotos().filter { t ->
                t.photoIDs.any { it in dropped } && (t.pendingMealID == meal.id || t.receipts.any { it.mealID == meal.id })
            }.mapNotNull { coachTurn(it.id) }
            val others = users.flatMap { t -> listOfNotNull(t.pendingMealID) + t.receipts.mapNotNull { it.mealID } }
                .toSet().minus(meal.id).mapNotNull { meal(it) }
            verify(pending, meals = listOf(meal) + others, turns = users)
            put("meal", meal.id.key, meal.copy(items = emptyList(), photos = emptyList(), submissions = emptyList()),
                DiaryMeal.serializer(), meal.dayID)
            for (table in listOf("submission", "item", "photo")) db.delete(table, "parent = ?", arrayOf(meal.id.key))
            putChildren(meal)
            changed = true
        }

        fun putWeight(weight: WeightEntry) {
            alive(Tombstone.weight, weight.id)
            verify(pending, weights = records("weight", WeightEntry.serializer()).map { it.second }.filter { it.id != weight.id } + weight)
            put("weight", weight.id.key, weight, WeightEntry.serializer(), weight.dayID)
            changed = true
        }

        fun putGoal(goal: GoalRecord) {
            verify(pending, goals = records("goal", GoalRecord.serializer()).map { it.second }.filter { it.id != goal.id } + goal)
            put("goal", goal.id.key, goal, GoalRecord.serializer())
            changed = true
        }

        fun putWorkout(workout: WorkoutSession) {
            alive(Tombstone.workout, workout.id)
            verify(pending, workouts = listOf(workout))
            put("workout", workout.id.key, workout, WorkoutSession.serializer(), workout.dayID)
            changed = true
        }

        /** Upserts the turn row and replaces its photos. Meals it points at are read for validation. */
        fun putCoachTurn(turn: CoachTurn) {
            val original = coachTurnWithoutPhotos(turn.id)
            if (original == null && DatabaseUtils.queryNumEntries(db, "coach_turn") >= MAX_COACH_TURNS) {
                throw DiaryError.InvalidData("coach turns")
            }
            // iOS `saveTurn`: an accepted capture's identity and context never change.
            if (original != null && (original.submissionManifest != turn.submissionManifest || original.capturedAt != turn.capturedAt ||
                    original.captureTimeZoneID != turn.captureTimeZoneID || original.activeDayID != turn.activeDayID ||
                    original.text != turn.text || original.captureSegmentID != turn.captureSegmentID)
            ) throw DiaryError.StaleRevision
            val mealIDs = (listOfNotNull(turn.pendingMealID) + turn.receipts.mapNotNull { it.mealID }).toSet()
            verify(pending, meals = mealIDs.mapNotNull { meal(it) }, turns = listOf(turn))
            put("coach_turn", turn.id.key, turn.copy(photos = emptyList()), CoachTurn.serializer())
            db.delete("coach_photo", "parent = ?", arrayOf(turn.id.key))
            putPhotos("coach_photo", turn.id, turn.photos)
            if (original == null) indexCoachSegment(turn)
            changed = true
        }

        /**
         * iOS `updateCoachTurn`: sets the turn's progress; a day choice only belongs to a clarification. Only the turn row is
         * rewritten: its photo rows and photo links are unchanged, so their checks (which need the bytes) still hold.
         */
        fun updateCoachTurn(
            turnID: UUID, state: CoachTurnState, assistantText: String?, question: CoachQuestion? = null,
            incomplete: Boolean? = null, needsDayChoice: Boolean = false, failureReason: String? = null,
        ) {
            val turn = (coachTurnWithoutPhotos(turnID) ?: throw DiaryError.NotFound).copy(state = state, assistantText = assistantText,
                question = question, incomplete = incomplete, failureReason = failureReason?.utf8Prefix(200),
                needsDayChoice = if (state == CoachTurnState.needsClarification && needsDayChoice) true else null)
            verify(pending, turns = listOf(turn.copy(photoIDs = emptyList())))
            put("coach_turn", turn.id.key, turn, CoachTurn.serializer())
            changed = true
        }

        /** Deletes the live record (a meal with its children), records its tombstone and repairs turns using a meal. */
        fun delete(kind: Tombstone, id: UUID) {
            val deleted = if (kind == Tombstone.meal) meal(id) else null
            db.delete(kind.name, "id = ?", arrayOf(id.key))
            if (!exists("tombstone_${kind.name}", id)) put("tombstone_${kind.name}", id.key, id, SwiftUUID)
            changed = true
            if (deleted != null) repairTurns(deleted)
        }

        /**
         * iOS `stripUnusedPhotoID`: [turn] keeps the photo ID only while it holds its own copy or another meal it links
         * (other than [mealID]) still holds the photo.
         */
        internal fun stripUnusedPhotoID(turn: CoachTurn, photoID: UUID, mealID: UUID): CoachTurn {
            if (photoID !in turn.photoIDs || turn.photos.any { it.id == photoID }) return turn
            val elsewhere = (listOfNotNull(turn.pendingMealID) + turn.receipts.mapNotNull { it.mealID })
                .filter { it != mealID }.toSet().any { id -> meal(id)?.photos?.any { it.id == photoID } == true }
            return if (elsewhere) turn else turn.copy(photoIDs = turn.photoIDs - photoID)
        }

        /**
         * iOS `deleteMeal`: each Coach turn using one of the meal's photos gets its own copy if it has surviving progress
         * (a logged weight or workout), otherwise the photo ID is stripped; pending turns for the meal need clarification.
         */
        private fun repairTurns(deleted: DiaryMeal) {
            val linked = coachTurnsWithoutPhotos().filter { it.pendingMealID == deleted.id || it.receipts.any { r -> r.mealID == deleted.id } }
            for (row in linked) {
                val original = coachTurn(row.id) ?: throw DiaryError.InvalidData("coach turn")
                var turn = original
                // shortcut: iOS also counts weights/workouts in record_source; Android has no record_source table yet, so only
                // receipts count. Add it with the Coach record-source port.
                val progress = original.receipts.any { r ->
                    r.weightID?.let { isLive(Tombstone.weight, it) } == true || r.workoutID?.let { isLive(Tombstone.workout, it) } == true
                }
                for (photo in deleted.photos) {
                    if (photo.id !in turn.photoIDs || turn.photos.any { it.id == photo.id }) continue // not a consumer of this copy
                    if (progress) { turn = turn.copy(photos = turn.photos + photo); continue }
                    turn = stripUnusedPhotoID(turn, photo.id, deleted.id)
                }
                if (turn.pendingMealID == deleted.id) turn = turn.copy(state = CoachTurnState.needsClarification)
                if (turn != original) putCoachTurn(turn)
            }
        }
    }

    /** Runs after every committed write (a changed transaction or a replace), outside the database transaction. */
    @Volatile var onCommit: (() -> Unit)? = null

    /** Test seam: how many complete diary reads ran; ordinary Coach paths keep it at zero. */
    @VisibleForTesting internal var snapshotReads = 0

    /** Test seam: runs after a transaction's row writes, before its head write and commit. */
    @VisibleForTesting internal var beforeCommit: (() -> Unit)? = null

    /** A consistent read through the transaction API; the body must not write. */
    fun <T> read(body: (Tx) -> T): T = immediate {
        val tx = Tx(head())
        body(tx).also { check(!tx.changed) { "write in read" } }
    }

    fun coachTurn(id: UUID): CoachTurn? = read { it.coachTurn(id) }

    /** Every Coach turn row in order, without loading photo bytes. */
    fun coachTurnsWithoutPhotos(): List<CoachTurn> = records("coach_turn", CoachTurn.serializer()).map { it.second }

    /** Port of iOS `nextPendingMealSubmission`: the first submission still waiting for analysis, as (mealID, submissionID). */
    fun nextPendingMealSubmission(): Pair<UUID, UUID>? = immediate {
        head() // owner check, as iOS domainRead
        db.rawQuery("SELECT parent, id FROM submission WHERE json_extract(CAST(payload AS TEXT), '$.state') IN " +
            "('captured','waitingForConnection','analyzing','needsRetry') ORDER BY ordinal, id LIMIT 1", null).use {
            if (!it.moveToFirst()) null
            else runCatching { UUID.fromString(it.getString(0)) to UUID.fromString(it.getString(1)) }
                .getOrElse { throw DiaryError.InvalidData("submission") }
        }
    }

    /**
     * iOS `nextPendingCoachTurn` (DiaryDatabaseCoachContext.swift:5): the oldest turn the worker may run; needsRetry waits for
     * the person. [capturedOnly] skips turns waiting on the network or a connection, so a stuck one cannot hold back newer ones.
     */
    fun nextPendingCoachTurn(includeWaitingForConnection: Boolean, capturedOnly: Boolean = false): UUID? = immediate {
        head() // owner check, as iOS domainRead
        val states = when {
            capturedOnly -> "'captured','analyzing'"
            includeWaitingForConnection -> "'captured','analyzing','waitingForNetwork','waitingForConnection'"
            else -> "'captured','analyzing','waitingForNetwork'"
        }
        db.rawQuery("SELECT id FROM coach_turn WHERE json_extract(CAST(payload AS TEXT), '$.state') IN ($states) " +
            "ORDER BY ordinal, id LIMIT 1", null).use {
            if (!it.moveToFirst()) null
            else runCatching { UUID.fromString(it.getString(0)) }.getOrElse { throw DiaryError.InvalidData("coach turn") }
        }
    }

    /** One meal photo's bytes, or null when the photo is gone. */
    fun photoBytes(mealID: UUID, photoID: UUID): ByteArray? = immediate {
        head() // owner check
        try { bytes("photo", "${mealID.key}/${photoID.key}") } catch (_: SQLiteDoneException) { null }
    }

    /**
     * One Coach photo's bytes, or null when it is gone: the turn's own copy, else the copy a meal the turn links now holds
     * (a logged photo moves to its meal).
     */
    fun coachPhotoBytes(turnID: UUID, photoID: UUID): ByteArray? = immediate {
        head() // owner check
        val turn = records("coach_turn", CoachTurn.serializer(), "id = ?", turnID).firstOrNull()?.second ?: return@immediate null
        if (photoID !in turn.photoIDs) return@immediate null
        val owners = listOf("coach_photo" to turnID) + (listOfNotNull(turn.pendingMealID) + turn.receipts.mapNotNull { it.mealID }).distinct().map { "photo" to it }
        owners.firstNotNullOfOrNull { (table, owner) ->
            try { bytes(table, "${owner.key}/${photoID.key}") } catch (_: SQLiteDoneException) { null }
        }
    }

    fun head(): Head = readHead() ?: throw DiaryError.InvalidData("no diary")

    fun snapshot(): DiarySnapshot = immediate { readSnapshot(head()) }

    /**
     * Throws StaleRevision unless the head is still at [expectedRevision] (null: whatever head the lock sees); a body that
     * writes nothing commits nothing.
     */
    fun <T> transaction(expectedRevision: Long?, body: (Tx) -> T): T {
        var committed = false
        return immediate {
            val original = head()
            if (expectedRevision != null && original.revision != expectedRevision) throw DiaryError.StaleRevision
            val tx = Tx(original)
            val value = body(tx)
            if (tx.changed) {
                beforeCommit?.invoke()
                if (tx.head.profile.id != profileID) throw DiaryError.WrongOwner
                val next = tx.head.copy(revision = original.revision + 1,
                    lineage = (original.lineage ?: emptyList()).takeLast(255) + UUID.randomUUID())
                verify(next)
                writeHead(next)
                committed = true
            }
            value
        }.also { if (committed) notifyCommit() }
    }

    /** Import: validates, then replaces every row and the head with [snapshot] as given (no revision bump). */
    fun replaceAll(snapshot: DiarySnapshot) = replace(requireEmpty = false) { snapshot }

    /**
     * Gives [body] the diary with SHA-256 digests as photo data and a reader of each digest's bytes, one photo at a
     * time. Each photo is read in its own short transaction, so writes wait for one photo rather than the whole encode;
     * a photo that is gone or changed since the snapshot throws [DiaryError.StaleRevision]. Photo sizes were checked
     * when they were written.
     */
    internal fun <T> withPhotoDigests(body: (DiarySnapshot, (ByteArray) -> ByteArray) -> T): T {
        val rows = HashMap<String, Pair<String, String>>()
        val snapshot = immediate { readSnapshot(head(), ::digest) }
        for (m in snapshot.meals) for (p in m.photos) rows[p.data.hex()] = "photo" to "${m.id.key}/${p.id.key}"
        for (t in snapshot.coachTurns) for (p in t.photos) rows[p.data.hex()] = "coach_photo" to "${t.id.key}/${p.id.key}"
        return body(snapshot) { digest ->
            val (table, id) = rows.getValue(digest.hex())
            val bytes = try { immediate { bytes(table, id) } } catch (_: SQLiteDoneException) { throw DiaryError.StaleRevision }
            if (!MessageDigest.getInstance("SHA-256").digest(bytes).contentEquals(digest)) throw DiaryError.StaleRevision
            bytes
        }
    }

    override fun close() = db.close()

    internal fun pragma(name: String): String = db.rawQuery("PRAGMA $name", null).use { it.moveToFirst(); it.getString(0) }

    /**
     * One write transaction from the current diary (null when there is none) to the snapshot [next] returns. With
     * [photoBytes], photo data are placeholders: the current diary's are SHA-256 digests (as [PhotoSpool]'s) and each
     * written photo's bytes come from [photoBytes], one at a time.
     */
    internal fun replace(
        requireEmpty: Boolean,
        photoBytes: ((ByteArray) -> ByteArray)? = null,
        next: (DiarySnapshot?) -> DiarySnapshot,
    ) = immediate {
        val current = readHead()
        if (requireEmpty && current != null) throw DiaryError.InvalidData("diary exists")
        val snapshot = next(current?.let { readSnapshot(it, if (photoBytes == null) ::bytes else ::digest) })
        if (snapshot.profile.id != profileID) throw DiaryError.WrongOwner
        validateArchiveManifests(snapshot)
        writeRows(snapshot, photoBytes ?: { it })
        val head = Head(snapshot.revision.toLong(), snapshot.lineage, snapshot.profile, snapshot.activeDayID,
            snapshot.previousDayConfirmedAt, snapshot.activeConversationSegmentID)
        writeHead(head)
        Tx(head).rebuildCoachSegments()
    }.also { notifyCommit() }

    // The write is durable by now; a failing listener must not make the caller think it was not.
    private fun notifyCommit() { onCommit?.let { runCatching(it) } }

    // beginTransactionNonExclusive issues `BEGIN IMMEDIATE` (SQLiteSession.TRANSACTION_MODE_IMMEDIATE).
    private fun <T> immediate(body: () -> T): T {
        check(!db.inTransaction()) { "nested diary transaction" }
        try {
            db.beginTransactionNonExclusive()
        } catch (_: SQLiteDatabaseLockedException) { throw DiaryError.Busy }
        try {
            try {
                return body().also { db.setTransactionSuccessful() }
            } finally { db.endTransaction() } // rolls back unless marked successful
        } catch (e: SQLiteConstraintException) { // duplicate child ID or missing parent day
            throw DiaryError.InvalidData(e.message ?: "constraint")
        }
    }

    /** Validates head metadata, every day, and the given records against them (the cross-record rules they reach). */
    private fun verify(
        head: Head,
        days: List<TrackingDay> = days(),
        meals: List<DiaryMeal> = emptyList(),
        weights: List<WeightEntry> = emptyList(),
        goals: List<GoalRecord> = emptyList(),
        workouts: List<WorkoutSession> = emptyList(),
        turns: List<CoachTurn> = emptyList(),
    ) {
        if (head.revision !in 0 until MAX_REVISION) throw DiaryError.InvalidData("revision")
        DiarySnapshot(1, head.revision.toInt(), head.profile, days, meals, weights, goals, workouts, turns, head.activeDayID,
            head.previousDayConfirmedAt, deletedMealIDs = emptyList(), lineage = head.lineage,
            activeConversationSegmentID = head.activeConversationSegmentID).validate()
    }

    private fun alive(kind: Tombstone, id: UUID) {
        if (exists("tombstone_${kind.name}", id)) throw DiaryError.InvalidData("tombstoned ${kind.name}")
    }

    private fun exists(table: String, id: UUID) =
        db.rawQuery("SELECT 1 FROM $table WHERE id = ?", arrayOf(id.key)).use { it.moveToFirst() }

    private fun readHead(): Head? = db.rawQuery("SELECT payload FROM head WHERE id = 1", null).use {
        if (!it.moveToFirst()) return null
        decode(it.getBlob(0), Head.serializer()).also { h ->
            if (h.profile.id != profileID) throw DiaryError.WrongOwner
            if (h.revision !in 0 until MAX_REVISION) throw DiaryError.InvalidData("revision")
        }
    }

    private fun writeHead(head: Head) =
        db.execSQL("INSERT OR REPLACE INTO head (id, payload) VALUES (1, ?)", arrayOf(SwiftJson.encodeToString(Head.serializer(), head).toByteArray()))

    /** Upsert of a non-photo row; without [ordinal] it keeps an existing row's place or appends after the last. */
    private fun <T> put(table: String, id: String, value: T, serializer: KSerializer<T>, parent: UUID? = null, ordinal: Int? = null) {
        val payload = SwiftJson.encodeToString(serializer, value).toByteArray()
        val place = ordinal?.toString()
            ?: "COALESCE((SELECT ordinal FROM $table WHERE id = ?1), (SELECT COALESCE(MAX(ordinal) + 1, 0) FROM $table))"
        if (table in PARENTS) {
            db.execSQL("INSERT INTO $table (id, ordinal, payload, parent) VALUES (?1, $place, ?2, ?3) " +
                "ON CONFLICT(id) DO UPDATE SET ordinal = excluded.ordinal, payload = excluded.payload, parent = excluded.parent",
                arrayOf(id, payload, parent?.key))
        } else {
            db.execSQL("INSERT INTO $table (id, ordinal, payload) VALUES (?1, $place, ?2) " +
                "ON CONFLICT(id) DO UPDATE SET ordinal = excluded.ordinal, payload = excluded.payload", arrayOf(id, payload))
        }
    }

    // Plain inserts: a child ID already used by another meal fails the primary key instead of moving rows.
    private fun putChildren(m: DiaryMeal, photoBytes: (ByteArray) -> ByteArray = { it }) {
        m.submissions.forEachIndexed { j, sub -> insert("submission", sub.id.key, j, SwiftJson.encodeToString(MealSubmission.serializer(), sub), m.id) }
        m.items.forEachIndexed { j, item -> insert("item", "${m.id.key}/${item.id.key}", j, SwiftJson.encodeToString(FoodItem.serializer(), item), m.id) }
        putPhotos("photo", m.id, m.photos, photoBytes)
    }

    private fun putPhotos(table: String, parent: UUID, photos: List<MealPhoto>, photoBytes: (ByteArray) -> ByteArray = { it }) =
        photos.forEachIndexed { i, p ->
            insert(table, "${parent.key}/${p.id.key}", i, SwiftJson.encodeToString(MealPhoto.serializer(), p.copy(data = ByteArray(0))),
                parent, photoBytes(p.data))
    }

    private fun insert(table: String, id: String, ordinal: Int, payload: String, parent: UUID?, bytes: ByteArray? = null) {
        val args = listOf<Any?>(id, ordinal.toLong(), payload.toByteArray(), parent?.key) + (if (bytes != null) listOf(bytes) else emptyList())
        db.execSQL("INSERT INTO $table (id, ordinal, payload, parent${if (bytes != null) ", bytes" else ""}) VALUES (?, ?, ?, ?${if (bytes != null) ", ?" else ""})",
            args.toTypedArray())
    }

    private fun writeRows(s: DiarySnapshot, photoBytes: (ByteArray) -> ByteArray = { it }) {
        for ((kind, ids) in listOf(Tombstone.meal to s.deletedMealIDs, Tombstone.weight to s.deletedWeightIDs, Tombstone.workout to s.deletedWorkoutIDs)) {
            val kept = ids.toSet()
            if (records("tombstone_${kind.name}", SwiftUUID).any { it.second !in kept }) throw DiaryError.InvalidData("dropped ${kind.name} tombstone")
        }
        for (table in RECORD_TABLES.reversed()) db.delete(table, null, null) // children first: foreign keys stay satisfied
        s.days.forEachIndexed { i, d -> put("day", d.id.key, d, TrackingDay.serializer(), ordinal = i) }
        s.meals.forEachIndexed { i, m ->
            put("meal", m.id.key, m.copy(items = emptyList(), photos = emptyList(), submissions = emptyList()), DiaryMeal.serializer(), m.dayID, ordinal = i)
            putChildren(m, photoBytes)
        }
        s.weights.forEachIndexed { i, w -> put("weight", w.id.key, w, WeightEntry.serializer(), w.dayID, ordinal = i) }
        s.goals.forEachIndexed { i, g -> put("goal", g.id.key, g, GoalRecord.serializer(), ordinal = i) }
        s.workouts.forEachIndexed { i, w -> put("workout", w.id.key, w, WorkoutSession.serializer(), w.dayID, ordinal = i) }
        s.coachTurns.forEachIndexed { i, t ->
            put("coach_turn", t.id.key, t.copy(photos = emptyList()), CoachTurn.serializer(), ordinal = i)
            putPhotos("coach_photo", t.id, t.photos, photoBytes)
        }
        for ((kind, ids) in listOf(Tombstone.meal to s.deletedMealIDs, Tombstone.weight to s.deletedWeightIDs, Tombstone.workout to s.deletedWorkoutIDs)) {
            ids.forEachIndexed { i, id -> put("tombstone_${kind.name}", id.key, id, SwiftUUID, ordinal = i) }
        }
    }

    // Photo rows are listed without `bytes`: a blob over the 2 MB CursorWindow cannot be read through a cursor.
    private fun rows(table: String, where: String?, args: Array<String>?, order: String, limit: Int?): List<Row> {
        val parent = if (table in PARENTS) "parent" else "NULL"
        val sql = "SELECT id, $parent, payload FROM $table${where?.let { " WHERE $it" } ?: ""} ORDER BY $order${limit?.let { " LIMIT $it" } ?: ""}"
        return db.rawQuery(sql, args).use {
            buildList { while (it.moveToNext()) add(Row(it.getString(0), it.getString(1), it.getBlob(2))) }
        }
    }

    private fun <T> blob(table: String, id: String, read: (InputStream) -> T): T = db.compileStatement("SELECT bytes FROM $table WHERE id = ?").use { st ->
        st.bindString(1, id)
        ParcelFileDescriptor.AutoCloseInputStream(st.simpleQueryForBlobFileDescriptor() ?: throw DiaryError.InvalidData(table)).use(read)
    }

    private fun bytes(table: String, id: String): ByteArray = blob(table, id) { it.readBytes() }

    /** SHA-256 of a photo's bytes, streamed rather than loaded. */
    private fun digest(table: String, id: String): ByteArray = blob(table, id) { input ->
        val sha = MessageDigest.getInstance("SHA-256")
        val buffer = ByteArray(64 * 1024)
        while (true) { val n = input.read(buffer); if (n < 0) break; sha.update(buffer, 0, n) }
        sha.digest()
    }

    // Decodes each row and checks it is stored under its own key, as iOS `decode` does.
    private fun <T> records(table: String, serializer: KSerializer<T>, where: String? = null, arg: UUID? = null): List<Pair<Row, T>> =
        records(table, serializer, where, arg?.let { arrayOf(it.key) }, "ordinal", null)

    private fun <T> records(table: String, serializer: KSerializer<T>, where: String?, args: Array<String>?, order: String, limit: Int?): List<Pair<Row, T>> =
        rows(table, where, args, order, limit).map { row ->
            val value = decode(row.payload, serializer)
            val id = when (value) {
                is UUID -> value
                is TrackingDay -> value.id; is DiaryMeal -> value.id; is MealSubmission -> value.id; is WeightEntry -> value.id
                is GoalRecord -> value.id; is WorkoutSession -> value.id; is CoachTurn -> value.id
                is FoodItem -> value.id; is MealPhoto -> value.id
                else -> error("unkeyed record")
            }
            val key = if (value is FoodItem || value is MealPhoto) "${row.parent}/${id.key}" else id.key
            if (key != row.id) throw DiaryError.InvalidData(table)
            row to value
        }

    /** Photos with [data] of each row as their data, or metadata only when it is null. */
    private fun photos(table: String, where: String?, arg: UUID?, data: ((String, String) -> ByteArray)?): Map<String?, List<MealPhoto>> =
        records(table, MealPhoto.serializer(), where, arg)
            .groupBy({ it.first.parent }, { (r, p) -> if (data != null) p.copy(data = data(table, r.id)) else p })

    private fun days(id: UUID? = null) = records("day", TrackingDay.serializer(), id?.let { "id = ?" }, id).map { it.second }

    private fun meals(id: UUID? = null, data: ((String, String) -> ByteArray)? = ::bytes): List<DiaryMeal> =
        meals(id?.let { "id = ?" }, id?.let { "parent = ?" }, id, data)

    /** Meals matching [where] with their children matching [childWhere], both bound to [arg]. */
    private fun meals(where: String?, childWhere: String?, arg: UUID?, photoData: ((String, String) -> ByteArray)? = ::bytes): List<DiaryMeal> {
        val submissions = records("submission", MealSubmission.serializer(), childWhere, arg).groupBy({ it.first.parent }, { it.second })
        val items = records("item", FoodItem.serializer(), childWhere, arg).groupBy({ it.first.parent }, { it.second })
        val photos = photos("photo", childWhere, arg, photoData)
        return records("meal", DiaryMeal.serializer(), where, arg).map { (_, m) ->
            m.copy(items = items[m.id.key].orEmpty(), photos = photos[m.id.key].orEmpty(), submissions = submissions[m.id.key].orEmpty())
        }
    }

    private fun turns(id: UUID? = null, data: ((String, String) -> ByteArray)? = ::bytes): List<CoachTurn> {
        val photos = photos("coach_photo", id?.let { "parent = ?" }, id, data)
        return records("coach_turn", CoachTurn.serializer(), id?.let { "id = ?" }, id).map { (_, t) -> t.copy(photos = photos[t.id.key].orEmpty()) }
    }

    private fun readSnapshot(head: Head, photoData: (String, String) -> ByteArray = ::bytes): DiarySnapshot {
        snapshotReads++
        fun ids(kind: Tombstone) = records("tombstone_${kind.name}", SwiftUUID).map { it.second }
        return DiarySnapshot(
            schemaVersion = 1,
            revision = head.revision.toInt(), // readHead and check bound it below MAX_REVISION
            profile = head.profile,
            days = days(),
            meals = meals(data = photoData),
            weights = records("weight", WeightEntry.serializer()).map { it.second },
            goals = records("goal", GoalRecord.serializer()).map { it.second },
            workouts = records("workout", WorkoutSession.serializer()).map { it.second },
            coachTurns = turns(data = photoData),
            activeDayID = head.activeDayID,
            previousDayConfirmedAt = head.previousDayConfirmedAt,
            deletedMealIDs = ids(Tombstone.meal),
            deletedWeightIDs = ids(Tombstone.weight),
            deletedWorkoutIDs = ids(Tombstone.workout),
            lineage = head.lineage,
            activeConversationSegmentID = head.activeConversationSegmentID,
        )
    }
}

private val String.isPhotos get() = this == "photo" || this == "coach_photo"

private val UUID.key get() = toString().uppercase()

private fun <T> decode(bytes: ByteArray, serializer: KSerializer<T>): T = try {
    SwiftJson.decodeFromString(serializer, bytes.decodeToString())
} catch (e: IllegalArgumentException) { // SerializationException included
    throw DiaryError.InvalidData(e.message ?: "row")
}
