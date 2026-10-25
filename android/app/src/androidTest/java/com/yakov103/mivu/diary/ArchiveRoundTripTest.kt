package com.yakov103.mivu.diary

import android.content.Context
import android.os.Debug
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

    @Test fun iosFixtureStillImports() {
        val exported = ByteArrayOutputStream()
        val first = DiaryDatabase.open(context, fixture.profile.id).use { db ->
            db.importArchive(iosFixture(), context.cacheDir)
            db.exportArchive(exported)
            db.snapshot()
        }
        assertEquals(fixture, first) // a fresh profile takes the archive as it is, like iOS importProfile
        clean()
        val second = DiaryDatabase.open(context, fixture.profile.id).use { db ->
            db.importArchive(exported.toByteArray().inputStream(), context.cacheDir)
            db.snapshot()
        }
        assertEquals(fixture, second)
        assertEquals(4, fixture.photoHashes().size)
        assertEquals(fixture.photoHashes(), second.photoHashes())
    }

    @Test fun androidExportStillMatchesFixture() {
        val golden = javaClass.classLoader!!.getResourceAsStream("archive/android-v4-full.json").readBytes()
        val exported = ByteArrayOutputStream()
        DiaryDatabase.open(context, fixture.profile.id).use { db ->
            db.importArchive(iosFixture(), context.cacheDir)
            db.exportArchive(exported)
        }
        // writeAndroidFixture adds one newline after the archive.
        assertEquals(golden.decodeToString(), exported.toByteArray().decodeToString() + "\n")
    }

    // The export reads each photo in its own short transaction, so a capture during the encode does not wait for it.
    @Test fun exportLetsWritesInBetweenPhotos() {
        val at = java.time.Instant.parse("2026-10-24T12:00:00Z")
        DiaryDatabase.open(context, fixture.profile.id).use { db ->
            db.importArchive(iosFixture(), context.cacheDir)
            val out = ByteArrayOutputStream()
            var captured = false
            db.withPhotoDigests { snapshot, bytes ->
                DiaryArchive.encode(snapshot, out) { digest ->
                    if (!captured) {
                        val h = db.head()
                        db.captureCoachSubmission(CoachSubmissionPayload(java.util.UUID.randomUUID(), "synthetic note", emptyList(),
                            CoachCaptureContext(at, h.profile.timeZoneID, h.activeDayID, h.previousDayConfirmedAt, h.activeConversationSegmentID)),
                            h.revision)
                        captured = true
                    }
                    bytes(digest)
                }
            }
            assertEquals(fixture, DiaryArchive.decode(out.toByteArray().inputStream()))
            assertEquals(fixture.revision + 1L, db.head().revision)
        }
    }

    @Test fun photoGoneDuringExportFailsIt() {
        DiaryDatabase.open(context, fixture.profile.id).use { db ->
            db.importArchive(iosFixture(), context.cacheDir)
            try {
                db.withPhotoDigests { snapshot, bytes ->
                    DiaryArchive.encode(snapshot, ByteArrayOutputStream()) { digest ->
                        if (db.photoBytes(snapshot.meals[0].id, snapshot.meals[0].photos[0].id) != null) {
                            db.deleteMeal(snapshot.meals[0].id, db.head().revision)
                        }
                        bytes(digest)
                    }
                }
                error("expected StaleRevision")
            } catch (_: DiaryError.StaleRevision) {}
        }
    }

    @Test fun failedImportRemovesTheSpool() {
        val cache = File(context.cacheDir, "truncated").apply { deleteRecursively(); mkdirs() }
        val bytes = iosFixture().readBytes()
        DiaryDatabase.open(context, fixture.profile.id).use { db ->
            db.importArchive(bytes.inputStream(), cache)
            val before = db.snapshot()
            try {
                db.importArchive(bytes.copyOf(bytes.size / 2).inputStream(), cache); error("expected InvalidData")
            } catch (_: DiaryError.InvalidData) {}
            assertEquals(before, db.snapshot())
        }
        assertEquals(emptyList<String>(), cache.list()!!.toList())
        cache.deleteRecursively()
    }

    @Test fun importOverExistingDiaryUsesRestoreRules() {
        DiaryDatabase.open(context, fixture.profile.id).use { db ->
            db.importArchive(iosFixture(), context.cacheDir)
            db.importArchive(iosFixture(), context.cacheDir) // the same archive again: equal, so it replaces with a new revision
            assertEquals(fixture.revision + 1, db.snapshot().revision)
            try { db.importArchive(iosFixture(), context.cacheDir); error("expected StaleArchive") } catch (_: DiaryError.StaleArchive) {}
            assertEquals(fixture.revision + 1, db.snapshot().revision)
        }
    }

    @Test fun fullFlowKeepsOneDiaryValidThroughDeleteExportAndImport() {
        val at = java.time.Instant.parse("2026-10-24T12:00:00Z")
        val profile = DiaryProfile(java.util.UUID.randomUUID(), "Synthetic", "en", "UTC", "")
        val day = TrackingDay(java.util.UUID.randomUUID(), "2026-10-24", "UTC", at, DayCompleteness.unknown)
        val photo = MealPhoto(java.util.UUID.randomUUID(), byteArrayOf(1, 2, 3), at, PhotoRole.unspecified)
        val sub = MealSubmission(java.util.UUID.randomUUID(), 0, "synthetic soup", emptyList(), false, SubmissionState.captured)
        val meal = DiaryMeal(java.util.UUID.randomUUID(), day.id, at, at, 0, items = emptyList(), photos = listOf(photo), submissions = listOf(sub))
        val exported = ByteArrayOutputStream()
        val final = DiaryDatabase.create(context, profile).use { db ->
            db.captureCoachSubmission(CoachSubmissionPayload(java.util.UUID.randomUUID(), "synthetic lunch",
                listOf(photo.copy(id = java.util.UUID.randomUUID())), CoachCaptureContext(at, "UTC")), db.head().revision)
            db.snapshot().validate()
            val linked = CoachTurn(java.util.UUID.randomUUID(), at, "synthetic", emptyList(), CoachTurnState.captured,
                receipts = emptyList(), captureTimeZoneID = "UTC", photoIDs = listOf(photo.id), pendingMealID = meal.id, pendingMealRevision = 0)
            db.transaction(db.head().revision) { it.putDay(day); it.putMeal(meal); it.putCoachTurn(linked) }
            db.applyAnalysis(AnalysisOutput(1, profile.id, meal.id, sub.id, 0, listOf(FoodItem(java.util.UUID.randomUUID(),
                "synthetic soup", 1.0, "serving", NutritionValues(kcal = 100.0), NutritionProvenance.estimate, "", true, emptyMap()))))
            db.snapshot().validate()
            db.deleteMeal(meal.id, db.head().revision)
            db.snapshot().validate()
            db.exportArchive(exported)
            db.importArchive(exported.toByteArray().inputStream(), context.cacheDir) // over the existing diary
            db.snapshot().also { it.validate() }
        }
        clean()
        val fresh = DiaryDatabase.open(context, profile.id).use { db ->
            db.importArchive(exported.toByteArray().inputStream(), context.cacheDir)
            db.snapshot().also { it.validate() }
        }
        assertEquals(listOf(meal.id), fresh.deletedMealIDs)
        assertEquals(final.coachTurns, fresh.coachTurns)
    }

    /** Copies Android's encoding of the iOS golden snapshot out for iOS to read; run with `writeFixtures=true`. */
    @Test fun writeAndroidFixture() {
        if (args.getString("writeFixtures") != "true") return // connected runs report a JUnit assumption as a failure
        File(context.filesDir, "android-v4-full.json").outputStream().use { out ->
            DiaryArchive.encode(fixture, out)
            out.write('\n'.code)
        }
    }

    /** 10 MB of seeded random bytes per synthetic photo; the archive carries a 32-byte placeholder until it is written. */
    private class Synthetic {
        val hashes = mutableMapOf<java.util.UUID, List<Byte>>()
        private val seeds = mutableMapOf<String, Int>()
        fun photo(template: MealPhoto, seed: Int): MealPhoto {
            val placeholder = ByteArray(32).also { java.nio.ByteBuffer.wrap(it).putInt(0x5EED0000 + seed) }
            seeds[placeholder.toList().toString()] = seed
            return template.copy(id = java.util.UUID.randomUUID(), data = placeholder).also { p ->
                hashes[p.id] = MessageDigest.getInstance("SHA-256").digest(bytes(placeholder)!!).toList()
            }
        }
        fun bytes(placeholder: ByteArray) = seeds[placeholder.toList().toString()]?.let { Random(it).nextBytes(10_000_000) }
        fun write(snapshot: DiarySnapshot, file: File) =
            file.outputStream().buffered().use { out -> DiaryArchive.encode(snapshot, out) { bytes(it) ?: it } }
    }

    private class Peak(label: String) : AutoCloseable {
        private val runtime = Runtime.getRuntime()
        private val name = label
        private var java = 0L
        private var native = 0L
        private val baseJava: Long
        private val baseNative: Long
        private val started = System.nanoTime()
        private fun sample() {
            java = maxOf(java, runtime.totalMemory() - runtime.freeMemory())
            native = maxOf(native, Debug.getNativeHeapAllocatedSize())
        }
        // Collecting before each sample makes the Java figure the live heap, not garbage awaiting the next GC.
        private val sampler = Thread { while (!Thread.interrupted()) { runtime.gc(); sample(); try { Thread.sleep(5) } catch (_: InterruptedException) { break } } }
        init {
            System.gc(); System.runFinalization(); System.gc()
            baseJava = runtime.totalMemory() - runtime.freeMemory()
            baseNative = Debug.getNativeHeapAllocatedSize()
            sampler.start()
        }
        var javaDelta = 0L
        override fun close() {
            sampler.interrupt(); sampler.join(); sample()
            javaDelta = java - baseJava
            Log.i("MivuArchiveMemory", "$name (live, GC per sample) javaBaseline=$baseJava javaPeak=$java javaDelta=$javaDelta " +
                "nativeBaseline=$baseNative nativePeak=$native nativeDelta=${native - baseNative} max=${runtime.maxMemory()} " +
                "ms=${(System.nanoTime() - started) / 1_000_000}")
        }
    }

    /** Base diary: the fixture plus 3 synthetic 10 MB photos; incoming: its successor with 12 others instead. */
    private fun hundredTwentyMegabytesOverADiary(synthetic: Synthetic, cache: File): DiarySnapshot {
        val meal = fixture.meals[0]
        fun withPhotos(s: DiarySnapshot, seeds: IntRange) = s.copy(meals = s.meals.map { m ->
            if (m.id == meal.id) m.copy(photos = meal.photos + seeds.map { synthetic.photo(meal.photos[0], it) }) else m
        })
        val base = File(cache, "base.json").also { synthetic.write(withPhotos(fixture, 0..2), it) }
        val incoming = withPhotos(fixture, 100..111).copy(lineage = fixture.lineage!! + java.util.UUID.randomUUID())
        DiaryDatabase.open(context, fixture.profile.id).use { db -> base.inputStream().buffered().use { db.importArchive(it, cache) } }
        base.delete()
        return incoming
    }

    private fun DiaryDatabase.assertSyntheticPhotos(synthetic: Synthetic, mealID: java.util.UUID, ids: List<java.util.UUID>) {
        for (id in ids) assertEquals(synthetic.hashes[id], MessageDigest.getInstance("SHA-256").digest(photoBytes(mealID, id)!!).toList())
    }

    @Test fun importHundredTwentyMegabytesOverADiary() {
        if (args.getString("measureMemory") != "true") return
        val cache = File(context.cacheDir, "large").apply { deleteRecursively(); mkdirs() }
        val synthetic = Synthetic()
        val incoming = hundredTwentyMegabytesOverADiary(synthetic, cache)
        val file = File(cache, "incoming.json").also { synthetic.write(incoming, it) }
        val meal = incoming.meals[0]
        val added = meal.photos.drop(fixture.meals[0].photos.size).map { it.id }
        assertEquals(12, added.size)
        DiaryDatabase.open(context, fixture.profile.id).use { db ->
            val old = synthetic.hashes.keys - added.toSet()
            Peak("import archive=${file.length()}").use { file.inputStream().buffered().use { db.importArchive(it, cache) } }
            assertEquals(fixture.revision + 1, db.head().revision.toInt())
            db.assertSyntheticPhotos(synthetic, meal.id, added)
            for (id in old) assertEquals(null, db.photoBytes(meal.id, id))
        }
        file.delete()
        assertEquals(emptyList<String>(), cache.list()!!.toList())
        cache.delete()
    }

    @Test fun exportHundredTwentyMegabytes() {
        if (args.getString("measureMemory") != "true") return
        val cache = File(context.cacheDir, "large").apply { deleteRecursively(); mkdirs() }
        val synthetic = Synthetic()
        val incoming = hundredTwentyMegabytesOverADiary(synthetic, cache)
        File(cache, "incoming.json").also { synthetic.write(incoming, it) }.let { f ->
            DiaryDatabase.open(context, fixture.profile.id).use { db -> f.inputStream().buffered().use { db.importArchive(it, cache) } }
            f.delete()
        }
        val out = File(cache, "export.json")
        DiaryDatabase.open(context, fixture.profile.id).use { db ->
            Peak("export").use { out.outputStream().buffered().use { db.exportArchive(it) } }
        }
        Log.i("MivuArchiveMemory", "export archive=${out.length()}")
        val added = incoming.meals[0].photos.drop(fixture.meals[0].photos.size).map { it.id }.toSet()
        PhotoSpool(File(cache, "check")).use { spool ->
            val exported = out.inputStream().buffered().use { DiaryArchive.decode(it, spool) }
            val photos = exported.meals[0].photos.filter { it.id in added }
            assertEquals(12, photos.size)
            for (p in photos) assertEquals(synthetic.hashes[p.id], p.data.toList()) // spool placeholders are SHA-256 of the real bytes
        }
        cache.deleteRecursively()
    }
}
