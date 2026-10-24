package com.yakov103.mivu.diary

import java.security.MessageDigest
import java.text.BreakIterator
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.ResolverStyle
import java.util.TimeZone
import java.util.UUID

// One-to-one port of ios/Mivu/Diary/DiaryModels.swift (DiarySnapshot.validate and the validate* helpers) and the
// manifest checks in DiaryArchive.validate, with the same numeric limits.

sealed class DiaryError(message: String? = null) : Exception(message) {
    class InvalidData(val reason: String) : DiaryError(reason)
    object WrongOwner : DiaryError("wrong owner")
    object InvalidAmountUnitChange : DiaryError("Enter or clear each known nutrient when changing to an unrelated unit.")
    object StaleRevision : DiaryError("stale revision")
    object StaleArchive : DiaryError("stale archive")
    object NotFound : DiaryError("not found")
    object EmptyCapture : DiaryError("empty capture")
    object AmbiguousDay : DiaryError("ambiguous day") // the day changed since the target was prepared
    object QuotaExceeded : DiaryError("quota exceeded")
    object Busy : DiaryError("database busy") // another connection holds the write lock
}

private fun ok(condition: Boolean, reason: String) {
    if (!condition) throw DiaryError.InvalidData(reason)
}

// Swift String.count counts grapheme clusters; UTF-16 length is an upper bound, so only count when it could matter.
private fun String.graphemes(): Int {
    val it = BreakIterator.getCharacterInstance().also { it.setText(this) }
    var n = 0
    while (it.next() != BreakIterator.DONE) n++
    return n
}

internal fun String.atMost(limit: Int) = length <= limit || graphemes() <= limit
// Swift .whitespacesAndNewlines: Unicode Z* separators, U+0009-U+000D and U+0085 (not U+001C-U+001F).
private fun Char.swiftSpace() = code in 9..13 || code == 0x85 || Character.getType(this).toByte().let {
    it == Character.SPACE_SEPARATOR || it == Character.LINE_SEPARATOR || it == Character.PARAGRAPH_SEPARATOR
}
internal fun String.blankLikeSwift() = all { it.swiftSpace() }
private fun String.utf8Size() = toByteArray(Charsets.UTF_8).size
private fun <T> List<T>.unique() = toSet().size == size
private fun Double.finite() = !isNaN() && !isInfinite()
private fun Double?.inRange(low: Double, high: Double, lowInclusive: Boolean) =
    this == null || (finite() && (if (lowInclusive) this >= low else this > low) && this <= high)

// shortcut: Swift TimeZone(identifier:) also takes Foundation-only ids; java ids plus the legacy short ids
// (EST, GMT, UTC...) cover everything iOS writes. Revisit if a real archive uses another spelling.
internal fun validZone(id: String) =
    id in ZoneId.getAvailableZoneIds() || id in TimeZone.getAvailableIDs()

private val localDateFormat = DateTimeFormatter.ofPattern("uuuu-MM-dd").withResolverStyle(ResolverStyle.STRICT)

internal fun validLocalDate(value: String) = value.length == 10 &&
    runCatching {
        val date = LocalDate.parse(value, localDateFormat)
        date.year >= 1 && date.format(localDateFormat) == value // Swift's era-based yyyy rejects year 0
    }.getOrDefault(false)

private val hex64 = Regex("[0-9a-f]{64}")
internal fun fingerprint(text: String) = fingerprint(text.toByteArray(Charsets.UTF_8))
internal fun fingerprint(bytes: ByteArray) =
    MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }

internal fun validateItems(items: List<FoodItem>) {
    ok(items.size <= 200 && items.map { it.id }.unique(), "items")
    for (item in items) {
        val values = listOfNotNull(item.nutrition, item.nutritionBasis)
        ok(
            item.nutrientSources.keys.all { it in setOf("kcal", "carbs", "protein", "fat") } &&
                !item.name.blankLikeSwift() && item.name.atMost(500) &&
                item.quantity.finite() && item.quantity >= 0 && item.quantity <= 100_000 &&
                item.unit.isNotEmpty() && item.unit.atMost(100) && item.reference.atMost(2000) &&
                values.all { v -> listOf(v.kcal, v.carbs, v.protein, v.fat).all { it.inRange(0.0, 10_000_000.0, true) } },
            "item",
        )
    }
}

private fun validateMetadata(s: DiarySnapshot) {
    val p = s.profile
    ok(
        s.schemaVersion == 1 && s.revision >= 0 && s.revision < 10_000_000 &&
            !p.name.blankLikeSwift() && p.name.atMost(200) && p.language in setOf("en", "he") &&
            validZone(p.timeZoneID) && p.preferences.atMost(10_000) &&
            (p.about?.let { a ->
                a.heightCm in 50.0..272.0 && a.birthYear in 1900..2100 && a.dietTags.size <= 32 &&
                    a.dietTags.all { it.isNotEmpty() && it.atMost(60) } && a.healthNotes.atMost(2_000)
            } ?: true) &&
            (s.lineage?.let { it.isNotEmpty() && it.size <= 256 && it.unique() } ?: true),
        "metadata",
    )
    ok(
        s.goals.size <= 10_000 && s.goals.map { it.id }.unique() &&
            s.goals.map { it.effectiveLocalDate }.toSet().size == s.goals.size &&
            s.deletedWeightIDs.size <= 10_000 && s.deletedWeightIDs.unique() &&
            s.deletedWorkoutIDs.size <= 50_000 && s.deletedWorkoutIDs.unique(),
        "metadata collections",
    )
    for (g in s.goals) {
        ok(
            validLocalDate(g.effectiveLocalDate) && validZone(g.timeZoneID) && g.revision > 0 && g.revision < 1_000_000 &&
                listOf(g.targets.kcal, g.targets.carbs, g.targets.protein, g.targets.fat, g.goalWeightKg)
                    .all { it.inRange(0.0, 10_000_000.0, false) },
            "goal",
        )
    }
}

private fun validateSubmission(sub: MealSubmission, meal: DiaryMeal, profileId: UUID) {
    ok(
        sub.baseRevision >= 0 && sub.baseRevision <= meal.revision && sub.text.atMost(20_000) && sub.photoIDs.unique() &&
            (sub.state != SubmissionState.awaitingReview || sub.proposal != null),
        "submission",
    )
    sub.proposal?.let { p ->
        ok(
            p.schemaVersion == 1 && p.profileID == profileId && p.mealID == meal.id &&
                p.submissionID == sub.id && p.baseRevision == sub.baseRevision,
            "proposal",
        )
        validateItems(p.items)
    }
    sub.manualAcceptance?.let { a ->
        ok(meal.revision > sub.baseRevision, "manual acceptance revision")
        val p = sub.proposal
        ok(
            a.schemaVersion == 1 && sub.state == SubmissionState.saved && sub.photoIDs.isEmpty() && p != null &&
                p.schemaVersion == 1 && p.profileID == profileId && p.mealID == meal.id && p.submissionID == sub.id &&
                p.baseRevision == sub.baseRevision && a.enteredItemIDs == p.items.map { it.id } &&
                sub.baseRevision == (a.expectedMealRevision ?: 0),
            "manual acceptance",
        )
    }
}

internal fun validatePhoto(photo: MealPhoto) = ok(photo.data.size in 1..10_000_000, "photo bytes")

internal fun targetDay(t: ManualNutritionTarget) = when (t) {
    is ManualNutritionTarget.Recorded -> Triple(t.dayID, t.localDate, t.timeZoneID)
    is ManualNutritionTarget.Active -> Triple(t.dayID, t.localDate, t.timeZoneID)
    is ManualNutritionTarget.NewCurrent -> Triple(t.dayID, t.localDate, t.timeZoneID)
}

private fun validateReceipt(r: CoachReceipt, turnId: UUID, revision: Int, dayIds: Set<UUID>) {
    r.commandFingerprint?.let { ok(hex64.matches(it), "receipt fingerprint") }
    val key = "${turnId.toString().uppercase()}/update_preferences"
    ok(
        r.turnID == turnId && r.operationKey.utf8Size() <= 500 && r.operationKey.isNotEmpty() &&
            r.committedRevision > 0 && r.committedRevision <= revision && r.resultJSON.utf8Size() <= 65_536 &&
            (r.dayID != null || r.goalID != null || r.destination != null ||
                r.operationKey == key || r.operationKey.startsWith("$key/")) &&
            strictJsonContainer(r.resultJSON),
        "receipt",
    )
    ok(r.dayID == null || r.dayID in dayIds, "receipt day")
}

private fun validateTurn(turn: CoachTurn, s: DiarySnapshot, dayIds: Set<UUID>): Int {
    ok(
        turn.text.atMost(20_000) && validZone(turn.captureTimeZoneID) && turn.photoIDs.unique() && turn.photoIDs.size <= 30 &&
            (turn.assistantText?.let { it.utf8Size() <= 65_536 } ?: true) &&
            turn.receipts.size <= 16 && turn.receipts.map { it.operationKey }.toSet().size == turn.receipts.size &&
            (turn.pendingMealRevision?.let { it >= 0 } ?: true) &&
            (turn.submissionManifest?.reply?.let { it.excerpt.atMost(280) && !it.excerpt.blankLikeSwift() } ?: true),
        "coach turn",
    )
    ok(
        turn.photos.size <= 30 && turn.photos.map { it.id }.unique() &&
            (turn.activeDayID == null || turn.activeDayID in dayIds) &&
            (turn.resolvedDayID == null || turn.resolvedDayID in dayIds) &&
            turn.photos.all { it.id in turn.photoIDs },
        "coach turn links",
    )
    turn.photos.forEach(::validatePhoto)
    for (id in turn.photoIDs) {
        ok(
            turn.photos.any { it.id == id } || s.meals.any { m ->
                (m.id == turn.pendingMealID || turn.receipts.any { it.mealID == m.id }) && m.photos.any { it.id == id }
            },
            "coach photo reference",
        )
    }
    for (r in turn.receipts) validateReceipt(r, turn.id, s.revision, dayIds)
    return turn.photos.sumOf { it.data.size }
}

// Foundation's JSONSerialization: strict RFC 8259 with an object or array at the top level.
// kotlinx parseToJsonElement is lenient (unquoted tokens, NaN), so check the grammar here.
private val jsonNumber = Regex("-?(0|[1-9][0-9]*)(\\.[0-9]+)?([eE][+-]?[0-9]+)?")

internal fun strictJsonContainer(text: String): Boolean {
    var i = 0
    fun ws() { while (i < text.length && text[i] in " \t\n\r") i++ }
    fun lit(w: String) = text.startsWith(w, i).also { if (it) i += w.length }
    fun str(): Boolean {
        if (text.getOrNull(i) != '"') return false
        i++
        while (i < text.length) {
            val c = text[i++]
            when {
                c == '"' -> return true
                c < ' ' -> return false
                c == '\\' -> {
                    val e = text.getOrNull(i++) ?: return false
                    if (e == 'u') { if (i + 4 > text.length || !text.substring(i, i + 4).all { it in "0123456789abcdefABCDEF" }) return false; i += 4 }
                    else if (e !in "\"\\/bfnrt") return false
                }
            }
        }
        return false
    }
    fun value(depth: Int): Boolean {
        if (depth > 512) return false // JSONSerialization's nesting cap; also bounds recursion
        ws()
        val c = text.getOrNull(i) ?: return false
        val ok = when {
            c == '"' -> str()
            c == '{' -> {
                i++; ws()
                if (text.getOrNull(i) == '}') { i++; true } else {
                    var good = true
                    while (good) {
                        ws(); good = str(); if (!good) break
                        ws(); good = text.getOrNull(i++) == ':' && value(depth + 1); if (!good) break
                        ws(); val d = text.getOrNull(i++)
                        if (d == '}') break
                        good = d == ','
                    }
                    good
                }
            }
            c == '[' -> {
                i++; ws()
                if (text.getOrNull(i) == ']') { i++; true } else {
                    var good = true
                    while (good) {
                        good = value(depth + 1); if (!good) break
                        ws(); val d = text.getOrNull(i++)
                        if (d == ']') break
                        good = d == ','
                    }
                    good
                }
            }
            lit("true") || lit("false") || lit("null") -> true
            else -> jsonNumber.matchAt(text, i)?.also { i = it.range.last + 1 } != null
        }
        return ok
    }
    ws()
    if (text.getOrNull(i) != '{' && text.getOrNull(i) != '[') return false
    return value(1).also { ws() } && i == text.length
}

internal fun validateWeight(w: WeightEntry) = ok(
    w.value.finite() && w.value > 0 && w.value <= 1500 && w.unit in setOf("kg", "lb") && w.revision > 0 && w.revision < 1_000_000,
    "weight",
)

internal fun validateWorkout(w: WorkoutSession) {
    ok(
        w.revision > 0 && w.revision < 1_000_000 && w.durationMinutes in 1..1440 && w.exercises.size <= 100 &&
            w.estimatedBurnKcal.inRange(0.0, 100_000.0, true) && (w.burnSource == null || w.estimatedBurnKcal != null),
        "workout",
    )
    for (e in w.exercises) {
        ok(!e.name.blankLikeSwift() && e.name.atMost(200) && e.sets.size <= 100, "exercise")
        for (set in e.sets) ok(set.repetitions in 1..10_000 && set.loadKg.inRange(0.0, 100_000.0, true), "set")
    }
}

fun DiarySnapshot.validate() {
    validateMetadata(this)
    val dayIds = days.map { it.id }.toSet()
    ok(
        days.size <= 10_000 && meals.size <= 50_000 && weights.size <= 10_000 && workouts.size <= 50_000 &&
            deletedMealIDs.size <= 50_000 &&
            days.map { it.id }.unique() && meals.map { it.id }.unique() && weights.map { it.id }.unique() &&
            weights.mapNotNull { it.dayID }.unique() && workouts.map { it.id }.unique() && deletedMealIDs.unique() &&
            (activeDayID == null || activeDayID in dayIds) &&
            meals.none { it.id in deletedMealIDs } && weights.none { it.id in deletedWeightIDs } &&
            workouts.none { it.id in deletedWorkoutIDs },
        "collections",
    )
    var photoBytes = 0L
    val submissionIds = HashSet<UUID>()
    for (day in days) {
        ok(validLocalDate(day.localDate) && validZone(day.timeZoneID), "day")
    }
    for (meal in meals) {
        ok(meal.dayID in dayIds && meal.photos.size <= 30 && meal.submissions.size <= 1000 && meal.photos.map { it.id }.unique(), "meal")
        ok(meal.revision >= 0 && meal.revision < 1_000_000 && (meal.revision == 0 || meal.items.isNotEmpty()), "meal revision")
        validateItems(meal.items)
        for (photo in meal.photos) {
            validatePhoto(photo)
            photoBytes += photo.data.size
        }
        for (sub in meal.submissions) {
            ok(submissionIds.add(sub.id) && sub.photoIDs.all { id -> meal.photos.any { it.id == id } }, "submission photos")
            validateSubmission(sub, meal, profile.id)
            sub.manualAcceptance?.let { a ->
                val (id, date, zone) = targetDay(a.target)
                ok(days.any { it.id == id && it.localDate == date && it.timeZoneID == zone }, "manual acceptance day")
            }
        }
    }
    ok(coachTurns.size <= 10_000 && coachTurns.map { it.id }.unique(), "coach turns")
    for (turn in coachTurns) photoBytes += validateTurn(turn, this, dayIds)
    ok(photoBytes <= 250_000_000, "photo total")
    for (w in weights) {
        validateWeight(w)
        ok(w.dayID == null || w.dayID in dayIds, "weight day")
    }
    for (w in workouts) {
        validateWorkout(w)
        ok(w.dayID in dayIds, "workout day")
    }
}

/** The manifest checks of DiaryArchive.validate; validates the snapshot first, like DiaryArchive.validate. */
fun validateArchiveManifests(snapshot: DiarySnapshot) {
    snapshot.validate()
    for (turn in snapshot.coachTurns) {
        val m = turn.submissionManifest ?: continue
        ok(
            m.submissionID == turn.id && m.textFingerprint == fingerprint(turn.text) &&
                m.context.capturedAt == turn.capturedAt && m.context.timeZoneID == turn.captureTimeZoneID &&
                m.context.activeDayID == turn.activeDayID &&
                (m.context.activeConversationSegmentID == null || m.context.activeConversationSegmentID == turn.captureSegmentID) &&
                (m.pendingMealID == null) == (m.pendingMealRevision == null) &&
                (m.pendingMealRevision?.let { it >= 0 } ?: true) &&
                m.attachments.size <= 8 && m.attachments.map { it.id }.unique() &&
                m.attachments.all { hex64.matches(it.contentFingerprint) },
            "manifest",
        )
    }
}
