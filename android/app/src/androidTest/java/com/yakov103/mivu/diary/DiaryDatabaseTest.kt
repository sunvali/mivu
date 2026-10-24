package com.yakov103.mivu.diary

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteDatabaseLockedException
import androidx.test.core.app.ApplicationProvider
import com.yakov103.mivu.R
import java.io.File
import java.util.UUID
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test
import org.xmlpull.v1.XmlPullParser

class DiaryDatabaseTest {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val fixture = DiaryArchive.decode(javaClass.classLoader!!.getResourceAsStream("archive/ios-v4-full.json"))
    private val profileID = fixture.profile.id
    private lateinit var db: DiaryDatabase

    @Before fun open() {
        File(context.filesDir, "profiles").deleteRecursively()
        db = DiaryDatabase.open(context, profileID)
        db.replaceAll(fixture)
    }

    @After fun close() {
        db.close()
        File(context.filesDir, "profiles").deleteRecursively()
    }

    private inline fun <reified E : Throwable> throws(block: () -> Unit) {
        try { block(); fail("expected ${E::class.simpleName}") } catch (e: Throwable) { if (e !is E) throw e }
    }

    /** The body fails with [E] and the store is left exactly as the fixture. */
    private inline fun <reified E : Throwable> rejected(noinline body: (DiaryDatabase.Tx) -> Unit) {
        val before = db.head()
        throws<E> { db.transaction(before.revision, body) }
        assertEquals(before, db.head())
        assertEquals(fixture, db.snapshot())
    }

    // Same journal mode as the store: default params may switch the file to WAL.
    private fun otherConnection() =
        SQLiteDatabase.openDatabase(db.file, SQLiteDatabase.OpenParams.Builder().setJournalMode("DELETE").build())

    private fun weight() = WeightEntry(id = UUID.randomUUID(), measuredAt = fixture.weights[0].measuredAt, value = 70.0, unit = "kg")

    @Test fun replaceAllThenSnapshotRoundTripsFixture() {
        assertEquals(fixture, db.snapshot())
        db.close()
        db = DiaryDatabase.open(context, profileID)
        assertEquals(fixture, db.snapshot())
        assertEquals(fixture.revision.toLong(), db.head().revision)
        assertEquals(fixture.lineage, db.head().lineage)
    }

    @Test fun transactionBumpsRevisionAndLineage() {
        val before = db.head()
        val added = weight()
        val result = db.transaction(before.revision) { tx ->
            tx.write(tx.snapshot().let { it.copy(weights = it.weights + added) })
            "done"
        }
        assertEquals("done", result)
        val after = db.head()
        assertEquals(before.revision + 1, after.revision)
        assertEquals(before.lineage!! + after.lineage!!.last(), after.lineage)
        assertTrue(after.lineage.last() !in before.lineage)
        assertEquals(added, db.snapshot().weights.last())
        assertEquals(after.revision.toInt(), db.snapshot().revision)
    }

    @Test fun lineageKeepsTheLast255PlusTheNewEntry() {
        val long = List(256) { UUID.randomUUID() }
        db.replaceAll(fixture.copy(lineage = long))
        db.transaction(db.head().revision) { it.putWeight(weight()) }
        val lineage = db.head().lineage!!
        assertEquals(256, lineage.size)
        assertEquals(long.drop(1), lineage.dropLast(1))
    }

    @Test fun staleExpectedRevisionThrowsAndChangesNothing() {
        val before = db.head()
        try {
            db.transaction(before.revision - 1) { tx -> tx.write(fixture.copy(weights = emptyList())) }
            fail("expected StaleRevision")
        } catch (_: DiaryError.StaleRevision) {}
        assertEquals(before, db.head())
        assertEquals(fixture, db.snapshot())
    }

    @Test fun bodyThrowRollsBack() {
        val before = db.head()
        try {
            db.transaction(before.revision) { tx ->
                tx.write(fixture.copy(meals = emptyList(), coachTurns = emptyList()))
                tx.head = tx.head.copy(activeDayID = null)
                error("boom")
            }
            fail("expected throw")
        } catch (e: IllegalStateException) { assertEquals("boom", e.message) }
        assertEquals(before, db.head())
        assertEquals(fixture, db.snapshot())
    }

    @Test fun transactionTakesTheWriteLockAtBegin() {
        val other = otherConnection()
        try {
            db.transaction(db.head().revision) {
                // Nothing written yet: only BEGIN IMMEDIATE holds RESERVED here; DEFERRED would hold just SHARED.
                try {
                    other.beginTransactionNonExclusive() // RESERVED only; execSQL("BEGIN …") would be EXCLUSIVE
                    other.endTransaction()
                    fail("second writer was not blocked")
                } catch (_: SQLiteDatabaseLockedException) {}
            }
        } finally { other.close() }
    }

    @Test fun wrongProfileIsRejected() {
        try {
            db.replaceAll(fixture.copy(profile = fixture.profile.copy(id = UUID.randomUUID())))
            fail("expected WrongOwner")
        } catch (_: DiaryError.WrongOwner) {}
        assertEquals(fixture, db.snapshot())
    }

    @Test fun largePhotosRoundTripAfterReopen() {
        val big = ByteArray(10_000_000) { (it * 31).toByte() }
        val mid = ByteArray(5_000_000) { (it * 7).toByte() }
        val meal = fixture.meals[0].let { m -> m.copy(photos = listOf(m.photos[0].copy(data = big)) + m.photos.drop(1)) }
        val turn = fixture.coachTurns[0].let { t -> t.copy(photos = listOf(t.photos[0].copy(data = mid))) }
        val large = fixture.copy(meals = listOf(meal) + fixture.meals.drop(1), coachTurns = listOf(turn) + fixture.coachTurns.drop(1))
        db.replaceAll(large)
        db.close()
        db = DiaryDatabase.open(context, profileID)
        assertEquals(large, db.snapshot())
    }

    @Test fun putMealKeepsOrdinalAndReplacesChildren() {
        val meal = fixture.meals[1].let { m -> m.copy(items = listOf(m.items[0].copy(name = "Changed")), revision = m.revision + 1) }
        db.transaction(db.head().revision) { tx ->
            tx.putMeal(meal)
            assertEquals(meal, tx.meal(meal.id))
        }
        assertEquals(fixture.meals.toMutableList().also { it[1] = meal }, db.snapshot().meals)
        assertEquals(fixture.revision + 1, db.snapshot().revision)
    }

    @Test fun putCoachTurnAppendsTurnWithPhotos() {
        val photo = MealPhoto(UUID.randomUUID(), ByteArray(3_000_000) { it.toByte() }, fixture.coachTurns[0].capturedAt, PhotoRole.unspecified)
        val turn = fixture.coachTurns[1].copy(id = UUID.randomUUID(), photos = listOf(photo), photoIDs = listOf(photo.id),
            receipts = emptyList(), submissionManifest = null)
        db.transaction(db.head().revision) { it.putCoachTurn(turn) }
        db.transaction(db.head().revision) { tx -> assertEquals(turn, tx.coachTurn(turn.id)); assertEquals(null, tx.coachTurn(UUID.randomUUID())) }
        assertEquals(fixture.coachTurns + turn, db.snapshot().coachTurns)
    }

    @Test fun putRecordsUpsertAndValidate() {
        val day = fixture.days[0].copy(completeness = DayCompleteness.partial)
        val goal = fixture.goals[0].copy(revision = fixture.goals[0].revision + 1)
        val workout = fixture.workouts[0].copy(durationMinutes = 42, revision = fixture.workouts[0].revision + 1)
        val w = weight()
        db.transaction(db.head().revision) { tx ->
            tx.putDay(day); tx.putGoal(goal); tx.putWorkout(workout); tx.putWeight(w)
            assertEquals(day, tx.day(day.id))
        }
        val s = db.snapshot()
        assertEquals(listOf(day) + fixture.days.drop(1), s.days)
        assertEquals(listOf(goal), s.goals)
        assertEquals(listOf(workout) + fixture.workouts.drop(1), s.workouts)
        assertEquals(fixture.weights + w, s.weights)
        db.replaceAll(fixture)
        rejected<DiaryError.InvalidData> { it.putMeal(fixture.meals[1].copy(dayID = UUID.randomUUID())) }
        rejected<DiaryError.InvalidData> { it.putWorkout(fixture.workouts[0].copy(durationMinutes = 0)) }
        rejected<DiaryError.InvalidData> { it.putGoal(goal.copy(id = UUID.randomUUID())) } // duplicate effective date
    }

    @Test fun deleteMealWritesTombstoneAndBlocksReinsert() {
        val meal = fixture.meals[1]
        db.transaction(db.head().revision) { it.delete(DiaryDatabase.Tombstone.meal, meal.id) }
        val s = db.snapshot()
        assertEquals(fixture.meals - meal, s.meals)
        assertEquals(fixture.deletedMealIDs + meal.id, s.deletedMealIDs)
        val before = db.head()
        throws<DiaryError.InvalidData> { db.transaction(before.revision) { it.putMeal(meal) } }
        assertEquals(before, db.head())
        assertEquals(s, db.snapshot())
    }

    @Test fun tombstonesCannotBeDroppedOrReused() {
        rejected<DiaryError.InvalidData> { it.write(fixture.copy(deletedMealIDs = emptyList())) }
        rejected<DiaryError.InvalidData> { it.putWeight(fixture.weights[0].copy(id = fixture.deletedWeightIDs[0])) }
        rejected<DiaryError.InvalidData> { it.putWorkout(fixture.workouts[0].copy(id = fixture.deletedWorkoutIDs[0])) }
        throws<DiaryError.InvalidData> { db.replaceAll(fixture.copy(deletedWorkoutIDs = emptyList())) }
        assertEquals(fixture, db.snapshot())
    }

    @Test fun writeTakesHeadFromSnapshotAndHeadIsValidated() {
        val day = fixture.days.last().id
        db.transaction(db.head().revision) { it.write(fixture.copy(activeDayID = day, previousDayConfirmedAt = null)) }
        assertEquals(day, db.head().activeDayID)
        assertEquals(null, db.head().previousDayConfirmedAt)
        db.replaceAll(fixture)
        rejected<DiaryError.InvalidData> { it.head = it.head.copy(activeDayID = UUID.randomUUID()) }
        rejected<DiaryError.InvalidData> { it.head = it.head.copy(profile = it.head.profile.copy(name = " ")) }
        rejected<DiaryError.WrongOwner> { it.head = it.head.copy(profile = it.head.profile.copy(id = UUID.randomUUID())) }
    }

    @Test fun unchangedBodyKeepsRevisionAndLineage() {
        val before = db.head()
        assertEquals(7, db.transaction(before.revision) { it.snapshot(); 7 })
        assertEquals(before, db.head())
    }

    @Test fun nestedTransactionThrows() {
        rejected<IllegalStateException> { db.transaction(db.head().revision) {} }
    }

    @Test fun busyWhenAnotherConnectionHoldsTheWriteLock() {
        val other = otherConnection()
        try {
            other.beginTransactionNonExclusive()
            throws<DiaryError.Busy> { db.transaction(db.head().revision) { it.putWeight(weight()) } }
            other.endTransaction()
        } finally { other.close() }
        assertEquals(fixture, db.snapshot())
    }

    @Test fun revisionStaysBelowTenMillion() {
        db.replaceAll(fixture.copy(revision = 9_999_999))
        throws<DiaryError.InvalidData> { db.transaction(9_999_999) { it.putWeight(weight()) } }
        assertEquals(9_999_999L, db.head().revision)
    }

    @Test fun createMakesAnEmptyValidDiaryOnce() {
        val profile = fixture.profile.copy(id = UUID.randomUUID())
        DiaryDatabase.create(context, profile).use { created ->
            val head = created.head()
            assertEquals(0L, head.revision)
            assertEquals(1, head.lineage!!.size)
            assertEquals(DiarySnapshot(1, 0, profile, emptyList(), emptyList(), emptyList(), deletedMealIDs = emptyList(),
                lineage = head.lineage), created.snapshot())
        }
        throws<DiaryError.InvalidData> { DiaryDatabase.create(context, profile).close() }
    }

    @Test fun databaseFileIsInFilesDirIncludedInDeviceTransfer() {
        assertEquals(File(context.filesDir, "profiles/${profileID.toString().uppercase()}/diary.sqlite"), db.file)
        assertTrue(db.file.isFile)
        assertEquals("delete", db.pragma("journal_mode"))
        assertEquals("2", db.pragma("synchronous")) // FULL
        assertEquals("1", db.pragma("foreign_keys"))

        val rules = mutableMapOf<String, MutableList<String>>()
        val xml = context.resources.getXml(R.xml.data_extraction_rules)
        var section = ""
        while (xml.next() != XmlPullParser.END_DOCUMENT) {
            if (xml.eventType != XmlPullParser.START_TAG) continue
            when (xml.name) {
                "include", "exclude" -> rules.getOrPut(section) { mutableListOf() } +=
                    "${xml.name}:${xml.getAttributeValue(null, "domain")}:${xml.getAttributeValue(null, "path") ?: ""}"
                else -> section = xml.name
            }
        }
        assertTrue(rules["device-transfer"]!!.contains("include:file:"))
        assertTrue(rules["cloud-backup"]!!.contains("exclude:file:"))
        assertTrue(rules["cross-platform-transfer"]!!.contains("exclude:file:"))
    }
}
