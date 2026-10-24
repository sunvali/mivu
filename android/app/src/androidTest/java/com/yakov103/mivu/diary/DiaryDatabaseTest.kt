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
        db.transaction(db.head().revision) {}
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
        val other = SQLiteDatabase.openDatabase(db.file, SQLiteDatabase.OpenParams.Builder().build())
        try {
            db.transaction(db.head().revision) {
                // Nothing written yet: only BEGIN IMMEDIATE (not DEFERRED) holds the RESERVED lock here.
                try {
                    other.execSQL("BEGIN IMMEDIATE")
                    other.execSQL("ROLLBACK")
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
