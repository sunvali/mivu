package com.yakov103.mivu.diary

import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.fail
import org.junit.Test

class DiaryRestoreTest {
    private val fixture = DiaryArchive.decode(javaClass.classLoader!!.getResourceAsStream("archive/ios-v4-full.json"))
    private val head = fixture.lineage!!.last()

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
}
