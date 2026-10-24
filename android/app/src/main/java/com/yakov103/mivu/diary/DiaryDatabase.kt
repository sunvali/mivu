@file:UseSerializers(SwiftDate::class, SwiftUUID::class)

package com.yakov103.mivu.diary

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import java.io.Closeable
import java.io.File
import java.time.Instant
import java.util.UUID
import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.UseSerializers

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

private class Row(val id: String, val parent: String?, val payload: ByteArray, val bytes: ByteArray?)

class DiaryDatabase private constructor(private val db: SQLiteDatabase, private val profileID: UUID, internal val file: File) :
    Closeable {

    companion object {
        fun open(context: Context, profileID: UUID): DiaryDatabase {
            val file = File(context.filesDir, "profiles/${profileID.toString().uppercase()}/diary.sqlite")
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
                            val bytes = if (table == "photo" || table == "coach_photo") ", bytes BLOB NOT NULL" else ""
                            db.execSQL("CREATE TABLE $table (id TEXT PRIMARY KEY, ordinal INTEGER NOT NULL$parent, payload BLOB NOT NULL$bytes)")
                        }
                        db.execSQL("CREATE TABLE head (id INTEGER PRIMARY KEY CHECK(id = 1), payload BLOB NOT NULL)")
                        db.version = 1
                        db.setTransactionSuccessful()
                    } finally { db.endTransaction() }
                }
                if (db.version != 1) throw DiaryError.InvalidData("database version")
            } catch (e: Throwable) { db.close(); throw e }
            return DiaryDatabase(db, profileID, file)
        }
    }

    /** One revisioned write. Throws StaleRevision unless the head is still at [expectedRevision]. */
    inner class Tx internal constructor(var head: Head) {
        fun snapshot(): DiarySnapshot = readSnapshot(head)

        /** Replaces every record row with [snapshot]'s lists; the head changes only through [head]. */
        fun write(snapshot: DiarySnapshot) {
            snapshot.validate()
            writeRows(snapshot)
        }
    }

    fun head(): Head = readHead() ?: throw DiaryError.InvalidData("no diary")

    fun snapshot(): DiarySnapshot = immediate { readSnapshot(head()) }

    // beginTransactionNonExclusive issues `BEGIN IMMEDIATE` (SQLiteSession.TRANSACTION_MODE_IMMEDIATE).
    fun <T> transaction(expectedRevision: Long, body: (Tx) -> T): T = immediate {
        val original = head()
        if (original.revision != expectedRevision) throw DiaryError.StaleRevision
        val tx = Tx(original)
        val value = body(tx)
        val lineage = (original.lineage ?: emptyList()).takeLast(255) + UUID.randomUUID()
        writeHead(tx.head.copy(profile = tx.head.profile.takeIf { it.id == profileID } ?: throw DiaryError.WrongOwner,
            revision = original.revision + 1, lineage = lineage))
        value
    }

    /** Import: validates, then replaces every row and the head with [snapshot] as given (no revision bump). */
    fun replaceAll(snapshot: DiarySnapshot) {
        if (snapshot.profile.id != profileID) throw DiaryError.WrongOwner
        validateArchiveManifests(snapshot)
        immediate {
            writeRows(snapshot)
            writeHead(Head(snapshot.revision.toLong(), snapshot.lineage, snapshot.profile, snapshot.activeDayID,
                snapshot.previousDayConfirmedAt, snapshot.activeConversationSegmentID))
        }
    }

    override fun close() = db.close()

    internal fun pragma(name: String): String = db.rawQuery("PRAGMA $name", null).use { it.moveToFirst(); it.getString(0) }

    private fun <T> immediate(body: () -> T): T {
        db.beginTransactionNonExclusive()
        try {
            return body().also { db.setTransactionSuccessful() }
        } finally { db.endTransaction() } // rolls back unless marked successful
    }

    private fun readHead(): Head? = db.rawQuery("SELECT payload FROM head WHERE id = 1", null).use {
        if (!it.moveToFirst()) return null
        decode<Head>(it.getBlob(0)).also { h -> if (h.profile.id != profileID) throw DiaryError.WrongOwner }
    }

    private fun writeHead(head: Head) {
        db.insertWithOnConflict("head", null, ContentValues().apply { put("id", 1); put("payload", encode(head)) },
            SQLiteDatabase.CONFLICT_REPLACE)
    }

    private fun writeRows(s: DiarySnapshot) {
        db.execSQL("PRAGMA defer_foreign_keys = ON")
        for (table in RECORD_TABLES.reversed()) db.delete(table, null, null)
        fun <T> put(table: String, id: String, ordinal: Int, value: T, serializer: KSerializer<T>, parent: UUID? = null, bytes: ByteArray? = null) {
            db.insertOrThrow(table, null, ContentValues().apply {
                put("id", id); put("ordinal", ordinal); put("payload", SwiftJson.encodeToString(serializer, value).toByteArray())
                parent?.let { put("parent", it.key) }; bytes?.let { put("bytes", it) }
            })
        }
        fun photos(table: String, parent: UUID, photos: List<MealPhoto>) = photos.forEachIndexed { i, p ->
            put(table, "${parent.key}/${p.id.key}", i, p.copy(data = ByteArray(0)), MealPhoto.serializer(), parent, p.data)
        }
        s.days.forEachIndexed { i, d -> put("day", d.id.key, i, d, TrackingDay.serializer()) }
        s.meals.forEachIndexed { i, m ->
            put("meal", m.id.key, i, m.copy(items = emptyList(), photos = emptyList(), submissions = emptyList()), DiaryMeal.serializer(), m.dayID)
            m.submissions.forEachIndexed { j, sub -> put("submission", sub.id.key, j, sub, MealSubmission.serializer(), m.id) }
            m.items.forEachIndexed { j, item -> put("item", "${m.id.key}/${item.id.key}", j, item, FoodItem.serializer(), m.id) }
            photos("photo", m.id, m.photos)
        }
        s.weights.forEachIndexed { i, w -> put("weight", w.id.key, i, w, WeightEntry.serializer(), w.dayID) }
        s.goals.forEachIndexed { i, g -> put("goal", g.id.key, i, g, GoalRecord.serializer()) }
        s.workouts.forEachIndexed { i, w -> put("workout", w.id.key, i, w, WorkoutSession.serializer(), w.dayID) }
        s.coachTurns.forEachIndexed { i, t ->
            put("coach_turn", t.id.key, i, t.copy(photos = emptyList()), CoachTurn.serializer())
            photos("coach_photo", t.id, t.photos)
        }
        for ((table, ids) in listOf("tombstone_meal" to s.deletedMealIDs, "tombstone_weight" to s.deletedWeightIDs,
            "tombstone_workout" to s.deletedWorkoutIDs)) {
            ids.forEachIndexed { i, id -> put(table, id.key, i, id, SwiftUUID) }
        }
    }

    private fun rows(table: String): List<Row> {
        val parent = if (table in PARENTS) "parent" else "NULL"
        val bytes = if (table == "photo" || table == "coach_photo") "bytes" else "NULL"
        return db.rawQuery("SELECT id, $parent, payload, $bytes FROM $table ORDER BY ordinal", null).use {
            buildList { while (it.moveToNext()) add(Row(it.getString(0), it.getString(1), it.getBlob(2), it.getBlob(3))) }
        }
    }

    // Decodes each row and checks it is stored under its own key, as iOS `decode` does.
    private fun <T> records(table: String, serializer: KSerializer<T>, key: (Row, T) -> String): List<Pair<Row, T>> =
        rows(table).map { row -> (row to decode(row.payload, serializer)).also { (r, v) -> if (key(r, v) != r.id) throw DiaryError.InvalidData(table) } }

    private fun photos(table: String): Map<String?, List<MealPhoto>> =
        records(table, MealPhoto.serializer()) { r, p -> "${r.parent}/${p.id.key}" }
            .groupBy({ it.first.parent }, { (r, p) -> p.copy(data = r.bytes!!) })

    private fun readSnapshot(head: Head): DiarySnapshot {
        val submissions = records("submission", MealSubmission.serializer()) { _, v -> v.id.key }.groupBy({ it.first.parent }, { it.second })
        val items = records("item", FoodItem.serializer()) { r, v -> "${r.parent}/${v.id.key}" }.groupBy({ it.first.parent }, { it.second })
        val mealPhotos = photos("photo")
        val coachPhotos = photos("coach_photo")
        fun ids(table: String) = records(table, SwiftUUID) { _, v -> v.key }.map { it.second }
        return DiarySnapshot(
            schemaVersion = 1,
            revision = head.revision.toInt(),
            profile = head.profile,
            days = records("day", TrackingDay.serializer()) { _, v -> v.id.key }.map { it.second },
            meals = records("meal", DiaryMeal.serializer()) { _, v -> v.id.key }.map { (_, m) ->
                m.copy(items = items[m.id.key].orEmpty(), photos = mealPhotos[m.id.key].orEmpty(),
                    submissions = submissions[m.id.key].orEmpty())
            },
            weights = records("weight", WeightEntry.serializer()) { _, v -> v.id.key }.map { it.second },
            goals = records("goal", GoalRecord.serializer()) { _, v -> v.id.key }.map { it.second },
            workouts = records("workout", WorkoutSession.serializer()) { _, v -> v.id.key }.map { it.second },
            coachTurns = records("coach_turn", CoachTurn.serializer()) { _, v -> v.id.key }.map { (_, t) ->
                t.copy(photos = coachPhotos[t.id.key].orEmpty())
            },
            activeDayID = head.activeDayID,
            previousDayConfirmedAt = head.previousDayConfirmedAt,
            deletedMealIDs = ids("tombstone_meal"),
            deletedWeightIDs = ids("tombstone_weight"),
            deletedWorkoutIDs = ids("tombstone_workout"),
            lineage = head.lineage,
            activeConversationSegmentID = head.activeConversationSegmentID,
        )
    }
}

private val UUID.key get() = toString().uppercase()

private inline fun <reified T> encode(value: T) = SwiftJson.encodeToString(value).toByteArray()

private inline fun <reified T> decode(bytes: ByteArray): T = decode(bytes, kotlinx.serialization.serializer<T>())

private fun <T> decode(bytes: ByteArray, serializer: KSerializer<T>): T = try {
    SwiftJson.decodeFromString(serializer, bytes.decodeToString())
} catch (e: IllegalArgumentException) { // SerializationException included
    throw DiaryError.InvalidData(e.message ?: "row")
}
