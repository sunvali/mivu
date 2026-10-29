package com.yakov103.mivu.coach

import android.app.job.JobScheduler
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import androidx.test.core.app.ApplicationProvider
import com.yakov103.mivu.MivuApplication
import com.yakov103.mivu.diary.Bootstrap
import com.yakov103.mivu.diary.DiaryDatabase
import com.yakov103.mivu.diary.DiaryProfile
import com.yakov103.mivu.diary.DiaryRepository
import com.yakov103.mivu.diary.startDay
import com.yakov103.mivu.ui.today.TodayFixture
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException
import java.time.Instant
import java.time.temporal.ChronoUnit
import java.util.UUID
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.BeforeClass
import org.junit.Test

/** Synthetic diary, text and generated JPEGs; scripted inference only, so no ChatGPT call. */
class TellCoachTest {
    private val app: MivuApplication = ApplicationProvider.getApplicationContext()
    private lateinit var db: DiaryDatabase
    private lateinit var profileID: UUID

    companion object {
        // Before anything opens the app's diary, so the repository opens one synthetic diary.
        @BeforeClass @JvmStatic fun fresh() {
            val context: Context = ApplicationProvider.getApplicationContext()
            TodayFixture.wipe(context)
            TodayFixture.diary(context)
        }
    }

    @Before fun open() = runBlocking {
        profileID = (app.repository.bootstrap() as Bootstrap.Ready).profileID
        db = app.repository.database(profileID)
        if (db.head().activeDayID == null) db.startDay(Instant.now(), db.head().revision)
        app.coachInferenceForTest = { { _, _ -> CoachInferenceResult("fixture-model", "Noted.", emptyList(), emptyList()) } }
        TellCoach.canInferForTest = true
        withTimeout(10_000) { app.drainCoach(retryWaiting = true).join() } // an earlier test's turn finishes before this one reads
    }

    @After fun close() {
        TellCoach.beforeCaptureForTest = null
        TellCoach.afterCaptureForTest = null
        TellCoach.canInferForTest = null
        app.getSystemService(JobScheduler::class.java).cancelAll()
        app.coachInferenceForTest = null
    }

    private fun count() = db.coachTurnsWithoutPhotos().size
    private fun run(text: String, photos: List<File> = emptyList(), id: UUID = UUID.randomUUID()) = runBlocking { TellCoach.run(app, text, photos, id) }

    @Test fun savesOneCapturedTurnWithTheText() {
        val before = count()
        val id = UUID.randomUUID()
        assertEquals(TellCoachOutcome.Sent, run("Synthetic lunch: two boiled eggs and a slice of toast", id = id))
        assertEquals(before + 1, count())
        assertEquals("Synthetic lunch: two boiled eggs and a slice of toast", db.coachTurn(id)!!.text)
    }

    @Test fun uncertainFailureSavesOnce() {
        val before = count()
        var thrown = false
        TellCoach.afterCaptureForTest = { if (!thrown) { thrown = true; throw IOException("synthetic lost acknowledgement") } }
        val id = UUID.randomUUID()
        assertEquals(TellCoachOutcome.Sent, run("Synthetic black coffee", id = id))
        assertEquals(before + 1, count())
        // A second tap of Send to Coach in the same sheet keeps the ID: no second turn.
        assertEquals(TellCoachOutcome.Sent, run("Synthetic black coffee", id = id))
        assertEquals(before + 1, count())
    }

    @Test fun staleContextIsRebuiltOnce() {
        db.startDay(Instant.now().minus(2, ChronoUnit.DAYS), db.head().revision)
        var rolled = false
        // The day rolls over between the context read and the write.
        TellCoach.beforeCaptureForTest = { if (!rolled) { rolled = true; db.startDay(Instant.now(), db.head().revision) } }
        val before = count()
        val id = UUID.randomUUID()
        assertEquals(TellCoachOutcome.Sent, run("Synthetic apple", id = id))
        assertEquals(before + 1, count())
        assertEquals(db.head().activeDayID, db.coachTurn(id)!!.activeDayID)
    }

    @Test fun blankMessageFails() {
        val before = count()
        val id = UUID.randomUUID()
        assertEquals(TellCoachOutcome.Failed, run("  \n ", id = id))
        assertNull(db.coachTurn(id))
        assertEquals(before, count())
    }

    @Test fun noDiaryNeedsSetup() {
        // A second diary and a lost selection: the person must choose a diary first.
        val other = DiaryProfile(UUID.randomUUID(), "Synthetic other", "en", "UTC", "")
        DiaryDatabase.create(app, other).close()
        val prefs = DiaryRepository.preferences(app)
        prefs.edit().putString("selectedProfile", UUID.randomUUID().toString()).commit()
        try {
            runBlocking { app.repository.bootstrap() }
            assertEquals(TellCoachOutcome.NeedsSetup, run("Synthetic pear"))
        } finally {
            File(app.filesDir, "profiles/${other.id.toString().uppercase()}").deleteRecursively()
            File(app.filesDir, "profiles/${other.id}").deleteRecursively()
            prefs.edit().putString("selectedProfile", profileID.toString()).commit()
            runBlocking { app.repository.bootstrap() }
        }
    }

    @Test fun firstLaunchNeedsSetupAndCreatesNoDiary() {
        // As iOS `loadDiary(createDefaultProfile: false)`: a share before the app was ever opened leaves setup to Mivu.
        TodayFixture.wipe(app)
        try {
            assertEquals(TellCoachOutcome.NeedsSetup, run("Synthetic first share"))
            assertTrue(File(app.filesDir, "profiles").listFiles().isNullOrEmpty())
        } finally {
            profileID = TodayFixture.diary(app)
            runBlocking { app.repository.bootstrap() }
        }
    }

    @Test fun disconnectedSavesAndSaysConnect() {
        TellCoach.canInferForTest = null
        runBlocking { app.restored.join() }
        assertFalse(app.chatGPT.state.value.canInfer) // the emulator has no ChatGPT account
        val before = count()
        val id = UUID.randomUUID()
        assertEquals(TellCoachOutcome.SavedNeedsConnection, run("Synthetic yogurt", id = id))
        assertEquals(before + 1, count())
        assertEquals("Synthetic yogurt", db.coachTurn(id)!!.text)
    }

    @Test fun followsTheReplyBeforeRestoreFinishes() = runBlocking {
        // A sheet dismissed during a slow launch restore must already have its job: the follow comes before that wait.
        val original = app.restored
        val restoring = CompletableDeferred<Unit>()
        app.restored = app.scope.launch { restoring.await() }
        try {
            val id = UUID.randomUUID()
            val run = app.scope.async { TellCoach.run(app, "Synthetic toast", emptyList(), id) }
            withTimeout(5_000) { while (id !in app.followed) delay(20) }
            assertFalse(run.isCompleted)
            restoring.complete(Unit)
            assertEquals(TellCoachOutcome.Sent, withTimeout(10_000) { run.await() })
        } finally {
            restoring.complete(Unit)
            app.restored = original
        }
    }

    @Test fun photosAreSavedWithTheTurn() {
        val folder = File(app.cacheDir, "tell-coach-test").apply { deleteRecursively(); mkdirs() }
        val photos = listOf(Color.RED, Color.GREEN).map { color ->
            val bitmap = Bitmap.createBitmap(32, 24, Bitmap.Config.ARGB_8888).apply { eraseColor(color) }
            val bytes = ByteArrayOutputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, 85, it); it.toByteArray() }
            File(folder, "${UUID.randomUUID()}.jpg").apply { writeBytes(bytes) }
        }
        val id = UUID.randomUUID()
        try {
            assertEquals(TellCoachOutcome.Sent, run("", photos, id))
            val turn = db.coachTurn(id)!!
            assertEquals(photos.map { UUID.fromString(it.nameWithoutExtension) }, turn.photos.map { it.id })
            photos.zip(turn.photos).forEach { (file, photo) -> assertArrayEquals(file.readBytes(), photo.data) }
            assertNotEquals(0, turn.photos.size)
        } finally {
            folder.deleteRecursively()
        }
    }
}
