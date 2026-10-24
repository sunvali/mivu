package com.yakov103.mivu.diary

import java.time.Instant
import java.util.UUID

// Port of iOS `captureProjection` and `validateManualRetry` (ios/Mivu/Diary/DiaryDatabaseMealMutations.swift) on the
// non-Coach path: the meal and its captured submission are saved before any analysis runs.

/** Saves a new meal at revision 0 with one captured submission; a retry with the same [submissionID] returns that meal. */
fun DiaryDatabase.captureProjection(
    text: String,
    photos: List<MealPhoto>,
    reviewFirst: Boolean,
    dayID: UUID,
    at: Instant,
    dateOnly: Boolean = false,
    submissionID: UUID = UUID.randomUUID(),
    expectedRevision: Long,
): DiaryMeal = transaction(expectedRevision) { tx ->
    tx.submissionParent(submissionID)?.let { prior ->
        tx.validateManualRetry(submissionID, text, photos)
        return@transaction tx.meal(prior) ?: throw DiaryError.NotFound
    }
    val day = tx.trackingDay(dayID)
    if (text.blankLikeSwift() && photos.isEmpty()) throw DiaryError.EmptyCapture
    if (photos.size > 8 || photos.map { it.id }.toSet().size != photos.size) throw DiaryError.InvalidData("capture photos")
    val sub = MealSubmission(submissionID, 0, text, photos.map { it.id }, reviewFirst, SubmissionState.captured)
    val meal = DiaryMeal(UUID.randomUUID(), dayID, at, if (dateOnly) day.startAt else at, 0, (tx.head.revision + 1).toInt(),
        if (dateOnly) MealTimePrecision.dateOnly else null, emptyList(), photos, listOf(sub))
    tx.putMeal(meal)
    tx.meal(meal.id)!! // as stored: Swift Date rounding included
}

/** A Coach turn under this ID fixed the capture's content: a retry must carry the same text and photos. */
private fun DiaryDatabase.Tx.validateManualRetry(submissionID: UUID, text: String, photos: List<MealPhoto>) {
    // Accepted context wins over a later retry clock/day. Legacy evidence is never fingerprinted retroactively.
    val manifest = coachTurn(submissionID)?.submissionManifest ?: return
    val attempted = CoachSubmissionPayload(submissionID, text, photos, manifest.context, manifest.pendingMealID, manifest.pendingMealRevision)
    if (attempted.manifest != manifest) throw DiaryError.StaleRevision
}
