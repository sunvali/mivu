package com.yakov103.mivu.diary

import com.yakov103.mivu.coach.CoachCommittedReceipt
import com.yakov103.mivu.coach.coachCommittedReceipt
import java.time.Instant
import java.util.UUID

// Port of the iOS Coach timeline reads: coachPage (DiaryDatabaseCoachTimeline), the receipt link and undo reads behind
// CoachViewModel.refreshLinks, retry (CoachViewModel.swift:534) and chooseCoachDay (DiaryDatabaseMealMutations.swift:172).
// Every read is bounded by `coach_turn.ordinal` and record IDs; no path decodes a whole DiarySnapshot.

sealed interface CoachPageRequest {
    data object Latest : CoachPageRequest
    data class Before(val ordinal: Long) : CoachPageRequest
    data class After(val ordinal: Long) : CoachPageRequest
    /** Rows with an ordinal in [from]...[to], for refreshing resident rows. */
    data class Range(val from: Long, val to: Long) : CoachPageRequest
    /** Opens history at the turn: up to nine earlier turns, the turn, then later ones; 20 in all when there are that many. */
    data class AroundTurn(val turnID: UUID) : CoachPageRequest
    /** As [AroundTurn], at the first turn of the day's first conversation; [DiaryError.NotFound] for a day without chat. */
    data class AtDay(val dayID: UUID) : CoachPageRequest
}

/** Current target availability, independent of the original committed receipt. */
sealed interface CoachReceiptTarget {
    data object Loading : CoachReceiptTarget
    data object Unavailable : CoachReceiptTarget
    data object Failed : CoachReceiptTarget
    data class Meal(val meal: DiaryMeal, val localDate: String) : CoachReceiptTarget
    data class Workout(val session: WorkoutSession, val localDate: String) : CoachReceiptTarget
}

/** Read from coach_undo; the committed receipt itself never changes. */
enum class CoachUndoState { Available, Undone }

/**
 * One exchange as the timeline shows it: [turn] has photo IDs but no photo rows (read bytes with [coachPhotoBytes]).
 * [targets] and [undo] are keyed by receipt operation key; an absent undo key means no undo is offered.
 */
data class CoachExchange(
    val turn: CoachTurn,
    val ordinal: Long,
    val receipts: List<CoachCommittedReceipt>,
    val targets: Map<String, CoachReceiptTarget>,
    val undo: Map<String, CoachUndoState>,
    val questionMeals: List<DiaryMeal>,
)

data class CoachPage(val exchanges: List<CoachExchange>, val hasEarlier: Boolean, val hasLater: Boolean)

/** One read transaction: at most [limit] exchanges, oldest first; one extra row tells whether the paged edge goes on. */
fun DiaryDatabase.coachPage(request: CoachPageRequest, limit: Int = 20): CoachPage = read { tx ->
    val (where, args, descending) = when (request) {
        CoachPageRequest.Latest -> Triple(null, emptyList<String>(), true)
        is CoachPageRequest.Before -> Triple("ordinal < ?", listOf(request.ordinal.toString()), true)
        is CoachPageRequest.After -> Triple("ordinal > ?", listOf(request.ordinal.toString()), false)
        is CoachPageRequest.Range -> Triple("ordinal BETWEEN ? AND ?", listOf(request.from.toString(), request.to.toString()), false)
        is CoachPageRequest.AroundTurn, is CoachPageRequest.AtDay ->
            Triple("ordinal >= ?", listOf(tx.coachWindowStart(request).toString()), false)
    }
    val sql = "SELECT id, ordinal FROM coach_turn${where?.let { " WHERE $it" } ?: ""} ORDER BY ordinal ${if (descending) "DESC" else "ASC"} LIMIT ${limit + 1}"
    val found = tx.query(sql, args) { c -> buildList { while (c.moveToNext()) add(c.getString(0) to c.getLong(1)) } }
    val more = found.size > limit
    val rows = found.take(limit).let { if (descending) it.reversed() else it }
    fun exists(clause: String, ordinal: Long) = tx.query("SELECT EXISTS(SELECT 1 FROM coach_turn WHERE ordinal $clause ?)", listOf(ordinal.toString())) {
        it.moveToFirst(); it.getInt(0) == 1
    }
    val earlier = if (descending) more else rows.firstOrNull()?.let { exists("<", it.second) } ?: false
    val later = if (descending) rows.lastOrNull()?.let { exists(">", it.second) } ?: false else more
    CoachPage(rows.map { (id, ordinal) -> tx.coachExchange(swiftUUID(id) ?: throw DiaryError.InvalidData("coach turn"), ordinal) }, earlier, later)
}

private fun DiaryDatabase.Tx.coachExchange(id: UUID, ordinal: Long): CoachExchange {
    val turn = coachTurnWithoutPhotos(id) ?: throw DiaryError.InvalidData("coach turn")
    val meals = mutableMapOf<UUID, DiaryMeal?>()
    fun meal(mealID: UUID) = meals.getOrPut(mealID) { mealWithoutPhotoBytes(mealID) }
    val targets = mutableMapOf<String, CoachReceiptTarget>()
    val undo = mutableMapOf<String, CoachUndoState>()
    for (receipt in turn.receipts) {
        val key = receipt.operationKey
        when {
            // A record whose day cannot be read shows as unavailable rather than failing the page.
            receipt.mealID != null -> targets[key] = meal(receipt.mealID)?.let { m -> day(m.dayID)?.let { CoachReceiptTarget.Meal(m, it.localDate) } }
                ?: CoachReceiptTarget.Unavailable
            receipt.workoutID != null -> targets[key] = try {
                workout(receipt.workoutID).let { w -> day(w.dayID)?.let { CoachReceiptTarget.Workout(w, it.localDate) } }
            } catch (_: DiaryError.NotFound) { null } ?: CoachReceiptTarget.Unavailable
        }
        val snapshot = coachUndo(key) ?: continue
        when {
            snapshot.undone -> undo[key] = CoachUndoState.Undone
            meal(snapshot.mealID)?.let { undoState(it) == snapshot.afterState } == true -> undo[key] = CoachUndoState.Available
        }
    }
    val questionMeals = turn.question?.candidates.orEmpty().mapNotNull {
        when (it) { is CoachReply.Target.Meal -> it.mealID; is CoachReply.Target.Item -> it.mealID; else -> null }
    }.distinct().take(4).mapNotNull(::meal)
    return CoachExchange(turn, ordinal, turn.receipts.map(::coachCommittedReceipt), targets, undo, questionMeals)
}

/** iOS `retry`: the person asks for the turn again; the worker picks it up as newly captured. */
fun DiaryDatabase.retryCoachTurn(turnID: UUID) = atHead { it.failCoachTurn(turnID, CoachTurnState.captured) }

/** iOS `chooseCoachDay` then `retry`: the turn is recorded on the previous (active-at-capture) day or the capture date. */
fun DiaryDatabase.chooseCoachDay(turnID: UUID, usePrevious: Boolean, at: Instant = Instant.now()) = atHead { tx ->
    val turn = tx.coachTurn(turnID) ?: throw DiaryError.NotFound
    if (turn.needsDayChoice != true) throw DiaryError.InvalidData("day choice")
    val day = if (usePrevious) tx.trackingDay(turn.activeDayID ?: throw DiaryError.NotFound) else {
        val date = diaryDateLabel(turn.capturedAt, turn.captureTimeZoneID)
        tx.resolveDay(date, turn.captureTimeZoneID, turn.capturedAt).also {
            if (diaryDateLabel(at, turn.captureTimeZoneID) == date) tx.activateDay(it)
        }
    }
    tx.putCoachTurn(turn.copy(resolvedDayID = day.id, needsDayChoice = null))
    tx.failCoachTurn(turnID, CoachTurnState.captured)
}
