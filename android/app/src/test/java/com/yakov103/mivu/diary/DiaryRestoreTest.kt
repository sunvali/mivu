package com.yakov103.mivu.diary

import java.io.ByteArrayOutputStream
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.fail
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class DiaryRestoreTest {
    private val fixture = DiaryArchive.decode(javaClass.classLoader!!.getResourceAsStream("archive/ios-v4-full.json"))
    private val head = fixture.lineage!!.last()

    @get:Rule val tmp = TemporaryFolder()

    private fun fixtureStream() = javaClass.classLoader!!.getResourceAsStream("archive/ios-v4-full.json")

    private fun DiarySnapshot.resolved(spool: PhotoSpool) = copy(
        meals = meals.map { m -> m.copy(photos = m.photos.map { it.copy(data = spool.bytes(it.data)) }) },
        coachTurns = coachTurns.map { t -> t.copy(photos = t.photos.map { it.copy(data = spool.bytes(it.data)) }) },
    )

    private inline fun <reified E : Throwable> throws(block: () -> Unit) {
        try { block(); fail("expected ${E::class.simpleName}") } catch (e: Throwable) { if (e !is E) throw e }
    }

    /** The fixture as a later save on another device: same content, lineage extended past [head]. */
    private fun successor(vararg extra: UUID = arrayOf(UUID.randomUUID())) = fixture.copy(lineage = fixture.lineage!! + extra)

    @Test fun olderArchiveIsStale() {
        throws<DiaryError.StaleArchive> { replacement(successor(), fixture.copy(revision = fixture.revision + 1)) }
    }

    @Test fun unrelatedLineageIsStale() {
        throws<DiaryError.StaleArchive> { replacement(fixture.copy(lineage = listOf(UUID.randomUUID(), UUID.randomUUID())), fixture) }
        // The original's head as the incoming head is a sibling, not a successor.
        throws<DiaryError.StaleArchive> { replacement(fixture.copy(revision = fixture.revision + 1), fixture) }
    }

    @Test fun tombstoneResurrectionIsStale() {
        val weight = fixture.weights.first { it.dayID == null }
        val original = fixture.copy(weights = fixture.weights - weight, deletedWeightIDs = fixture.deletedWeightIDs + weight.id)
        throws<DiaryError.StaleArchive> { replacement(successor(), original) }
        // Only incoming is validated, so a tombstone beside the live record stands for "deleted here, still in the archive".
        throws<DiaryError.StaleArchive> { replacement(successor(), fixture.copy(deletedMealIDs = fixture.deletedMealIDs + fixture.meals[0].id)) }
        throws<DiaryError.StaleArchive> { replacement(successor(), fixture.copy(deletedWorkoutIDs = fixture.deletedWorkoutIDs + fixture.workouts[0].id)) }
    }

    @Test fun verifiedSuccessorMerges() {
        val extra = UUID.randomUUID()
        val incoming = successor(extra).copy(deletedMealIDs = listOf(UUID(0, 0x903)))
        val original = fixture.copy(deletedWorkoutIDs = fixture.deletedWorkoutIDs + UUID(0, 0x904))
        val result = replacement(incoming, original)
        assertEquals(fixture.revision + 1, result.revision)
        assertEquals((fixture.deletedMealIDs + UUID(0, 0x903)).sortedBy { it.toString() }, result.deletedMealIDs)
        assertEquals(original.deletedWorkoutIDs, result.deletedWorkoutIDs)
        assertEquals(incoming.lineage, result.lineage!!.dropLast(1))
        assertEquals(incoming.copy(revision = result.revision, deletedMealIDs = result.deletedMealIDs,
            deletedWorkoutIDs = result.deletedWorkoutIDs, lineage = result.lineage), result)

        val same = replacement(fixture, fixture)
        assertEquals(fixture.revision + 1, same.revision)
        assertEquals(fixture.lineage!! + same.lineage!!.last(), same.lineage)
        assertEquals(256, replacement(successor(*Array(254) { UUID.randomUUID() }), fixture).lineage!!.size)
    }

    @Test fun wrongOwner() {
        throws<DiaryError.WrongOwner> { replacement(successor(), fixture.copy(profile = fixture.profile.copy(id = UUID.randomUUID()))) }
    }

    @Test fun spooledReplacementEqualsInMemoryReplacement() {
        PhotoSpool(tmp.newFolder("spool")).use { spool ->
            val spooled = DiaryArchive.decode(fixtureStream(), spool)
            assertEquals(4, spooled.meals.sumOf { it.photos.size } + spooled.coachTurns.sumOf { it.photos.size })
            assertEquals(fixture, spooled.resolved(spool))
            val extra = UUID.randomUUID()
            val inMemory = replacement(successor(extra), fixture)
            val viaSpool = replacement(spooled.copy(lineage = spooled.lineage!! + extra), spooled).resolved(spool)
            assertEquals(inMemory.lineage!!.dropLast(1), viaSpool.lineage!!.dropLast(1))
            assertEquals(inMemory, viaSpool.copy(lineage = inMemory.lineage))
        }
    }

    @Test fun spoolRejectsOversizedPhoto() {
        val marker = ByteArray(32) { 7 }
        fun archive(size: Int) = ByteArrayOutputStream().also { out ->
            val meal = fixture.meals[0]
            val big = fixture.copy(meals = fixture.meals.map { m ->
                if (m.id == meal.id) m.copy(photos = listOf(m.photos[0].copy(data = marker)) + m.photos.drop(1)) else m
            })
            DiaryArchive.encode(big, out) { if (it.contentEquals(marker)) ByteArray(size) { 1 } else it }
        }.toByteArray()
        PhotoSpool(tmp.newFolder("ok")).use { DiaryArchive.decode(archive(10_000_000).inputStream(), it) }
        val dir = tmp.newFolder("over")
        PhotoSpool(dir).use { spool ->
            throws<DiaryError.InvalidData> { DiaryArchive.decode(archive(10_000_001).inputStream(), spool) }
        }
        assertEquals(false, dir.exists())
    }

    @Test fun manifestFingerprintsUseRealBytes() {
        PhotoSpool(tmp.newFolder("spool")).use { spool ->
            val bytes = byteArrayOf(1, 2, 3)
            assertEquals(fingerprint(bytes), spool.fingerprint(spool.put(bytes)))
            val turns = DiaryArchive.decode(fixtureStream(), spool).coachTurns
            val attachments = turns.flatMap { t -> t.submissionManifest?.attachments.orEmpty().map { a -> a to t.photos.first { it.id == a.id } } }
            assertEquals(1, attachments.size)
            for ((a, photo) in attachments) assertEquals(a.contentFingerprint, spool.fingerprint(photo.data))
        }
    }
}
