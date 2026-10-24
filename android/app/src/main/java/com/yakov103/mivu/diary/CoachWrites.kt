@file:UseSerializers(SwiftUUID::class)

package com.yakov103.mivu.diary

import com.yakov103.mivu.coach.CoachContext
import com.yakov103.mivu.coach.CoachError
import com.yakov103.mivu.coach.CoachManualEdit
import com.yakov103.mivu.coach.CoachWrite
import com.yakov103.mivu.coach.coachJSON
import com.yakov103.mivu.coach.commandFingerprint
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID
import kotlinx.serialization.Serializable
import kotlinx.serialization.UseSerializers

// Port of ios/Mivu/Diary/DiaryDatabaseCoachMutations.swift: applyCoachWrites (:5), validateCoachWrites (:33-73),
// validateReplay (:88), validateCoachWrite (:112), coachDay (:182), addedCoachItems (:204), applyCoachWrite (:215),
// undoSnapshot/undoCoachChange (:301-346) and applyManual (:358). One batch is one transaction: all or nothing.
// Android has no record_source or photo_consumer tables: a turn reaches a photo through its own copy or a meal its
// pending meal or receipts link, so iOS `addSource` has no counterpart and photo transfers move copies.

private const val MAX_RECEIPTS = 16

/** Validates [writes] for [turnID] against the current diary without writing. */
fun DiaryDatabase.validateCoachWrites(turnID: UUID, writes: List<CoachWrite>, at: Instant = Instant.now()) {
    read { tx -> tx.validateCoachWrites(tx.coachTurnWithoutPhotos(turnID) ?: throw DiaryError.NotFound, writes, at) }
}

/** Applies the batch with one receipt per write; a write whose key already has a receipt returns it unchanged. */
fun DiaryDatabase.applyCoachWrites(turnID: UUID, writes: List<CoachWrite>, at: Instant = Instant.now()): List<CoachReceipt> =
    atHead { tx ->
        val turn = tx.coachTurn(turnID) ?: throw DiaryError.NotFound
        tx.validateCoachWrites(turn, writes, at)
        val batch = CoachBatch(turn, at)
        val results = mutableListOf<CoachReceipt>()
        for (write in writes) {
            val key = "${turnID.swift}/${write.target}"
            val prior = turn.receipts.firstOrNull { it.operationKey == key }
            if (prior != null) { results += prior; continue }
            val before = tx.undoSnapshot(write, turn)
            val receipt = tx.applyCoachWrite(write, batch).copy(operationKey = key, commandFingerprint = write.commandFingerprint())
            if (before != null && receipt.mealID != null) tx.saveUndo(key, turnID, receipt.mealID, before)
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

/** Restores the meal as the change left it only while nothing changed it since; never recreates a deleted meal. */
fun DiaryDatabase.undoCoachChange(operationKey: String): UUID? = atHead { it.undoCoachChange(operationKey) }

private class CoachBatch(val turn: CoachTurn, val at: Instant) {
    val added = mutableListOf<CoachReceipt>()
    /** Turn photo copies a meal now holds; the final turn save drops them. */
    val moved = mutableSetOf<UUID>()
}

@Serializable private data class Deleted(val id: UUID, val deleted: Boolean = true)
@Serializable private data class Queued(val queued: Boolean = true, val turnID: UUID)
@Serializable private data class Handoff(val destination: CoachDestination, val completed: Boolean = false)
@Serializable private data class CorrectionResult(val mealID: UUID, val targetLocalDate: String, val revision: Int, val state: SubmissionState, val item: FoodItem)

private val DiaryMeal.state get() = submissions.lastOrNull()?.state ?: SubmissionState.saved

private fun DiaryDatabase.Tx.mealInfo(id: UUID) = mealWithoutPhotoBytes(id) ?: throw DiaryError.NotFound

/** iOS `saveMeal` stamps the change revision. */
private fun DiaryDatabase.Tx.saveMeal(meal: DiaryMeal) = save(meal.copy(changedRevision = (head.revision + 1).toInt()))

private fun DiaryDatabase.Tx.mealResult(id: UUID): String {
    val m = mealInfo(id)
    return coachJSON(CoachContext.Meal.serializer(), CoachContext.Meal(m.id, m.dayID, m.revision, m.eatenAt, m.timePrecision, m.items, m.state))
}

/** iOS `diaryDateOnlyInstant`: noon of [date] in [zone]. */
private fun dateOnlyInstant(date: String, zone: String): Instant {
    if (!validLocalDate(date) || !validZone(zone)) throw DiaryError.InvalidData("date")
    return LocalDate.parse(date).atTime(12, 0).atZone(ZoneId.of(zone, ZoneId.SHORT_IDS)).toInstant()
}

internal fun DiaryDatabase.Tx.validateCoachWrites(turn: CoachTurn, writes: List<CoachWrite>, at: Instant) {
    if (writes.map { it.target }.toSet().size != writes.size) throw CoachError.InvalidArguments
    // shortcut: iOS first resolves a dated weight to a correction of the existing entry (resolvedWeightWrite); weight
    // writes are refused below until the weight port lands, so the targets are already final.
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
            newCount++
            validateCoachWrite(write, turn, at)
        }
    }
    if (turn.receipts.size + newCount > MAX_RECEIPTS) throw CoachError.LimitExceeded
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
            dateOnlyInstant(write.date, zone)
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
        is CoachWrite.Close -> dateOnlyInstant(write.date, zone)
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
                dateOnlyInstant(e.date, zone)
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
            is CoachManualEdit.Coverage -> dateOnlyInstant(e.date, zone)
            is CoachManualEdit.Undo -> {
                val undo = coachUndo(e.operationKey) ?: throw CoachError.InvalidArguments
                if (undo.undone || undoState(mealInfo(undo.mealID)) != undo.afterState) throw DiaryError.StaleRevision
            }
            is CoachManualEdit.Open -> {}
            // shortcut: goal and preference writes throw until their port lands (plan 4a task 4 part B).
            is CoachManualEdit.Goals, is CoachManualEdit.Preferences -> throw CoachError.NotImplemented
        }
        // shortcut: weight and workout writes throw until their port lands (plan 4a task 4 part B).
        is CoachWrite.Weight, is CoachWrite.CorrectWeight, is CoachWrite.Workout, is CoachWrite.EditWorkout,
        is CoachWrite.DeleteWeight, is CoachWrite.DeleteWorkout -> throw CoachError.NotImplemented
    }
}

/** iOS `coachDay`: the tracking day a Coach write for [date] lands on, from the turn's persisted capture clock. */
private fun DiaryDatabase.Tx.coachDay(date: String, turn: CoachTurn, activateIfEmpty: Boolean = true, exact: Boolean = false): TrackingDay {
    val zone = turn.captureTimeZoneID
    val noon = dateOnlyInstant(date, zone)
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
            // The turn's own photo copies move into the meal; the receipt links them for the turn.
            val photos = turn.photos.filter { it.id !in batch.moved }
            saveMeal(meal.copy(photos = meal.photos + photos))
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
        // shortcut: refused in validateCoachWrite until the weight and workout port (plan 4a task 4 part B).
        is CoachWrite.Weight, is CoachWrite.CorrectWeight, is CoachWrite.Workout, is CoachWrite.EditWorkout,
        is CoachWrite.DeleteWeight, is CoachWrite.DeleteWorkout -> throw CoachError.NotImplemented
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
        is CoachManualEdit.Undo -> {
            val mealID = coachUndo(edit.operationKey)?.mealID ?: throw DiaryError.NotFound
            val dayID = mealInfo(mealID).dayID
            val restored = undoCoachChange(edit.operationKey)
            if (restored != null) mealReceipt(restored)
            else receipt.copy(dayID = dayID, resultJSON = coachJSON(Deleted.serializer(), Deleted(mealID)))
        }
        is CoachManualEdit.Open -> receipt.copy(destination = edit.destination,
            resultJSON = coachJSON(Handoff.serializer(), Handoff(edit.destination)))
        // shortcut: refused in validateCoachWrite until the goal and preference port (plan 4a task 4 part B).
        is CoachManualEdit.Goals, is CoachManualEdit.Preferences -> throw CoachError.NotImplemented
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

internal fun DiaryDatabase.Tx.undoCoachChange(key: String): UUID? {
    val undo = coachUndo(key) ?: throw DiaryError.NotFound
    val meal = mealRecord(undo.mealID)
    if (undo.undone || undoState(meal) != undo.afterState) throw DiaryError.StaleRevision
    if (undo.before != null) save(commitSavedItems(meal, undo.before, undo.afterRevision)) else deleteMeal(undo.mealID)
    markUndone(key)
    return if (undo.before == null) null else undo.mealID
}
