package com.yakov103.mivu.diary

import java.time.Instant
import java.time.ZoneId
import java.util.UUID

// Ports of ios/Mivu/Diary/DiaryDatabaseMealMutations.swift (startDay, resolveDay, activateDay, newDayLabel,
// resolveDayChoices, diaryDateLabel, wakingDateLabel, DayCutoff) and dayAssignment (DiaryDatabaseManualNutrition.swift).

sealed interface DayAssignment {
    data class Existing(val id: UUID) : DayAssignment
    object NewDay : DayAssignment
}

// shortcut: iOS reads a per-device "dayStartHour" preference (default 4); Android has no day settings yet, so the
// default is fixed. Read the preference here once the settings screen exists.
const val DAY_CUTOFF_HOUR = 4

fun diaryDateLabel(at: Instant, zone: String): String = at.atZone(ZoneId.of(zone, ZoneId.SHORT_IDS)).toLocalDate().toString()

/** The waking day an instant belongs to: before the cutoff hour it still counts for the previous date. */
fun wakingDateLabel(at: Instant, zone: String, cutoffHour: Int = DAY_CUTOFF_HOUR) =
    diaryDateLabel(at.minusSeconds(cutoffHour * 3600L), zone)

/** The instant after its Swift Date (Double) round trip: the value a stored row reads back as. */
internal val Instant.stored: Instant get() = SwiftJson.decodeFromJsonElement(SwiftDate, SwiftJson.encodeToJsonElement(SwiftDate, this))

internal fun DiaryDatabase.Tx.trackingDay(id: UUID) = day(id) ?: throw DiaryError.NotFound

fun DiaryDatabase.startDay(at: Instant, expectedRevision: Long): TrackingDay = transaction(expectedRevision) { it.startDay(at) }

fun DiaryDatabase.dayAssignment(at: Instant): DayAssignment = read { it.dayAssignment(at) }

internal fun DiaryDatabase.Tx.startDay(at: Instant): TrackingDay {
    val day = resolveDay(newDayLabel(at), head.profile.timeZoneID, at)
    activateDay(day)
    resolveDayChoices(at, day.id)
    return day
}

internal fun DiaryDatabase.Tx.dayAssignment(at: Instant): DayAssignment {
    val id = head.activeDayID ?: return DayAssignment.NewDay
    // The active day holds until the cutoff passes; then the next activity starts a new day, so logging never asks.
    val day = trackingDay(id)
    val zone = head.profile.timeZoneID
    return if (day.timeZoneID == zone && day.localDate >= wakingDateLabel(at, zone)) DayAssignment.Existing(id) else DayAssignment.NewDay
}

/** The waking date, unless the active day already covers it: then an explicit start before the cutoff opens the calendar date. */
internal fun DiaryDatabase.Tx.newDayLabel(at: Instant): String {
    val zone = head.profile.timeZoneID
    val waking = wakingDateLabel(at, zone)
    val active = head.activeDayID?.let { trackingDay(it) }
    return if (active != null && active.localDate >= waking) diaryDateLabel(at, zone) else waking
}

internal fun DiaryDatabase.Tx.resolveDay(localDate: String, timeZoneID: String, at: Instant, newDayID: UUID? = null): TrackingDay {
    days().firstOrNull { it.localDate == localDate && it.timeZoneID == timeZoneID }?.let {
        if (newDayID != null && newDayID != it.id) throw DiaryError.InvalidData("day")
        return it
    }
    if (newDayID != null && day(newDayID) != null) throw DiaryError.InvalidData("day")
    return TrackingDay(newDayID ?: UUID.randomUUID(), localDate, timeZoneID, at.stored, DayCompleteness.unknown).also(::putDay)
}

internal fun DiaryDatabase.Tx.activateDay(day: TrackingDay) {
    if (day(day.id) != day) throw DiaryError.InvalidData("day")
    if (head.activeDayID != day.id) {
        // As iOS: the new conversation's ID is not the current one nor any indexed segment.
        var boundary = UUID.randomUUID()
        while (boundary == head.activeConversationSegmentID || coachSegmentExists(boundary)) boundary = UUID.randomUUID()
        head = head.copy(activeDayID = day.id, activeConversationSegmentID = boundary)
    }
    head = head.copy(previousDayConfirmedAt = null)
}

internal fun DiaryDatabase.Tx.resolveDayChoices(at: Instant, dayID: UUID) {
    for (row in coachTurnsWithoutPhotos()) {
        if (row.needsDayChoice != true || row.state != CoachTurnState.needsClarification) continue
        if (diaryDateLabel(row.capturedAt, row.captureTimeZoneID) == diaryDateLabel(at, row.captureTimeZoneID)) {
            val turn = coachTurn(row.id) ?: throw DiaryError.InvalidData("coach turn")
            putCoachTurn(turn.copy(resolvedDayID = dayID, needsDayChoice = null))
        }
    }
}
