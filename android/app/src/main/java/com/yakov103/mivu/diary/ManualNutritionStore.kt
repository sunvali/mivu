package com.yakov103.mivu.diary

import java.time.Instant
import java.util.UUID
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.JsonArray

// Ports of ios/Mivu/Diary/ManualNutrition.swift (payload, validation, fingerprint, acceptance) and
// DiaryDatabaseManualNutrition.swift (saveManualNutrition, prepareManualNutritionTarget, manualNutritionResult,
// manualDay, manualRecordedDay, resolveManualNutritionDay). A retry with the same payload returns the saved meal;
// a changed payload under the same submission ID is rejected.

sealed interface ManualNutritionDayChoice {
    object Current : ManualNutritionDayChoice
    object NewCurrent : ManualNutritionDayChoice
    data class Recorded(val dayID: UUID) : ManualNutritionDayChoice
}

data class ManualNutritionPayload(
    val profileID: UUID,
    val mealID: UUID,
    val submissionID: UUID,
    val operation: ManualNutritionOperation,
    val target: ManualNutritionTarget,
    val capturedAt: Instant,
    val eatenAt: Instant,
    val timePrecision: MealTimePrecision,
    val expectedMealRevision: Int?,
    val items: List<FoodItem>,
)

data class ManualNutritionSaveResult(
    val acceptance: ManualNutritionAcceptance,
    val submissionID: UUID,
    val meal: DiaryMeal,
    val replayed: Boolean,
)

internal fun validateManualNutritionPayload(p: ManualNutritionPayload) {
    validateItems(p.items)
    val (_, date, zone) = targetDay(p.target)
    if (p.items.isEmpty() || !p.items.all { it.quantity > 0 && with(it.nutrition) { listOf(kcal, carbs, protein, fat).any { v -> v != null } } } ||
        !validLocalDate(date) || !validZone(zone)
    ) throw DiaryError.InvalidData("manual nutrition")
    val revision = p.expectedMealRevision
    val ok = when (p.operation) {
        ManualNutritionOperation.create -> revision == null
        ManualNutritionOperation.append -> revision != null && revision > 0 && revision < 1_000_000
    }
    if (!ok) throw DiaryError.InvalidData("manual nutrition revision")
    val t = p.target
    if (t is ManualNutritionTarget.NewCurrent && t.dayID == t.previousActiveDayID) throw DiaryError.InvalidData("manual nutrition target")
}

private val Instant.referenceSeconds get() = (epochSecond - 978_307_200L) + nano / 1e9

// Swift Date is a Double: compare and return what the row will hold, so a sub-second retry still matches.
private fun ManualNutritionPayload.stored() = copy(capturedAt = capturedAt.stored, eatenAt = eatenAt.stored)

// shortcut: integral numbers print as Foundation's JSONSerialization does; non-integral ones use Kotlin's shortest form,
// which can differ in exponent spelling. The fingerprint is write-only (iOS `matches` compares fields), so it never locks out a retry.
private fun number(value: Double?): JsonElement = when {
    value == null -> JsonNull
    value == 0.0 -> JsonPrimitive(0)
    value % 1.0 == 0.0 && kotlin.math.abs(value) < 1e15 -> JsonPrimitive(value.toLong())
    else -> JsonPrimitive(value)
}

private fun obj(vararg fields: Pair<String, JsonElement>) = JsonObject(fields.toMap().toSortedMap())

private fun nutrition(v: NutritionValues) = obj("kcal" to number(v.kcal), "carbs" to number(v.carbs), "protein" to number(v.protein), "fat" to number(v.fat))

private fun String?.json(): JsonElement = this?.let(::JsonPrimitive) ?: JsonNull

internal fun manualNutritionFingerprint(p: ManualNutritionPayload): String {
    validateManualNutritionPayload(p)
    val (dayID, date, zone) = targetDay(p.target)
    val base = arrayOf("dayID" to JsonPrimitive(dayID.key), "localDate" to JsonPrimitive(date), "timeZoneID" to JsonPrimitive(zone))
    val target = when (val t = p.target) {
        is ManualNutritionTarget.Recorded -> obj(*base, "kind" to JsonPrimitive("recorded"))
        is ManualNutritionTarget.Active -> obj(*base, "kind" to JsonPrimitive("active"), "confirmPrevious" to JsonPrimitive(t.confirmPrevious))
        is ManualNutritionTarget.NewCurrent -> obj(*base, "kind" to JsonPrimitive("newCurrent"), "previousActiveDayID" to t.previousActiveDayID?.key.json())
    }
    val items = JsonArray(p.items.map { item ->
        obj("id" to JsonPrimitive(item.id.key), "name" to JsonPrimitive(item.name), "quantity" to number(item.quantity),
            "unit" to JsonPrimitive(item.unit), "nutrition" to nutrition(item.nutrition), "provenance" to JsonPrimitive(item.provenance.name),
            "reference" to JsonPrimitive(item.reference), "uncertain" to JsonPrimitive(item.uncertain),
            "nutrientSources" to JsonObject(item.nutrientSources.mapValues { JsonPrimitive(it.value.name) }.toSortedMap()),
            "nutritionBasis" to (item.nutritionBasis?.let(::nutrition) ?: JsonNull))
    })
    val json = obj("schemaVersion" to JsonPrimitive(1), "profileID" to JsonPrimitive(p.profileID.key),
        "mealID" to JsonPrimitive(p.mealID.key), "submissionID" to JsonPrimitive(p.submissionID.key),
        "operation" to JsonPrimitive(p.operation.name), "target" to target,
        "capturedAt" to number(p.capturedAt.referenceSeconds), "eatenAt" to number(p.eatenAt.referenceSeconds),
        "timePrecision" to JsonPrimitive(p.timePrecision.name),
        "expectedMealRevision" to (p.expectedMealRevision?.let(::JsonPrimitive) ?: JsonNull), "items" to items)
    return fingerprint(json.toString())
}

fun ManualNutritionAcceptance(payload: ManualNutritionPayload) = ManualNutritionAcceptance(1, payload.operation,
    manualNutritionFingerprint(payload), payload.target, payload.capturedAt, payload.eatenAt, payload.timePrecision,
    payload.expectedMealRevision, payload.items.map { it.id })

/** Compares stored fields directly; the fingerprint is write-only so a library change cannot lock out saved meals. */
internal fun ManualNutritionAcceptance.matches(p: ManualNutritionPayload, proposal: AnalysisOutput?) =
    operation == p.operation && target == p.target && capturedAt == p.capturedAt && eatenAt == p.eatenAt &&
        timePrecision == p.timePrecision && expectedMealRevision == p.expectedMealRevision &&
        enteredItemIDs == p.items.map { it.id } && proposal?.items == p.items

fun DiaryDatabase.saveManualNutrition(entered: ManualNutritionPayload, expectedRevision: Long): ManualNutritionSaveResult =
    transaction(expectedRevision) { tx ->
        val payload = entered.stored()
        tx.manualNutritionResult(payload)?.let { return@transaction it }
        val meal = when (payload.operation) {
            ManualNutritionOperation.create -> {
                val day = tx.resolveManualNutritionDay(payload.target, payload.capturedAt)
                DiaryMeal(payload.mealID, day.id, payload.capturedAt, payload.eatenAt, 0, (tx.head.revision + 1).toInt(),
                    payload.timePrecision, emptyList(), emptyList(), emptyList())
            }
            ManualNutritionOperation.append -> {
                val current = tx.meal(payload.mealID) ?: throw DiaryError.NotFound
                if (current.revision != payload.expectedMealRevision) throw DiaryError.StaleRevision
                val target = payload.target
                if (current.hasUnresolvedInput || target !is ManualNutritionTarget.Recorded || current.dayID != target.dayID ||
                    current.eatenAt != payload.eatenAt || (current.timePrecision ?: MealTimePrecision.exact) != payload.timePrecision
                ) throw DiaryError.InvalidData("manual append")
                tx.manualRecordedDay(target)
                current
            }
        }
        val saved = tx.commitSavedItems(meal, meal.items + payload.items, meal.revision)
        val acceptance = ManualNutritionAcceptance(payload)
        val proposal = AnalysisOutput(1, payload.profileID, meal.id, payload.submissionID, meal.revision, payload.items)
        val submission = MealSubmission(payload.submissionID, meal.revision, "Entered manually", emptyList(), false,
            SubmissionState.saved, proposal, acceptance)
        val result = saved.copy(submissions = saved.submissions + submission)
        tx.putMeal(result)
        ManualNutritionSaveResult(acceptance, payload.submissionID, tx.meal(result.id)!!, replayed = false)
    }

fun DiaryDatabase.prepareManualNutritionTarget(choice: ManualNutritionDayChoice, at: Instant): ManualNutritionTarget = read { tx ->
    if (choice is ManualNutritionDayChoice.Recorded) {
        val day = tx.trackingDay(choice.dayID)
        return@read ManualNutritionTarget.Recorded(day.id, day.localDate, day.timeZoneID)
    }
    val assignment = tx.dayAssignment(at)
    when {
        choice == ManualNutritionDayChoice.Current && assignment is DayAssignment.Existing -> {
            val day = tx.trackingDay(assignment.id)
            ManualNutritionTarget.Active(day.id, day.localDate, day.timeZoneID, confirmPrevious = false)
        }
        choice == ManualNutritionDayChoice.NewCurrent && assignment == DayAssignment.NewDay -> {
            val date = tx.newDayLabel(at)
            val zone = tx.head.profile.timeZoneID
            ManualNutritionTarget.NewCurrent(tx.manualDay(date, zone)?.id ?: UUID.randomUUID(), date, zone, tx.head.activeDayID)
        }
        else -> throw DiaryError.AmbiguousDay
    }
}

fun DiaryDatabase.manualNutritionResult(payload: ManualNutritionPayload): ManualNutritionSaveResult? =
    read { it.manualNutritionResult(payload.stored()) }

internal fun DiaryDatabase.Tx.manualNutritionResult(payload: ManualNutritionPayload): ManualNutritionSaveResult? {
    if (payload.profileID != head.profile.id) throw DiaryError.WrongOwner
    validateManualNutritionPayload(payload)
    if (isTombstoned(DiaryDatabase.Tombstone.meal, payload.mealID)) throw DiaryError.NotFound
    submissionParent(payload.submissionID)?.let { parent ->
        if (parent != payload.mealID) throw DiaryError.InvalidData("manual submission meal")
        val meal = meal(parent) ?: throw DiaryError.NotFound
        val submission = meal.submissions.first { it.id == payload.submissionID }
        val acceptance = submission.manualAcceptance
        if (acceptance == null || !acceptance.matches(payload, submission.proposal)) throw DiaryError.InvalidData("manual retry")
        manualRecordedDay(acceptance.target)
        return ManualNutritionSaveResult(acceptance, submission.id, meal, replayed = true)
    }
    if (coachTurn(payload.submissionID) != null) throw DiaryError.InvalidData("manual submission id")
    when (payload.operation) {
        ManualNutritionOperation.create -> if (meal(payload.mealID) != null) throw DiaryError.InvalidData("manual meal id")
        ManualNutritionOperation.append -> meal(payload.mealID) ?: throw DiaryError.NotFound
    }
    return null
}

internal fun DiaryDatabase.Tx.manualDay(localDate: String, timeZoneID: String): TrackingDay? {
    val matches = days().filter { it.localDate == localDate && it.timeZoneID == timeZoneID }
    if (matches.size > 1) throw DiaryError.InvalidData("duplicate day")
    return matches.firstOrNull()
}

internal fun DiaryDatabase.Tx.manualRecordedDay(target: ManualNutritionTarget): TrackingDay {
    val (id, date, zone) = targetDay(target)
    val day = trackingDay(id)
    if (day.localDate != date || day.timeZoneID != zone) throw DiaryError.InvalidData("manual day")
    return day
}

internal fun DiaryDatabase.Tx.resolveManualNutritionDay(target: ManualNutritionTarget, capturedAt: Instant): TrackingDay = when (target) {
    is ManualNutritionTarget.Recorded -> manualRecordedDay(target)
    is ManualNutritionTarget.Active -> manualRecordedDay(target).also {
        if (head.activeDayID != target.dayID || dayAssignment(capturedAt) != DayAssignment.Existing(target.dayID)) throw DiaryError.AmbiguousDay
    }
    is ManualNutritionTarget.NewCurrent -> {
        if (head.activeDayID != target.previousActiveDayID || target.timeZoneID != head.profile.timeZoneID ||
            target.localDate != newDayLabel(capturedAt) || head.activeDayID?.let { trackingDay(it).startAt <= capturedAt } == false ||
            dayAssignment(capturedAt) is DayAssignment.Existing
        ) throw DiaryError.AmbiguousDay
        resolveDay(target.localDate, target.timeZoneID, capturedAt, target.dayID).also {
            activateDay(it)
            resolveDayChoices(capturedAt, it.id)
        }
    }
}

private val UUID.key get() = toString().uppercase()
