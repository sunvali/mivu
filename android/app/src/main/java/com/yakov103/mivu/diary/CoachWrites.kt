@file:UseSerializers(SwiftUUID::class)

package com.yakov103.mivu.diary

import com.yakov103.mivu.coach.CoachContext
import com.yakov103.mivu.coach.CoachError
import com.yakov103.mivu.coach.CoachManualEdit
import com.yakov103.mivu.coach.CoachWrite
import com.yakov103.mivu.coach.CoachWriteMode
import com.yakov103.mivu.coach.set
import com.yakov103.mivu.coach.coachJSON
import com.yakov103.mivu.coach.commandFingerprint
import java.time.Instant
import java.util.UUID
import kotlinx.serialization.Serializable
import kotlinx.serialization.UseSerializers
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject

// Port of ios/Mivu/Diary/DiaryDatabaseCoachMutations.swift: applyCoachWrites (:5), validateCoachWrites (:33-73),
// validateReplay (:88), validateCoachWrite (:112), coachDay (:182), addedCoachItems (:204), applyCoachWrite (:215),
// undoSnapshot/undoCoachChange (:301-346) and applyManual (:358). One batch is one transaction: all or nothing.
// Android has no record_source or photo_consumer tables: a turn reaches a photo through its own copy or a meal its
// pending meal or receipts link, so iOS `addSource` has no counterpart and photo transfers move copies.

private const val MAX_RECEIPTS = 16

/** Validates [writes] for [turnID] against the current diary without writing. */
fun DiaryDatabase.validateCoachWrites(
    turnID: UUID, writes: List<CoachWrite>, mode: CoachWriteMode = CoachWriteMode.uninterrupted, at: Instant = Instant.now(),
) {
    read { tx -> tx.validateCoachWrites(tx.coachTurnWithoutPhotos(turnID) ?: throw DiaryError.NotFound, writes, mode, at) }
}

/** Applies the batch with one receipt per write; a write whose key already has a receipt returns it unchanged. */
fun DiaryDatabase.applyCoachWrites(
    turnID: UUID, writes: List<CoachWrite>, mode: CoachWriteMode = CoachWriteMode.uninterrupted, at: Instant = Instant.now(),
): List<CoachReceipt> {
    purgeDeletedUndoApart(at) // copies past their window go while the app stays open
    return atHead { tx ->
        val turn = tx.coachTurn(turnID) ?: throw DiaryError.NotFound
        val normalized = tx.validateCoachWrites(turn, writes, mode, at)
        val batch = CoachBatch(turn, at)
        val results = mutableListOf<CoachReceipt>()
        for (write in normalized) {
            val key = "${turnID.swift}/${write.target}"
            val prior = turn.receipts.firstOrNull { it.operationKey == key }
            if (prior != null) { results += prior; continue }
            val before = tx.undoSnapshot(write, turn)
            val held = tx.deletedSnapshot(write)
            var receipt = tx.applyCoachWrite(write, batch).copy(operationKey = key, commandFingerprint = write.commandFingerprint())
            if (before != null && receipt.mealID != null) tx.saveUndo(key, turnID, receipt.mealID, before)
            // Tells the model this delete can still be undone.
            if (held != null && tx.holdDelete(key, turnID, held, at, freeBytes())) receipt = receipt.copy(resultJSON = undoHint(receipt.resultJSON, key))
            batch.added += receipt
            results += receipt
        }
        if (batch.added.isNotEmpty()) {
            val stored = tx.coachTurn(turnID) ?: throw DiaryError.NotFound
            var final = stored.copy(receipts = stored.receipts + batch.added, photos = stored.photos.filter { it.id !in batch.moved })
            final.pendingMealID?.let { id -> tx.mealWithoutPhotoBytes(id)?.let { final = final.copy(pendingMealRevision = it.revision) } }
            tx.putCoachTurn(final)
        }
        results
    }
}

/**
 * Restores the meal as the change left it only while nothing changed it since; never recreates a deleted meal. A Coach delete
 * still held for Undo is recreated under new IDs instead (CoachDeletedUndo.kt).
 */
fun DiaryDatabase.undoCoachChange(operationKey: String, now: Instant = Instant.now()): UUID? = atHead { it.undoCoachChange(operationKey, now) }

private fun undoHint(json: String, key: String) = JsonObject((SwiftJson.parseToJsonElement(json).jsonObject +
    mapOf("undo_key" to JsonPrimitive(key), "undo_until" to JsonPrimitive("next message"))).toSortedMap()).toString()

private class CoachBatch(val turn: CoachTurn, val at: Instant) {
    val added = mutableListOf<CoachReceipt>()
    /** Turn photo copies a meal now holds; the final turn save drops them. */
    val moved = mutableSetOf<UUID>()
}

@Serializable private data class Deleted(val id: UUID, val deleted: Boolean = true)
@Serializable private data class Queued(val queued: Boolean = true, val turnID: UUID)
@Serializable private data class Handoff(val destination: CoachDestination, val completed: Boolean = false)
@Serializable internal data class PreferencesResult(val profile: DiaryProfile, val diaryRevision: Int)
@Serializable private data class CorrectionResult(val mealID: UUID, val targetLocalDate: String, val revision: Int, val state: SubmissionState, val item: FoodItem)

private fun WorkoutSession.edited(draft: WorkoutDraft) = copy(kind = draft.kind, durationMinutes = draft.durationMinutes,
    exercises = draft.exercises, estimatedBurnKcal = draft.estimatedBurnKcal, burnSource = draft.burnSource, revision = revision + 1)

/** iOS `weightReceiptDay`: a legacy weight without a day names the profile-zone day of its measurement. */
private fun DiaryDatabase.Tx.weightReceiptDay(weight: WeightEntry): TrackingDay {
    weight.dayID?.let { return trackingDay(it) }
    val zone = head.profile.timeZoneID
    val date = diaryDateLabel(weight.measuredAt, zone)
    return resolveDay(date, zone, diaryDateOnlyInstant(date, zone))
}

private val DiaryMeal.state get() = submissions.lastOrNull()?.state ?: SubmissionState.saved

private fun DiaryDatabase.Tx.mealInfo(id: UUID) = mealWithoutPhotoBytes(id) ?: throw DiaryError.NotFound

/** iOS `saveMeal` stamps the change revision. */
internal fun DiaryDatabase.Tx.saveMeal(meal: DiaryMeal) = save(meal.copy(changedRevision = (head.revision + 1).toInt()))

private fun DiaryDatabase.Tx.mealResult(id: UUID): String {
    val m = mealInfo(id)
    return coachJSON(CoachContext.Meal.serializer(), CoachContext.Meal(m.id, m.dayID, m.revision, m.eatenAt, m.timePrecision, m.items, m.state))
}

/** The batch as it will apply: a dated weight that already exists becomes its correction. */
internal fun DiaryDatabase.Tx.validateCoachWrites(turn: CoachTurn, original: List<CoachWrite>, mode: CoachWriteMode, at: Instant): List<CoachWrite> {
    if (original.map { it.target }.toSet().size != original.size) throw CoachError.InvalidArguments
    val writes = original.map { resolvedWeightWrite(it, turn) }
    if (writes.map { it.target }.toSet().size != writes.size) throw CoachError.InvalidArguments
    val records = writes.mapNotNull {
        when (it) {
            is CoachWrite.CorrectWeight -> "weight/${it.id.swift}"
            is CoachWrite.DeleteWeight -> "weight/${it.id.swift}"
            is CoachWrite.EditWorkout -> "workout/${it.id.swift}"
            is CoachWrite.DeleteWorkout -> "workout/${it.id.swift}"
            is CoachWrite.Weight -> "weight-date/${it.date}"
            is CoachWrite.Workout -> "workout-date/${it.date}"
            else -> null
        }
    }
    if (records.toSet().size != records.size) throw CoachError.InvalidArguments
    if (turn.pendingMealID != null && writes.count { it is CoachWrite.Food } > 1) throw CoachError.InvalidArguments
    var newCount = 0
    for (write in writes) {
        val receipt = turn.receipts.firstOrNull { it.operationKey == "${turn.id.swift}/${write.target}" }
        if (receipt != null) {
            if (receipt.commandFingerprint != null && receipt.commandFingerprint != write.commandFingerprint()) throw CoachError.InvalidArguments
            validateReplay(write, receipt)
        } else {
            if (mode == CoachWriteMode.replayOnly) throw CoachError.InvalidArguments
            newCount++
            validateCoachWrite(write, turn, at)
        }
    }
    if (turn.receipts.size + newCount > MAX_RECEIPTS) throw CoachError.LimitExceeded
    return writes
}

/** iOS `resolvedWeightWrite`: log_weight for a date that already has a weight corrects it (revision required). */
private fun DiaryDatabase.Tx.resolvedWeightWrite(write: CoachWrite, turn: CoachTurn): CoachWrite {
    if (write !is CoachWrite.Weight) return write
    val prefix = "${turn.id.swift}/"
    if (turn.receipts.any { it.operationKey == "${prefix}weight/${write.date}" }) return write
    val days = boundedRecords("day", TrackingDay.serializer(), "json_extract(CAST(payload AS TEXT), '$.localDate') = ? AND " +
        "json_extract(CAST(payload AS TEXT), '$.timeZoneID') = ?", listOf(write.date, turn.captureTimeZoneID), "ordinal", 10_000)
    val dayIDs = days.map { it.id }.toSet()
    val existing = turn.receipts.firstOrNull { r -> r.weightID != null && r.operationKey == "${prefix}correct_weight/${r.weightID.swift}" && r.dayID in dayIDs }
        ?.weightID ?: days.firstNotNullOfOrNull { weightOn(it.id) }?.id ?: return write
    return CoachWrite.CorrectWeight(existing, write.value, write.unit, write.revision ?: throw DiaryError.StaleRevision)
}

/** A replayed receipt still names live records, and a replayed delete is still deleted. */
private fun DiaryDatabase.Tx.validateReplay(write: CoachWrite, receipt: CoachReceipt) {
    fun found(condition: Boolean) { if (!condition) throw DiaryError.NotFound }
    when (write) {
        is CoachWrite.DeleteWeight -> return found(isTombstoned(DiaryDatabase.Tombstone.weight, write.id))
        is CoachWrite.DeleteWorkout -> return found(isTombstoned(DiaryDatabase.Tombstone.workout, write.id))
        is CoachWrite.Manual -> when (val e = write.edit) {
            is CoachManualEdit.DeleteMeal -> return found(isTombstoned(DiaryDatabase.Tombstone.meal, e.mealID))
            is CoachManualEdit.DeleteItem -> return found(mealInfo(e.mealID).items.none { it.id == e.itemID })
            is CoachManualEdit.DeletePhoto -> return found(mealInfo(e.mealID).photos.none { it.id == e.photoID })
            is CoachManualEdit.Attach -> return found(mealInfo(e.mealID).photos.map { it.id }.containsAll(e.photoIDs))
            else -> {}
        }
        else -> {}
    }
    receipt.mealID?.let { id ->
        val meal = mealInfo(id)
        receipt.itemID?.let { item -> found(meal.items.any { it.id == item }) }
    }
    receipt.weightID?.let { found(isLive(DiaryDatabase.Tombstone.weight, it)) }
    receipt.workoutID?.let { found(isLive(DiaryDatabase.Tombstone.workout, it)) }
    receipt.goalID?.let { id -> found(goals().any { it.id == id }) }
    receipt.dayID?.let { trackingDay(it) }
}

private fun DiaryDatabase.Tx.validateCoachWrite(write: CoachWrite, turn: CoachTurn, at: Instant) {
    fun meal(id: UUID, revision: Int): DiaryMeal {
        if (turn.pendingMealID != null && turn.pendingMealID != id) throw DiaryError.InvalidData("coach meal")
        val meal = mealInfo(id)
        if (meal.revision != revision || (turn.pendingMealID == id && turn.pendingMealRevision != revision)) throw DiaryError.StaleRevision
        return meal
    }
    val zone = turn.captureTimeZoneID
    when (write) {
        is CoachWrite.Food -> {
            if (write.items.isEmpty()) throw DiaryError.InvalidData("food")
            validateItems(write.items)
            diaryDateOnlyInstant(write.date, zone)
            if (write.eatenAt != null && diaryDateLabel(write.eatenAt, zone) != write.date) throw DiaryError.InvalidData("eaten at")
            turn.pendingMealID?.let { id ->
                val current = mealRecord(id)
                if (current.submission(turn.id).state == SubmissionState.cancelled) throw DiaryError.NotFound
                if (current.revision != turn.pendingMealRevision) throw DiaryError.StaleRevision
                addedCoachItems(write.items, current, turn.id)
                if (current.revision > 0 && trackingDay(current.dayID).localDate != write.date) throw DiaryError.AmbiguousDay
            }
        }
        is CoachWrite.Correction -> {
            val previous = meal(write.mealID, write.revision).items.firstOrNull { it.id == write.item.id } ?: throw DiaryError.NotFound
            validateItems(listOf(diaryCorrectedItem(write.item, previous, emptySet())))
        }
        is CoachWrite.Close -> diaryDateOnlyInstant(write.date, zone)
        is CoachWrite.Manual -> when (val e = write.edit) {
            is CoachManualEdit.Item -> {
                val m = meal(e.mealID, e.revision)
                val items = e.submissionID?.let { m.submission(it).proposal?.items ?: emptyList() } ?: m.items
                if (items.firstOrNull { it.id == e.item.id } != e.original) throw DiaryError.StaleRevision
                validateItems(listOf(diaryCorrectedItem(e.item, e.original, e.explicitNutrients)))
            }
            is CoachManualEdit.Append -> {
                val m = meal(e.mealID, e.revision)
                validateItems(e.items)
                if (m.state != SubmissionState.saved) throw DiaryError.InvalidData("meal not saved")
            }
            is CoachManualEdit.Accept -> meal(e.mealID, e.revision).submission(e.submissionID)
            is CoachManualEdit.Move -> {
                if (meal(e.mealID, e.revision).dayID != e.originalDayID) throw DiaryError.StaleRevision
                diaryDateOnlyInstant(e.date, zone)
            }
            is CoachManualEdit.DeleteMeal -> meal(e.mealID, e.revision)
            is CoachManualEdit.Retry -> meal(e.mealID, e.revision)
            is CoachManualEdit.Attach -> {
                val m = meal(e.mealID, e.revision)
                if (e.photoIDs.isEmpty() || e.photoIDs.toSet().size != e.photoIDs.size) throw DiaryError.InvalidData("photos")
                if (e.photoIDs.any { id -> id !in turn.photoIDs || m.photos.any { it.id == id } }) throw DiaryError.NotFound
            }
            is CoachManualEdit.DeleteItem -> {
                val items = meal(e.mealID, e.revision).items
                if (items.none { it.id == e.itemID }) throw DiaryError.NotFound
                if (items.size <= 1) throw DiaryError.InvalidData("last item")
            }
            is CoachManualEdit.ScaleMeal -> {
                val m = meal(e.mealID, e.revision)
                if (m.state != SubmissionState.saved) throw DiaryError.InvalidData("meal not saved")
                val known = m.items.mapNotNull { it.nutrition.kcal }.sum()
                if (known <= 0 || e.targetKcal / known !in 0.1..3.0) throw DiaryError.InvalidData("scale")
            }
            is CoachManualEdit.DeletePhoto -> if (meal(e.mealID, e.revision).photos.none { it.id == e.photoID }) throw DiaryError.NotFound
            is CoachManualEdit.StartDay -> {
                if (head.revision != e.revision.toLong()) throw DiaryError.StaleRevision
                val profileZone = head.profile.timeZoneID
                val ordered = head.activeDayID?.let { trackingDay(it).startAt <= turn.capturedAt } ?: true
                if (zone != profileZone || diaryDateLabel(turn.capturedAt, zone) != diaryDateLabel(at, profileZone) || !ordered) throw DiaryError.AmbiguousDay
            }
            is CoachManualEdit.Coverage -> diaryDateOnlyInstant(e.date, zone)
            is CoachManualEdit.Undo -> if (isHeldDelete(e.operationKey)) {
                if (!deletedUndoUsable(e.operationKey, at, turn)) throw DiaryError.StaleRevision
            } else {
                val undo = coachUndo(e.operationKey) ?: throw CoachError.InvalidArguments
                if (undo.undone || undoState(mealInfo(undo.mealID)) != undo.afterState) throw DiaryError.StaleRevision
            }
            is CoachManualEdit.Open -> {}
            is CoachManualEdit.Goals -> {
                if (exactGoal(e.date)?.revision != e.revision) throw DiaryError.StaleRevision
                if (e.targets.map { it.nutrient }.toSet().size != e.targets.size ||
                    e.targets.any { it.nutrient !in setOf("kcal", "carbs", "protein", "fat") }) throw DiaryError.InvalidData("targets")
            }
            is CoachManualEdit.Preferences -> if (head.revision != e.revision.toLong()) throw DiaryError.StaleRevision
        }
        is CoachWrite.Workout -> diaryDateOnlyInstant(write.date, zone)
        is CoachWrite.Weight -> {
            diaryDateOnlyInstant(write.date, zone)
            if (write.revision != null) throw DiaryError.StaleRevision
            validateWeight(WeightEntry(UUID.randomUUID(), null, turn.capturedAt, write.value, write.unit))
        }
        is CoachWrite.CorrectWeight -> {
            val record = weight(write.id)
            if (record.revision != write.revision) throw DiaryError.StaleRevision
            validateWeight(record.copy(value = write.value, unit = write.unit, revision = record.revision + 1))
        }
        is CoachWrite.EditWorkout -> {
            val record = workout(write.id)
            if (record.revision != write.revision) throw DiaryError.StaleRevision
            validateWorkout(record.edited(write.draft))
        }
        is CoachWrite.DeleteWeight -> if (weight(write.id).revision != write.revision) throw DiaryError.StaleRevision
        is CoachWrite.DeleteWorkout -> if (workout(write.id).revision != write.revision) throw DiaryError.StaleRevision
    }
}

/** iOS `coachDay`: the tracking day a Coach write for [date] lands on, from the turn's persisted capture clock. */
private fun DiaryDatabase.Tx.coachDay(date: String, turn: CoachTurn, activateIfEmpty: Boolean = true, exact: Boolean = false): TrackingDay {
    val zone = turn.captureTimeZoneID
    val noon = diaryDateOnlyInstant(date, zone)
    val current = diaryDateLabel(turn.capturedAt, zone) == date
    var rollsOver = false
    if (!exact && current) {
        turn.resolvedDayID?.let { return trackingDay(it) }
        turn.activeDayID?.let { id ->
            val active = trackingDay(id)
            val waking = wakingDateLabel(turn.capturedAt, zone)
            // Before the cutoff the active day is still the waking day, so late food stays in it.
            if (active.localDate == waking) return active
            // After the cutoff with yesterday still open (the app stayed open), this capture starts the new day.
            rollsOver = active.localDate < waking && date == waking && head.activeDayID == id
            if (active.localDate != date && !rollsOver) throw DiaryError.AmbiguousDay
        }
    }
    val day = resolveDay(date, zone, if (current) turn.capturedAt else noon)
    if (activateIfEmpty && current && (head.activeDayID == null || rollsOver)) activateDay(day)
    return day
}

/** A saved meal gains only new foods: no repeated item ID or (trimmed, case-insensitive) name. */
private fun addedCoachItems(items: List<FoodItem>, meal: DiaryMeal, turnID: UUID): List<FoodItem> {
    if (meal.revision <= 0) return items
    val previous = meal.submissions.firstOrNull { it.id == turnID && it.state == SubmissionState.awaitingReview }?.proposal?.items ?: meal.items
    val ids = previous.map { it.id }.toSet()
    val names = previous.map { it.name.trim().lowercase() }.toSet()
    if (items.any { it.id in ids || it.name.trim().lowercase() in names }) throw DiaryError.InvalidData("repeated food")
    return (previous + items).also(::validateItems)
}

private fun DiaryDatabase.Tx.applyCoachWrite(write: CoachWrite, batch: CoachBatch): CoachReceipt {
    val turn = batch.turn
    var receipt = CoachReceipt("${turn.id.swift}/${write.target}", turn.id, committedRevision = (head.revision + 1).toInt(), resultJSON = "{}")
    when (write) {
        is CoachWrite.Food -> {
            val day = coachDay(write.date, turn)
            val pendingID = turn.pendingMealID
            var meal = pendingID?.let { mealRecord(it) } ?: DiaryMeal(UUID.randomUUID(), day.id, turn.capturedAt, day.startAt, 0, null,
                MealTimePrecision.dateOnly, emptyList(), emptyList(), emptyList())
            val proposalItems = addedCoachItems(write.items, meal, turn.id)
            if (pendingID != null) {
                var sub = meal.submission(turn.id)
                val proposal = AnalysisOutput(1, head.profile.id, meal.id, turn.id, meal.revision, proposalItems)
                meal = meal.copy(dayID = day.id)
                if (sub.reviewFirst || write.reviewFirst) sub = sub.copy(proposal = proposal, state = SubmissionState.awaitingReview)
                else {
                    meal = commitSavedItems(meal, proposalItems, meal.revision)
                    sub = sub.copy(proposal = proposal, state = SubmissionState.saved)
                }
                if (turn.pendingMealRevision == 0 && day.id != turn.activeDayID) meal = meal.copy(eatenAt = day.startAt, timePrecision = MealTimePrecision.dateOnly)
                meal = meal.with(sub)
            } else if (write.reviewFirst) {
                val proposal = AnalysisOutput(1, head.profile.id, meal.id, turn.id, 0, write.items)
                meal = meal.copy(submissions = listOf(MealSubmission(turn.id, 0, turn.text, turn.photoIDs, true, SubmissionState.awaitingReview, proposal)))
            } else meal = commitSavedItems(meal, write.items, meal.revision)
            // The turn's own photo copies move into the meal (a pending meal may hold them already); the receipt links them.
            val photos = turn.photos.filter { it.id !in batch.moved }
            saveMeal(meal.copy(photos = meal.photos + photos.filter { p -> meal.photos.none { it.id == p.id } }))
            batch.moved += photos.map { it.id }
            receipt = receipt.copy(dayID = day.id, mealID = meal.id, resultJSON = mealResult(meal.id))
        }
        is CoachWrite.Correction -> {
            var meal = mealRecord(write.mealID)
            val pending = if (turn.pendingMealID == write.mealID) meal.submission(turn.id) else null
            val source = pending?.proposal?.takeIf { pending.state == SubmissionState.awaitingReview }?.items ?: meal.items
            val index = source.indexOfFirst { it.id == write.item.id }
            if (index < 0) throw DiaryError.NotFound
            val edited = diaryCorrectedItem(write.item, source[index], emptySet())
            val items = source.toMutableList().also { it[index] = edited }
            validateItems(items)
            fun updated(m: DiaryMeal): DiaryMeal { // iOS updateCoachItem: the saved row in place, then a revision bump
                val i = m.items.indexOfFirst { it.id == edited.id }
                if (i < 0) throw DiaryError.NotFound
                return m.copy(items = m.items.toMutableList().also { it[i] = edited }, revision = m.revision + 1)
            }
            if (pending != null) {
                val proposal = AnalysisOutput(1, head.profile.id, write.mealID, turn.id, pending.baseRevision, items)
                if (!pending.reviewFirst) meal = updated(meal)
                meal = meal.with(pending.copy(proposal = proposal, state = if (pending.reviewFirst) SubmissionState.awaitingReview else SubmissionState.saved))
            } else meal = updated(meal)
            saveMeal(meal)
            receipt = receipt.copy(dayID = meal.dayID, mealID = meal.id, itemID = edited.id, resultJSON = coachJSON(CorrectionResult.serializer(),
                CorrectionResult(meal.id, trackingDay(meal.dayID).localDate, meal.revision, mealInfo(meal.id).state, edited)))
        }
        is CoachWrite.Close -> {
            val day = coachDay(write.date, turn).copy(completeness = write.completeness, closedAt = turn.capturedAt)
            putDay(day)
            receipt = receipt.copy(dayID = day.id, resultJSON = coachJSON(TrackingDay.serializer(), day))
        }
        is CoachWrite.Manual -> receipt = applyManual(write.edit, batch, receipt)
        is CoachWrite.Weight -> {
            val profileZone = head.profile.timeZoneID
            val current = write.date == diaryDateLabel(turn.capturedAt, turn.captureTimeZoneID)
            val day = coachDay(write.date, if (current) turn.copy(activeDayID = null, resolvedDayID = null) else turn, activateIfEmpty = false)
            val conflicting = boundedRecords("day", TrackingDay.serializer(), "json_extract(CAST(payload AS TEXT), '$.localDate') = ? AND id != ?",
                listOf(write.date, day.id.swift), "ordinal", 10_000)
            if (conflicting.any { weightOn(it.id) != null }) throw DiaryError.StaleRevision
            val active = head.activeDayID?.let { trackingDay(it) }
            if (current && write.date == diaryDateLabel(batch.at, profileZone) &&
                (active == null || (active.localDate <= write.date && active.startAt <= turn.capturedAt))) activateDay(day)
            val saved = setWeight(day.id, write.value, write.unit, write.revision)
            receipt = receipt.copy(dayID = day.id, weightID = saved.id, resultJSON = coachJSON(WeightEntry.serializer(), saved))
        }
        is CoachWrite.CorrectWeight -> {
            val record = weight(write.id).let { it.copy(value = write.value, unit = write.unit, revision = it.revision + 1) }
            putWeight(record)
            receipt = receipt.copy(dayID = weightReceiptDay(record).id, weightID = record.id, resultJSON = coachJSON(WeightEntry.serializer(), record))
        }
        is CoachWrite.Workout -> {
            val saved = createWorkout(coachDay(write.date, turn).id, write.draft)
            receipt = receipt.copy(dayID = saved.dayID, workoutID = saved.id, resultJSON = coachJSON(WorkoutSession.serializer(), saved))
        }
        is CoachWrite.EditWorkout -> {
            val record = workout(write.id).edited(write.draft)
            putWorkout(record)
            receipt = receipt.copy(dayID = record.dayID, workoutID = record.id, resultJSON = coachJSON(WorkoutSession.serializer(), record))
        }
        is CoachWrite.DeleteWeight -> {
            val dayID = weightReceiptDay(weight(write.id)).id
            deleteWeight(write.id, write.revision)
            receipt = receipt.copy(dayID = dayID, weightID = write.id, resultJSON = coachJSON(Deleted.serializer(), Deleted(write.id)))
        }
        is CoachWrite.DeleteWorkout -> {
            val dayID = workout(write.id).dayID
            deleteWorkout(write.id, write.revision)
            receipt = receipt.copy(dayID = dayID, workoutID = write.id, resultJSON = coachJSON(Deleted.serializer(), Deleted(write.id)))
        }
    }
    return receipt
}

private fun DiaryDatabase.Tx.applyManual(edit: CoachManualEdit, batch: CoachBatch, receipt: CoachReceipt): CoachReceipt {
    val turn = batch.turn
    fun mealReceipt(id: UUID, itemID: UUID? = null) = receipt.copy(mealID = id, itemID = itemID, dayID = mealInfo(id).dayID, resultJSON = mealResult(id))
    return when (edit) {
        is CoachManualEdit.Item -> {
            editItem(edit.mealID, edit.item, edit.explicitNutrients, edit.submissionID, null)
            mealReceipt(edit.mealID, edit.item.id)
        }
        is CoachManualEdit.Append -> {
            val m = mealRecord(edit.mealID)
            val submissionID = UUID.randomUUID()
            save(m.copy(submissions = m.submissions + MealSubmission(submissionID, m.revision, turn.text, emptyList(), false, SubmissionState.captured)))
            applyAnalysis(AnalysisOutput(1, head.profile.id, m.id, submissionID, m.revision, m.items + edit.items))
            mealReceipt(m.id)
        }
        is CoachManualEdit.Accept -> { acceptReview(edit.mealID, edit.submissionID, null); mealReceipt(edit.mealID) }
        is CoachManualEdit.Move -> {
            val day = coachDay(edit.date, turn, activateIfEmpty = false, exact = true)
            moveMeal(edit.mealID, day.id, null, null, null)
            mealReceipt(edit.mealID).copy(dayID = day.id)
        }
        is CoachManualEdit.DeleteMeal -> {
            val dayID = mealInfo(edit.mealID).dayID
            deleteMeal(edit.mealID)
            receipt.copy(dayID = dayID, mealID = edit.mealID, resultJSON = coachJSON(Deleted.serializer(), Deleted(edit.mealID)))
        }
        is CoachManualEdit.Attach -> {
            var target = mealRecord(edit.mealID)
            val linked = (listOfNotNull(turn.pendingMealID) + (turn.receipts + batch.added).mapNotNull { it.mealID }).toSet() - edit.mealID
            for (photoID in edit.photoIDs) {
                val own = turn.photos.filter { it.id == photoID && it.id !in batch.moved }
                val sources = own + linked.mapNotNull { id -> meal(id)?.photos?.firstOrNull { it.id == photoID } }
                if (sources.isEmpty()) throw DiaryError.NotFound
                if (sources.size > 1) throw DiaryError.InvalidData("photo source")
                target = target.copy(photos = target.photos + sources.single().copy(role = edit.role))
                if (own.isNotEmpty()) batch.moved += photoID
            }
            save(target)
            mealReceipt(edit.mealID)
        }
        is CoachManualEdit.DeleteItem -> { deleteItem(edit.mealID, edit.itemID, null); mealReceipt(edit.mealID, edit.itemID) }
        is CoachManualEdit.ScaleMeal -> { scaleMeal(edit.mealID, edit.targetKcal, null); mealReceipt(edit.mealID) }
        is CoachManualEdit.DeletePhoto -> {
            val dayID = mealInfo(edit.mealID).dayID
            deletePhoto(edit.mealID, edit.photoID)
            receipt.copy(dayID = dayID, mealID = edit.mealID, resultJSON = coachJSON(Deleted.serializer(), Deleted(edit.photoID)))
        }
        is CoachManualEdit.Retry -> {
            // The latest other paused turn for this meal: its pending capture, or one whose receipt saved it.
            val selected = query("SELECT t.id FROM coach_turn t WHERE t.id != ? AND json_extract(CAST(t.payload AS TEXT), '$.state') IN " +
                "('needsRetry','needsClarification','waitingForConnection','waitingForNetwork','captured') AND " +
                "(json_extract(CAST(t.payload AS TEXT), '$.pendingMealID') = ? OR EXISTS (SELECT 1 FROM json_each(CAST(t.payload AS TEXT), '$.receipts') r " +
                "WHERE json_extract(r.value, '$.mealID') = ?)) ORDER BY t.ordinal DESC LIMIT 1",
                listOf(turn.id.swift, edit.mealID.swift, edit.mealID.swift)) { if (it.moveToFirst()) swiftUUID(it.getString(0)) else null }
                ?: throw DiaryError.NotFound
            var paused = coachTurn(selected) ?: throw DiaryError.NotFound
            if (paused.receipts.isEmpty() && paused.pendingMealID != null) {
                val m = mealRecord(edit.mealID)
                save(m.with(m.submission(paused.id).copy(baseRevision = m.revision, proposal = null)))
                paused = paused.copy(pendingMealRevision = m.revision)
            }
            putCoachTurn(paused.copy(state = CoachTurnState.captured, assistantText = null))
            receipt.copy(dayID = mealInfo(edit.mealID).dayID, mealID = edit.mealID, resultJSON = coachJSON(Queued.serializer(), Queued(turnID = selected)))
        }
        is CoachManualEdit.StartDay -> {
            val day = startDay(turn.capturedAt)
            receipt.copy(dayID = day.id, resultJSON = coachJSON(TrackingDay.serializer(), day))
        }
        is CoachManualEdit.Coverage -> {
            val day = coachDay(edit.date, turn, activateIfEmpty = false, exact = true).copy(completeness = edit.completeness)
            putDay(day)
            receipt.copy(dayID = day.id, resultJSON = coachJSON(TrackingDay.serializer(), day))
        }
        is CoachManualEdit.Undo -> if (isHeldDelete(edit.operationKey)) when (val restored = undoDeleted(edit.operationKey)) {
            is Restored.Meal -> mealReceipt(restored.id)
            is Restored.Weight -> weight(restored.id).let {
                receipt.copy(dayID = weightReceiptDay(it).id, weightID = it.id, resultJSON = coachJSON(WeightEntry.serializer(), it))
            }
            is Restored.Workout -> workout(restored.id).let {
                receipt.copy(dayID = it.dayID, workoutID = it.id, resultJSON = coachJSON(WorkoutSession.serializer(), it))
            }
        } else {
            val mealID = coachUndo(edit.operationKey)?.mealID ?: throw DiaryError.NotFound
            val dayID = mealInfo(mealID).dayID
            val restored = undoCoachChange(edit.operationKey, batch.at)
            if (restored != null) mealReceipt(restored)
            else receipt.copy(dayID = dayID, resultJSON = coachJSON(Deleted.serializer(), Deleted(mealID)))
        }
        is CoachManualEdit.Open -> receipt.copy(destination = edit.destination,
            resultJSON = coachJSON(Handoff.serializer(), Handoff(edit.destination)))
        is CoachManualEdit.Goals -> {
            val exact = exactGoal(edit.date)
            var value = exact ?: (effectiveGoal(edit.date) ?: GoalRecord(UUID.randomUUID(), edit.date, turn.captureTimeZoneID, 1, NutritionValues(), null, false))
                .copy(id = UUID.randomUUID(), effectiveLocalDate = edit.date, timeZoneID = turn.captureTimeZoneID)
            value = value.copy(targets = edit.targets.fold(value.targets) { targets, target -> targets.set(target) })
            if (edit.clearWeight) value = value.copy(goalWeightKg = null) else if (edit.weight != null) value = value.copy(goalWeightKg = edit.weight)
            if (edit.exerciseCredit != null) value = value.copy(exerciseCreditEnabled = edit.exerciseCredit)
            val saved = setGoal(value, exact?.revision)
            receipt.copy(goalID = saved.id, resultJSON = coachJSON(GoalRecord.serializer(), saved))
        }
        is CoachManualEdit.Preferences -> {
            val profile = head.profile.copy(timeZoneID = edit.timezone ?: head.profile.timeZoneID, preferences = edit.text ?: head.profile.preferences)
            updateProfile(profile, null)
            receipt.copy(resultJSON = coachJSON(PreferencesResult.serializer(), PreferencesResult(profile, (head.revision + 1).toInt())))
        }
    }
}

/** Food writes only: the meal's saved items before the change; empty for a new meal, whose undo deletes it. */
private fun DiaryDatabase.Tx.undoSnapshot(write: CoachWrite, turn: CoachTurn): List<FoodItem>? = when (write) {
    // A capture placeholder has no saved items; deleting it would strand its turn, so it gets no undo.
    is CoachWrite.Food -> turn.pendingMealID.let { id -> if (id == null) emptyList() else mealInfo(id).items.ifEmpty { null } }
    is CoachWrite.Correction -> mealInfo(write.mealID).items
    is CoachWrite.Manual -> when (val e = write.edit) {
        is CoachManualEdit.Item, is CoachManualEdit.Append, is CoachManualEdit.DeleteItem, is CoachManualEdit.ScaleMeal ->
            e.mealID?.let { mealInfo(it).items }
        else -> null
    }
    else -> null
}

internal fun DiaryDatabase.Tx.undoCoachChange(key: String, now: Instant): UUID? {
    if (isHeldDelete(key)) {
        when (deletedUndoState(key, now)) {
            CoachUndoState.Available -> {}
            CoachUndoState.Undone -> throw DiaryError.StaleRevision
            null -> throw DiaryError.UndoExpired
        }
        return (undoDeleted(key) as? Restored.Meal)?.id
    }
    val undo = coachUndo(key) ?: throw DiaryError.NotFound
    val meal = mealRecord(undo.mealID)
    if (undo.undone || undoState(meal) != undo.afterState) throw DiaryError.StaleRevision
    if (undo.before != null) save(commitSavedItems(meal, undo.before, undo.afterRevision)) else deleteMeal(undo.mealID)
    markUndone(key)
    return if (undo.before == null) null else undo.mealID
}
