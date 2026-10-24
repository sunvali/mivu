package com.yakov103.mivu.diary

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID

// Ports of the DiaryTransaction progress store in ios/Mivu/Diary/DiaryDatabaseProgress.swift: weight(id:) :41,
// weight(on:) :46, workout(id:) :51, setWeight :74, createWorkout :84, exactGoal :91, setGoal :96, updateProfile :106,
// deleteWeight :112, deleteWorkout :117, goal(on:) (DiaryDatabaseMealMutations.swift:226) and diaryDateOnlyInstant :145, and
// the public DiaryStore operations of the same names (DiaryStore.swift:403-446, 569-573, 708), each one transaction at the
// current head; the per-record revisions guard the editor's view.

private const val DATE = "json_extract(CAST(payload AS TEXT), '$.effectiveLocalDate')"

/** iOS `diaryDateOnlyInstant`: noon of [date] in [zone]. */
internal fun diaryDateOnlyInstant(date: String, zone: String): Instant {
    if (!validLocalDate(date) || !validZone(zone)) throw DiaryError.InvalidData("date")
    return LocalDate.parse(date).atTime(12, 0).atZone(ZoneId.of(zone, ZoneId.SHORT_IDS)).toInstant()
}

internal fun DiaryDatabase.Tx.weight(id: UUID): WeightEntry =
    boundedRecords("weight", WeightEntry.serializer(), "id = ?", listOf(id.swift), "ordinal", 1).firstOrNull() ?: throw DiaryError.NotFound

internal fun DiaryDatabase.Tx.weightOn(dayID: UUID): WeightEntry? {
    val rows = boundedRecords("weight", WeightEntry.serializer(), "parent = ?", listOf(dayID.swift), "ordinal", 2)
    if (rows.size > 1) throw DiaryError.InvalidData("day weights")
    return rows.firstOrNull()
}

internal fun DiaryDatabase.Tx.workout(id: UUID): WorkoutSession =
    boundedRecords("workout", WorkoutSession.serializer(), "id = ?", listOf(id.swift), "ordinal", 1).firstOrNull() ?: throw DiaryError.NotFound

/**
 * Creates the day's weight (date-only time unless [measuredAt] is given) or updates it at [expectedRevision]; null means
 * none exists yet.
 */
internal fun DiaryDatabase.Tx.setWeight(
    dayID: UUID, value: Double, unit: String, expectedRevision: Int?, measuredAt: Instant? = null, precision: MealTimePrecision? = null,
): WeightEntry {
    val day = trackingDay(dayID)
    val previous = weightOn(dayID)
    if (previous?.revision != expectedRevision) throw DiaryError.StaleRevision
    var saved = previous?.copy(value = value, unit = unit, revision = previous.revision + 1)
        ?: WeightEntry(UUID.randomUUID(), dayID, diaryDateOnlyInstant(day.localDate, day.timeZoneID).stored, value, unit,
            timePrecision = MealTimePrecision.dateOnly)
    if (measuredAt != null) saved = saved.copy(measuredAt = measuredAt.stored)
    if (precision != null) saved = saved.copy(timePrecision = precision)
    putWeight(saved)
    return saved
}

internal fun DiaryDatabase.Tx.createWorkout(dayID: UUID, draft: WorkoutDraft): WorkoutSession {
    val day = trackingDay(dayID)
    val value = WorkoutSession(UUID.randomUUID(), dayID, diaryDateOnlyInstant(day.localDate, day.timeZoneID).stored, MealTimePrecision.dateOnly,
        1, draft.kind, draft.durationMinutes, draft.exercises, draft.estimatedBurnKcal, draft.burnSource)
    putWorkout(value)
    return value
}

internal fun DiaryDatabase.Tx.deleteWeight(id: UUID, revision: Int) {
    if (weight(id).revision != revision) throw DiaryError.StaleRevision
    delete(DiaryDatabase.Tombstone.weight, id)
}

// shortcut: iOS also strips photo copies from turns whose only surviving progress was this workout (record_source);
// Android has no record_source table yet, so those copies stay valid but kept. Port with record_source.
internal fun DiaryDatabase.Tx.deleteWorkout(id: UUID, revision: Int) {
    if (workout(id).revision != revision) throw DiaryError.StaleRevision
    delete(DiaryDatabase.Tombstone.workout, id)
}

internal fun DiaryDatabase.Tx.exactGoal(date: String): GoalRecord? {
    if (!validLocalDate(date)) throw DiaryError.InvalidData("date")
    return boundedRecords("goal", GoalRecord.serializer(), "$DATE = ?", listOf(date), "ordinal", 1).firstOrNull()
}

/** iOS `goal(on:)`: the goal in effect on [date]. */
internal fun DiaryDatabase.Tx.effectiveGoal(date: String): GoalRecord? =
    boundedRecords("goal", GoalRecord.serializer(), "$DATE <= ?", listOf(date), "$DATE DESC", 1).firstOrNull()

/** Saves [goal] for its date at [revision] (null: no exact goal yet); the stored revision advances by one. */
internal fun DiaryDatabase.Tx.setGoal(goal: GoalRecord, revision: Int?): GoalRecord {
    val previous = exactGoal(goal.effectiveLocalDate)
    if (previous?.revision != revision || (previous != null && previous.id != goal.id)) throw DiaryError.StaleRevision
    if (previous == null && goals().any { it.id == goal.id }) throw DiaryError.InvalidData("goal id")
    return goal.copy(revision = (previous?.revision ?: 0) + 1).also(::putGoal)
}

internal fun DiaryDatabase.Tx.updateProfile(profile: DiaryProfile, expectedProfile: DiaryProfile?) {
    if (profile.id != head.profile.id) throw DiaryError.WrongOwner
    if (expectedProfile != null && expectedProfile != head.profile) throw DiaryError.StaleRevision
    head = head.copy(profile = profile, previousDayConfirmedAt = if (profile.timeZoneID != head.profile.timeZoneID) null else head.previousDayConfirmedAt)
}

// Public operations for the Progress editors.

/** A weigh-in now: on a new waking day when [startNewDay], else on the active day, else unlinked to any day. */
fun DiaryDatabase.recordWeight(value: Double, unit: String = "kg", at: Instant = Instant.now(), startNewDay: Boolean = true): WeightEntry =
    transaction(null) { tx ->
        val dayID = if (startNewDay) tx.startDay(at).id else tx.head.activeDayID
        if (dayID != null) {
            tx.setWeight(dayID, value, unit, tx.weightOn(dayID)?.revision, at, MealTimePrecision.exact)
        } else {
            WeightEntry(UUID.randomUUID(), null, at.stored, value, unit).also(tx::putWeight)
        }
    }

fun DiaryDatabase.updateWeight(id: UUID, value: Double, expectedRevision: Int): WeightEntry = transaction(null) { tx ->
    val weight = tx.weight(id)
    if (weight.revision != expectedRevision) throw DiaryError.StaleRevision
    weight.copy(value = value, revision = weight.revision + 1).also(tx::putWeight)
}

fun DiaryDatabase.setWeight(dayID: UUID, value: Double, unit: String, expectedRevision: Int?): WeightEntry =
    transaction(null) { it.setWeight(dayID, value, unit, expectedRevision) }

fun DiaryDatabase.deleteWeight(id: UUID, expectedRevision: Int) = transaction(null) { it.deleteWeight(id, expectedRevision) }

/** A date-only workout on [localDate]'s day in the profile zone, created when that date has none. */
fun DiaryDatabase.createWorkout(localDate: String, draft: WorkoutDraft): WorkoutSession = transaction(null) { tx ->
    val zone = tx.head.profile.timeZoneID
    tx.createWorkout(tx.resolveDay(localDate, zone, diaryDateOnlyInstant(localDate, zone)).id, draft)
}

fun DiaryDatabase.createWorkout(dayID: UUID, draft: WorkoutDraft): WorkoutSession = transaction(null) { it.createWorkout(dayID, draft) }

/** Saves [session] at [expectedRevision]; it stays on its day, performed on that day's date. */
fun DiaryDatabase.updateWorkout(session: WorkoutSession, expectedRevision: Int): WorkoutSession = transaction(null) { tx ->
    val previous = tx.workout(session.id)
    val day = tx.trackingDay(session.dayID)
    if (previous.revision != expectedRevision) throw DiaryError.StaleRevision
    if (session.dayID != previous.dayID || diaryDateLabel(session.performedAt, day.timeZoneID) != day.localDate) throw DiaryError.InvalidData("workout day")
    session.copy(revision = previous.revision + 1).also(tx::putWorkout)
}

fun DiaryDatabase.deleteWorkout(id: UUID, expectedRevision: Int) = transaction(null) { it.deleteWorkout(id, expectedRevision) }

fun DiaryDatabase.setGoals(goal: GoalRecord, expectedRevision: Int?): GoalRecord = transaction(null) { it.setGoal(goal, expectedRevision) }

/** The goal in effect on [on], or with [exact] only one set for that very date. */
fun DiaryDatabase.goal(on: String, exact: Boolean = false): GoalRecord? = read { if (exact) it.exactGoal(on) else it.effectiveGoal(on) }

fun DiaryDatabase.updateProfile(profile: DiaryProfile, expectedProfile: DiaryProfile?) = transaction(null) { it.updateProfile(profile, expectedProfile) }
