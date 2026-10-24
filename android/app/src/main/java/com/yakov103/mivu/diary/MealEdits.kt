package com.yakov103.mivu.diary

import java.time.Instant
import java.util.UUID

// Ports of iOS editItem, deleteItem, scaleMeal, deleteMealPhoto and moveMeal (DiaryDatabaseMealMutations.swift
// DiaryTransaction) with diaryCorrectedItem and diaryUnitConversion. Each runs at the current head, as iOS
// DiaryStore.pagedMutation; [expectedRevision] is the meal revision the caller saw.

private fun DiaryMeal.checkRevision(expected: Int?) {
    if (expected != null && expected != revision) throw DiaryError.StaleRevision
}

/** Replaces one food; with [reviewSubmissionID] it edits that pending review's proposal instead of the meal. */
fun DiaryDatabase.editItem(
    mealID: UUID, item: FoodItem, explicitNutrients: Set<String>, reviewSubmissionID: UUID? = null, expectedRevision: Int? = null,
) = atHead { tx ->
    val meal = tx.mealRecord(mealID)
    meal.checkRevision(expectedRevision)
    if (reviewSubmissionID != null) {
        val sub = meal.submission(reviewSubmissionID)
        val proposal = sub.proposal
        val index = proposal?.items?.indexOfFirst { it.id == item.id } ?: -1
        if (sub.state != SubmissionState.awaitingReview || proposal == null || index < 0) throw DiaryError.NotFound
        if (sub.baseRevision != meal.revision) throw DiaryError.StaleRevision
        val items = proposal.items.toMutableList().also { it[index] = diaryCorrectedItem(item, it[index], explicitNutrients) }
        validateItems(items)
        tx.save(meal.with(sub.copy(proposal = proposal.copy(items = items))))
        return@atHead
    }
    val index = meal.items.indexOfFirst { it.id == item.id }
    if (index < 0) throw DiaryError.NotFound
    val items = meal.items.toMutableList().also { it[index] = diaryCorrectedItem(item, it[index], explicitNutrients) }
    validateItems(items)
    tx.commitDirectEdit(meal, items, "Direct item edit")
}

fun DiaryDatabase.deleteItem(mealID: UUID, itemID: UUID, expectedRevision: Int) = atHead { tx ->
    val meal = tx.mealRecord(mealID)
    meal.checkRevision(expectedRevision)
    if (meal.items.none { it.id == itemID }) throw DiaryError.NotFound
    // A meal keeps at least one food; removing the last one is deleting the meal.
    if (meal.items.size <= 1) throw DiaryError.InvalidData("last item")
    meal.requireSaved()
    tx.commitDirectEdit(meal, meal.items.filter { it.id != itemID }, "Direct item delete")
}

/** Resizes every portion by one ratio so the foods with a known energy total [targetKcal]. */
fun DiaryDatabase.scaleMeal(mealID: UUID, targetKcal: Double, expectedRevision: Int) = atHead { tx ->
    val meal = tx.mealRecord(mealID)
    meal.checkRevision(expectedRevision)
    meal.requireSaved()
    val known = meal.items.mapNotNull { it.nutrition.kcal }.sum()
    if (known <= 0 || !targetKcal.isFinite()) throw DiaryError.InvalidData("scale")
    val ratio = targetKcal / known
    if (ratio !in 0.1..3.0) throw DiaryError.InvalidData("scale ratio")
    // Math.round is half-up; quantities are non-negative, so it matches Swift's schoolbook rounded().
    val scaled = meal.items.map { diaryCorrectedItem(it.copy(quantity = Math.round(it.quantity * ratio * 100) / 100.0), it, emptySet()) }
    validateItems(scaled)
    tx.commitDirectEdit(meal, scaled, "Direct meal scale")
}

/**
 * iOS `deleteMealPhoto`: removes one photo and keeps the meal. Coach turns using it drop the ID unless they still reach
 * it elsewhere; unsaved submissions naming it are cancelled. A photo already gone commits nothing.
 */
fun DiaryDatabase.deletePhoto(mealID: UUID, photoID: UUID) = atHead { tx ->
    val meal = tx.mealRecord(mealID)
    if (meal.photos.none { it.id == photoID }) return@atHead
    // Turns first: the meal write re-validates turns that still name the photo.
    for (row in tx.coachTurnsWithoutPhotos()) {
        if (photoID !in row.photoIDs || (row.pendingMealID != mealID && row.receipts.none { it.mealID == mealID })) continue
        val turn = tx.coachTurn(row.id) ?: throw DiaryError.InvalidData("coach turn")
        val stripped = tx.stripUnusedPhotoID(turn, photoID, mealID)
        if (stripped != turn) tx.putCoachTurn(stripped)
    }
    val submissions = meal.submissions.map { sub ->
        if (photoID !in sub.photoIDs) sub
        else (if (sub.state != SubmissionState.saved) sub.copy(state = SubmissionState.cancelled, proposal = null) else sub)
            .copy(photoIDs = sub.photoIDs - photoID)
    }
    tx.save(meal.copy(photos = meal.photos.filter { it.id != photoID }, submissions = submissions))
}

/** Moves a meal to [toDayID]; an [eatenAt] must fall on that day's date and makes the time exact. */
fun DiaryDatabase.moveMeal(
    mealID: UUID, toDayID: UUID, eatenAt: Instant? = null, expectedRevision: Int? = null, expectedDayID: UUID? = null,
) = atHead { tx ->
    val meal = tx.mealRecord(mealID)
    val day = tx.trackingDay(toDayID)
    meal.checkRevision(expectedRevision)
    if (expectedDayID != null && expectedDayID != meal.dayID) throw DiaryError.StaleRevision
    var moved = meal.copy(dayID = toDayID, changedRevision = (tx.head.revision + 1).toInt()) // iOS saveMeal
    if (eatenAt != null) {
        if (diaryDateLabel(eatenAt, day.timeZoneID) != day.localDate) throw DiaryError.InvalidData("eaten at")
        moved = moved.copy(eatenAt = eatenAt, timePrecision = MealTimePrecision.exact)
    }
    tx.save(moved)
}

private val NUTRIENTS = listOf<Pair<String, (NutritionValues) -> Double?>>(
    "kcal" to { it.kcal }, "carbs" to { it.carbs }, "protein" to { it.protein }, "fat" to { it.fat },
)

private fun NutritionValues.with(name: String, value: Double?) = when (name) {
    "kcal" -> copy(kcal = value)
    "carbs" -> copy(carbs = value)
    "protein" -> copy(protein = value)
    else -> copy(fat = value)
}

/**
 * iOS `diaryCorrectedItem`: nutrients not in [explicitNutrients] must be unchanged and are recomputed from the previous
 * per-unit basis for the new amount (converted between related units); explicit ones become the person's own values.
 */
internal fun diaryCorrectedItem(item: FoodItem, previous: FoodItem, explicitNutrients: Set<String>): FoodItem {
    validateItems(listOf(item))
    if (!NUTRIENTS.map { it.first }.containsAll(explicitNutrients)) throw DiaryError.InvalidData("nutrients")
    val conversion = diaryUnitConversion(previous.unit, item.unit)
    var nutrition = item.nutrition
    val sources = previous.nutrientSources.toMutableMap()
    var basis = NutritionValues()
    for ((name, field) in NUTRIENTS) {
        val explicit = name in explicitNutrients
        if (!explicit && field(item.nutrition) != field(previous.nutrition)) throw DiaryError.InvalidData("nutrient")
        val oldValue = field(previous.nutrition)
        val oldBasis = if (previous.quantity > 0) oldValue?.let { it / previous.quantity } else previous.nutritionBasis?.let(field)
        if (explicit) {
            sources[name] = NutritionProvenance.user
        } else {
            if (conversion == null) {
                if (oldValue != null) throw DiaryError.InvalidAmountUnitChange
                nutrition = nutrition.with(name, null)
                continue
            }
            val convertedBasis = oldBasis?.let { it * conversion }
            if (item.quantity > 0) {
                if (oldValue != null && convertedBasis == null) throw DiaryError.InvalidAmountUnitChange
                nutrition = nutrition.with(name, if (oldValue == null) null else convertedBasis?.let { it * item.quantity })
            } else {
                nutrition = nutrition.with(name, oldValue?.let { 0.0 })
                basis = basis.with(name, convertedBasis)
            }
            if (oldValue != null && explicitNutrients.isNotEmpty()) sources[name] = previous.nutrientSources[name] ?: previous.provenance
        }
        if (item.quantity > 0) basis = basis.with(name, field(nutrition)?.let { it / item.quantity })
    }
    return item.copy(
        nutrition = nutrition,
        nutrientSources = sources,
        nutritionBasis = basis,
        provenance = if (explicitNutrients.isEmpty()) previous.provenance else NutritionProvenance.user,
        reference = previous.reference,
        uncertain = previous.uncertain || sources.values.any { it == NutritionProvenance.sample || it == NutritionProvenance.estimate },
    )
}

private fun diaryUnitConversion(previous: String, edited: String): Double? {
    if (previous == edited) return 1.0
    fun unit(label: String): Pair<String, Double>? = when (label.trim().lowercase()) {
        "mg", "milligram", "milligrams" -> "mass" to 0.001
        "g", "gram", "grams" -> "mass" to 1.0
        "kg", "kilogram", "kilograms" -> "mass" to 1000.0
        "ml", "milliliter", "milliliters", "millilitre", "millilitres" -> "volume" to 1.0
        "l", "liter", "liters", "litre", "litres" -> "volume" to 1000.0
        else -> null
    }
    val from = unit(previous) ?: return null
    val to = unit(edited) ?: return null
    return if (from.first == to.first) to.second / from.second else null
}
