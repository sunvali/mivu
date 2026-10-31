package com.yakov103.mivu.diary

import java.io.File
import java.io.InputStream
import java.io.OutputStream
import java.util.UUID

// Port of DiaryArchive.replacement and DiarySnapshot.isVerifiedSuccessor in ios/Mivu/Diary.

/** True when this snapshot's lineage passes through [prior]'s head and has moved on from it. */
private fun DiarySnapshot.isVerifiedSuccessor(prior: DiarySnapshot): Boolean {
    val head = prior.lineage?.lastOrNull() ?: return false
    val lineage = lineage ?: return false
    return lineage.lastOrNull() != head && head in lineage.dropLast(1)
}

/** The diary that restoring [incoming] over [original] writes; never older, unrelated or resurrecting a deletion. */
fun replacement(incoming: DiarySnapshot, original: DiarySnapshot): DiarySnapshot {
    validateArchiveManifests(incoming)
    if (incoming.profile.id != original.profile.id) throw DiaryError.WrongOwner
    if (incoming.revision < original.revision ||
        !(incoming == original || incoming.isVerifiedSuccessor(original)) ||
        incoming.meals.any { it.id in original.deletedMealIDs } ||
        incoming.weights.any { it.id in original.deletedWeightIDs } ||
        incoming.workouts.any { it.id in original.deletedWorkoutIDs }
    ) throw DiaryError.StaleArchive
    fun union(a: List<UUID>, b: List<UUID>) = (a + b).distinct().sortedBy { it.toString() } // same order as Swift's uppercase uuidString
    return incoming.copy(
        deletedMealIDs = union(incoming.deletedMealIDs, original.deletedMealIDs),
        deletedWeightIDs = union(incoming.deletedWeightIDs, original.deletedWeightIDs),
        deletedWorkoutIDs = union(incoming.deletedWorkoutIDs, original.deletedWorkoutIDs),
        revision = maxOf(incoming.revision, original.revision) + 1,
        lineage = (incoming.lineage ?: emptyList()).takeLast(255) + UUID.randomUUID(),
    )
}

/**
 * Streams the whole diary as a version-4 archive, reading one photo's bytes at a time. Over the size cap it throws
 * mid-write: write to a temp file.
 */
fun DiaryDatabase.exportArchive(out: OutputStream) = withPhotoDigests { snapshot, bytes -> DiaryArchive.encode(snapshot, out, bytes) }

/**
 * Restores an archive. A profile with no diary yet takes it as it is, like iOS `importProfile`; an existing
 * diary is replaced only by [replacement], in the same write transaction that reads it. Photo bytes are spooled
 * to `cacheDir/archive-<uuid>` while decoding and written one at a time; the spool is deleted either way.
 */
fun DiaryDatabase.importArchive(input: InputStream, cacheDir: File) =
    PhotoSpool(File(cacheDir, "archive-${UUID.randomUUID()}")).use { spool -> restore(DiaryArchive.decode(input, spool), spool) }

/** As [importArchive] for an archive already decoded into [spool]; the caller closes the spool. */
fun DiaryDatabase.restore(incoming: DiarySnapshot, spool: PhotoSpool) =
    replace(requireEmpty = false, photoBytes = spool::bytes) { current -> current?.let { replacement(incoming, it) } ?: incoming }

/** In-memory restore for small archives in tests. */
fun DiaryDatabase.importArchive(input: InputStream) {
    val incoming = DiaryArchive.decode(input)
    replace(requireEmpty = false) { current -> current?.let { replacement(incoming, it) } ?: incoming }
}
