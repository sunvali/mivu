package com.yakov103.mivu.diary

import java.util.UUID

// Port of ios/Mivu/Diary/DiaryDatabaseMealMutations.swift (prepareAnalysis, applyAnalysis, acceptReview, deleteMeal)
// and commitSavedItems (DiaryDatabaseManualNutrition.swift). A late analysis result never overwrites a newer edit
// (StaleRevision) and never brings back a deleted meal (NotFound; the tombstone blocks reinsertion).
// Analysis itself stays outside: these only apply an AnalysisOutput.

private val ANALYZABLE = setOf(SubmissionState.captured, SubmissionState.waitingForConnection, SubmissionState.analyzing,
    SubmissionState.needsRetry)

// iOS DiaryStore wraps each of these in a transaction at the current head (pagedMutation).
private fun <T> DiaryDatabase.atHead(body: (DiaryDatabase.Tx) -> T): T = transaction(head().revision, body)

private fun DiaryDatabase.Tx.mealRecord(id: UUID) = meal(id) ?: throw DiaryError.NotFound

private fun DiaryMeal.submission(id: UUID) = submissions.firstOrNull { it.id == id } ?: throw DiaryError.NotFound

private fun DiaryMeal.with(sub: MealSubmission) = copy(submissions = submissions.map { if (it.id == sub.id) sub else it })

// shortcut: putMeal rewrites the meal's photo blobs on every call; add a submission-only write if photo-heavy
// meals make analysis commits slow.
private fun DiaryDatabase.Tx.save(meal: DiaryMeal) = putMeal(meal)

/** iOS `commitSavedItems`: replaces the items and bumps the meal revision, only at [expectedRevision]. */
private fun DiaryDatabase.Tx.commitSavedItems(meal: DiaryMeal, items: List<FoodItem>, expectedRevision: Int): DiaryMeal {
    if (meal.revision != expectedRevision) throw DiaryError.StaleRevision
    return meal.copy(items = items, revision = meal.revision + 1, changedRevision = (head.revision + 1).toInt())
}

fun DiaryDatabase.prepareAnalysis(mealID: UUID, submissionID: UUID) = atHead { tx ->
    val meal = tx.mealRecord(mealID)
    val sub = meal.submission(submissionID)
    if (sub.state !in ANALYZABLE) throw DiaryError.InvalidData("submission state")
    if (sub.baseRevision != meal.revision) tx.save(meal.with(sub.copy(baseRevision = meal.revision, proposal = null)))
}

fun DiaryDatabase.applyAnalysis(output: AnalysisOutput) = atHead { tx ->
    if (output.profileID != tx.head.profile.id) throw DiaryError.WrongOwner
    if (output.schemaVersion != 1 || output.items.isEmpty()) throw DiaryError.InvalidData("analysis output")
    validateItems(output.items)
    val meal = tx.mealRecord(output.mealID)
    val sub = meal.submission(output.submissionID)
    if (sub.state == SubmissionState.saved || sub.state == SubmissionState.awaitingReview) return@atHead
    if (sub.state == SubmissionState.cancelled) throw DiaryError.NotFound
    if (output.baseRevision != meal.revision || output.baseRevision != sub.baseRevision) throw DiaryError.StaleRevision
    tx.save(if (sub.reviewFirst) meal.with(sub.copy(proposal = output, state = SubmissionState.awaitingReview))
    else tx.commitSavedItems(meal, output.items, meal.revision).with(sub.copy(proposal = output, state = SubmissionState.saved)))
}

/** iOS `acceptReview`, plus the caller's [expectedMealRevision] (checked after the idempotent return). */
fun DiaryDatabase.acceptReview(mealID: UUID, submissionID: UUID, expectedMealRevision: Int) = atHead { tx ->
    val meal = tx.mealRecord(mealID)
    val sub = meal.submission(submissionID)
    if (sub.state == SubmissionState.saved) return@atHead
    val proposal = sub.proposal
    if (sub.state != SubmissionState.awaitingReview || proposal == null) throw DiaryError.InvalidData("review")
    if (meal.revision != proposal.baseRevision || meal.revision != expectedMealRevision) throw DiaryError.StaleRevision
    tx.save(tx.commitSavedItems(meal, proposal.items, meal.revision).with(sub.copy(state = SubmissionState.saved)))
}

/**
 * Replaces the meal's items, like iOS `editItem`/`deleteItem`: a saved "Direct item edit" submission records the
 * change and the meal revision is bumped, so any analysis based on the old revision is stale.
 */
fun DiaryDatabase.editMealItems(mealID: UUID, items: List<FoodItem>, expectedMealRevision: Int) = atHead { tx ->
    val meal = tx.mealRecord(mealID)
    if (meal.revision != expectedMealRevision) throw DiaryError.StaleRevision
    // iOS deleteItem/scaleMeal: a pending submission is based on this revision; editing would strand it.
    if ((meal.submissions.lastOrNull()?.state ?: SubmissionState.saved) != SubmissionState.saved) throw DiaryError.InvalidData("meal not saved")
    val id = UUID.randomUUID()
    val output = AnalysisOutput(1, tx.head.profile.id, mealID, id, meal.revision, items)
    val saved = MealSubmission(id, meal.revision, "Direct item edit", emptyList(), false, SubmissionState.saved, output)
    val committed = tx.commitSavedItems(meal, items, meal.revision)
    tx.save(committed.copy(submissions = committed.submissions + saved))
}

/** iOS `deleteMeal`; the store's meal delete repairs the Coach turns that use its photos. */
fun DiaryDatabase.deleteMeal(mealID: UUID, expectedRevision: Long) = transaction(expectedRevision) { tx ->
    tx.mealRecord(mealID)
    tx.delete(DiaryDatabase.Tombstone.meal, mealID)
}
