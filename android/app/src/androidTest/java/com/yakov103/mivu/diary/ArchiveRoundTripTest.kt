package com.yakov103.mivu.diary

import android.content.Context
import android.util.Log
import androidx.test.core.app.ApplicationProvider
import androidx.test.platform.app.InstrumentationRegistry
import java.io.ByteArrayOutputStream
import java.io.File
import java.security.MessageDigest
import kotlin.random.Random
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test

class ArchiveRoundTripTest {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val args = InstrumentationRegistry.getArguments()
    private fun iosFixture() = javaClass.classLoader!!.getResourceAsStream("archive/ios-v4-full.json")
    private val fixture = DiaryArchive.decode(iosFixture())

    @Before @After fun clean() { File(context.filesDir, "profiles").deleteRecursively() }

    private fun DiarySnapshot.photoHashes() = (meals.flatMap { it.photos } + coachTurns.flatMap { it.photos })
        .associate { it.id to MessageDigest.getInstance("SHA-256").digest(it.data).toList() }

    @Test fun androidExportImportsOnAndroidAndMatchesIosFixture() {
        val exported = ByteArrayOutputStream()
        val first = DiaryDatabase.open(context, fixture.profile.id).use { db ->
            db.importArchive(iosFixture())
            db.exportArchive(exported)
            db.snapshot()
        }
        assertEquals(fixture, first) // a fresh profile takes the archive as it is, like iOS importProfile
        clean()
        val second = DiaryDatabase.open(context, fixture.profile.id).use { db ->
            db.importArchive(exported.toByteArray().inputStream())
            db.snapshot()
        }
        assertEquals(fixture, second)
        assertEquals(4, fixture.photoHashes().size)
        assertEquals(fixture.photoHashes(), second.photoHashes())
    }

    @Test fun importOverExistingDiaryUsesRestoreRules() {
        DiaryDatabase.open(context, fixture.profile.id).use { db ->
            db.importArchive(iosFixture())
            db.importArchive(iosFixture()) // the same archive again: equal, so it replaces with a new revision
            assertEquals(fixture.revision + 1, db.snapshot().revision)
            try { db.importArchive(iosFixture()); error("expected StaleArchive") } catch (_: DiaryError.StaleArchive) {}
            assertEquals(fixture.revision + 1, db.snapshot().revision)
        }
    }

    /** Copies Android's encoding of the iOS golden snapshot out for iOS to read; run with `writeFixtures=true`. */
    @Test fun writeAndroidFixture() {
        if (args.getString("writeFixtures") != "true") return // connected runs report a JUnit assumption as a failure
        File(context.filesDir, "android-v4-full.json").outputStream().use { out ->
            DiaryArchive.encode(fixture, out)
            out.write('\n'.code)
        }
    }

    /** Practical import ceiling: ~50 MB of photos; run with `measureMemory=true`. */
    @Test fun importFiftyMegabytesOfPhotos() {
        if (args.getString("measureMemory") != "true") return
        fun big(p: MealPhoto) = p.copy(data = Random.nextBytes(10_000_000))
        val meals = fixture.meals.mapIndexed { i, m ->
            if (i == 0) m.copy(photos = m.photos.map(::big)) else m
        }
        val turns = fixture.coachTurns.map { t -> t.copy(photos = t.photos.map(::big)) }
        val extra = fixture.meals[1].let { it.copy(photos = listOf(big(fixture.meals[0].photos[0].copy(id = java.util.UUID.randomUUID())))) }
        val large = fixture.copy(meals = meals.map { if (it.id == extra.id) extra else it }, coachTurns = turns)
        val file = File(context.cacheDir, "large-archive.json")
        file.outputStream().buffered().use { DiaryArchive.encode(large, it) }
        val runtime = Runtime.getRuntime()
        var peak = 0L
        val sampler = Thread { while (!Thread.interrupted()) { peak = maxOf(peak, runtime.totalMemory() - runtime.freeMemory()); try { Thread.sleep(5) } catch (_: InterruptedException) { break } } }
        System.gc()
        val baseline = runtime.totalMemory() - runtime.freeMemory()
        sampler.start()
        val started = System.nanoTime()
        DiaryDatabase.open(context, fixture.profile.id).use { db -> file.inputStream().buffered().use { db.importArchive(it) } }
        val ms = (System.nanoTime() - started) / 1_000_000
        sampler.interrupt(); sampler.join()
        Log.i("MivuArchiveMemory", "archive=${file.length()} bytes photos=50000000 baseline=$baseline peak=$peak max=${runtime.maxMemory()} ms=$ms")
        file.delete()
    }
}
