@file:UseSerializers(SwiftDate::class, SwiftUUID::class)

package com.yakov103.mivu.coach

import com.yakov103.mivu.diary.CoachDestination
import com.yakov103.mivu.diary.CoachQuestion
import com.yakov103.mivu.diary.CoachReceipt
import com.yakov103.mivu.diary.CoachReply
import com.yakov103.mivu.diary.CoachTurn
import com.yakov103.mivu.diary.CoachTurnState
import com.yakov103.mivu.diary.DiaryDatabase
import com.yakov103.mivu.diary.DiaryError
import com.yakov103.mivu.diary.DiaryMeal
import com.yakov103.mivu.diary.DiaryProfile
import com.yakov103.mivu.diary.FoodItem
import com.yakov103.mivu.diary.GoalRecord
import com.yakov103.mivu.diary.MealTimePrecision
import com.yakov103.mivu.diary.NutritionProvenance
import com.yakov103.mivu.diary.NutritionValues
import com.yakov103.mivu.diary.PhotoRole
import com.yakov103.mivu.diary.SubmissionState
import com.yakov103.mivu.diary.SwiftDate
import com.yakov103.mivu.diary.SwiftJson
import com.yakov103.mivu.diary.SwiftUUID
import com.yakov103.mivu.diary.TrackingDay
import com.yakov103.mivu.diary.WeightEntry
import com.yakov103.mivu.diary.WorkoutKind
import com.yakov103.mivu.diary.WorkoutSession
import com.yakov103.mivu.diary.blankLikeSwift
import com.yakov103.mivu.diary.diaryDateLabel
import com.yakov103.mivu.diary.trackingDay
import com.yakov103.mivu.diary.validLocalDate
import com.yakov103.mivu.diary.validateItems
import java.time.Instant
import java.util.UUID
import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.UseSerializers
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject

// Ports of CoachContext, includeCommittedReceipts, coachJSON and WorkoutReference (ios/Mivu/Coach/CoachModels.swift:189-290),
// CoachCommittedReceipt/Item (CoachTimelineModels.swift:14), coachCommittedReceipt (DiaryDatabaseQueries.swift:305),
// coachInferenceContext and its helpers (DiaryDatabaseCoachContext.swift:128-260, :392) and
// CoachEngine.historyMessages (CoachEngine.swift:224). Every read is bounded; nothing reads the whole diary.

@Serializable
data class CoachContext(
    val profile: DiaryProfile,
    val capturedAt: Instant,
    val captureTimeZoneID: String,
    val activeDayID: UUID? = null,
    val days: List<TrackingDay>,
    val meals: List<Meal>,
    val weights: List<WeightEntry>,
    val recentTurns: List<Turn>,
    val goal: GoalRecord? = null,
    val workouts: List<WorkoutReference>? = null,
    val omittedWorkoutCount: Int? = null,
    val omittedWeightCount: Int? = null,
    val pendingMealID: UUID? = null,
    val pendingMealRevision: Int? = null,
    val additionalMealCount: Int = 0,
    val omittedMeals: List<MealReference> = emptyList(),
    val truncated: Boolean = false,
    val diaryRevision: Int? = null,
    val preferencesTruncated: Boolean? = null,
    val attachedPhotoIDs: List<UUID>? = null,
    val committedReceipts: List<CoachCommittedReceipt>? = null,
    val omittedReceiptCount: Int? = null,
    /** What the person is replying to, resolved to current content for this turn only. */
    val replyTo: Reply? = null,
    /** Conversation focus for resolving "it"/"that"; null when nothing applies. */
    val focus: Focus? = null,
) {
    @Serializable
    data class Turn(val id: UUID, val capturedAt: Instant, val text: String, val assistantText: String? = null, val receipts: String? = null)

    @Serializable
    data class MealReference(val id: UUID, val dayID: UUID, val revision: Int, val itemCount: Int)

    @Serializable
    data class Meal(
        val id: UUID,
        val dayID: UUID,
        val revision: Int,
        val eatenAt: Instant,
        val timePrecision: MealTimePrecision? = null,
        val items: List<FoodItem>,
        val state: SubmissionState = SubmissionState.saved,
        val omittedItemCount: Int = 0,
        val photos: List<Photo>? = null,
        val review: Review? = null,
        val omittedPhotoCount: Int? = null,
    ) {
        @Serializable data class Photo(val id: UUID, val role: PhotoRole)
        @Serializable data class Review(val submissionID: UUID, val baseRevision: Int, val items: List<FoodItem>)
    }

    @Serializable
    data class Focus(val lastChanged: LastChanged? = null, val pendingQuestion: CoachQuestion? = null) {
        @Serializable data class LastChanged(val mealID: UUID, val itemNames: List<String>, val localDate: String, val revision: Int)
    }

    @Serializable
    data class Reply(
        val target: CoachReply.Target,
        val excerpt: String,
        val turn: Turn? = null,
        val meal: Meal? = null,
        val weight: WeightEntry? = null,
        val workout: WorkoutSession? = null,
        val unavailable: Boolean? = null,
    )
}

@Serializable
data class WorkoutReference(val id: UUID, val dayID: UUID, val localDate: String, val revision: Int, val kind: WorkoutKind, val durationMinutes: Int)

@Serializable
data class CoachCommittedItem(
    val itemID: UUID,
    val name: String,
    val quantity: Double,
    val unit: String,
    val nutrition: NutritionValues? = null,
    val provenance: NutritionProvenance? = null,
    val uncertain: Boolean? = null,
)

/** Committed linkage for presentation. Replay continues to use CoachReceipt. */
@Serializable
data class CoachCommittedReceipt(
    val operationKey: String,
    val turnID: UUID,
    val dayID: UUID? = null,
    val mealID: UUID? = null,
    val itemID: UUID? = null,
    val weightID: UUID? = null,
    val workoutID: UUID? = null,
    val goalID: UUID? = null,
    val destination: CoachDestination? = null,
    val committedRevision: Int,
    val targetLocalDate: String? = null,
    val items: List<CoachCommittedItem> = emptyList(),
    val submissionState: SubmissionState? = null,
    val weightValue: Double? = null,
    val weightUnit: String? = null,
    val workoutKind: String? = null,
    val workoutMinutes: Int? = null,
)

sealed class CoachError : Exception() {
    object InvalidTool : CoachError()
    object InvalidArguments : CoachError()
    object LimitExceeded : CoachError()
    /** A write whose diary port has not landed yet (weight, workout, goal and preference writes). */
    object NotImplemented : CoachError()
}

/** iOS `coachJSON`: sorted keys, at most 64 KiB. */
fun <T> coachJSON(serializer: KSerializer<T>, value: T): String {
    fun sorted(e: JsonElement): JsonElement = when (e) {
        is JsonObject -> JsonObject(e.mapValues { sorted(it.value) }.toSortedMap())
        is JsonArray -> JsonArray(e.map(::sorted))
        else -> e
    }
    val text = sorted(SwiftJson.encodeToJsonElement(serializer, value)).toString()
    if (text.toByteArray().size > 65_536) throw DiaryError.InvalidData("coach json")
    return text
}

/** At most [bytes] UTF-8 bytes, whole code points, with a trailing ellipsis when cut. */
fun coachBoundedText(value: String, bytes: Int): String {
    if (value.toByteArray().size <= bytes) return value
    val result = StringBuilder()
    var count = 3 // the ellipsis
    var i = 0
    while (i < value.length) {
        val point = value.codePointAt(i)
        val size = when { point < 0x80 -> 1; point < 0x800 -> 2; point < 0x10000 -> 3; else -> 4 }
        if (count + size > bytes) break
        result.appendCodePoint(point); count += size; i += Character.charCount(point)
    }
    return result.append("…").toString()
}

/** Earlier exchanges as chat messages; receipt ids let the model act on records it saved before. */
fun coachHistoryMessages(turns: List<CoachContext.Turn>): List<CoachInferenceInput> = turns.flatMap { turn ->
    val reply = listOfNotNull(turn.assistantText, turn.receipts).joinToString("\n")
    listOfNotNull(
        CoachInferenceInput.Message(CoachInferenceInput.Role.user, if (turn.text.blankLikeSwift()) "[photo]" else turn.text),
        if (reply.blankLikeSwift()) null else CoachInferenceInput.Message(CoachInferenceInput.Role.assistant, reply),
    )
}

fun DiaryDatabase.coachHistoryMessages(turnID: UUID): List<CoachInferenceInput> =
    coachHistoryMessages(coachInferenceContext(turnID).recentTurns)

fun DiaryDatabase.coachInferenceContext(turnID: UUID): CoachContext = read { it.coachInferenceContext(turnID) }

internal fun DiaryDatabase.Tx.coachInferenceContext(turnID: UUID): CoachContext {
    val work = coachTurnWithoutPhotos(turnID) ?: throw DiaryError.NotFound
    val sequence = query("SELECT ordinal FROM coach_turn WHERE id = ?", listOf(turnID.key)) { it.moveToFirst(); it.getLong(0) }
    val profile = head.profile.copy(name = coachBoundedText(head.profile.name, 512), preferences = coachBoundedText(head.profile.preferences, 8192))
    val previous = boundedRecords("coach_turn", CoachTurn.serializer(), "ordinal < ?", listOf(sequence.toString()), "ordinal DESC", 12)
    // Only the immediately previous turn; bounded for the 60 KB cap.
    val pendingQuestion = previous.firstOrNull()?.takeIf { it.state == CoachTurnState.completed }
        ?.let { t -> t.question?.copy(originalText = coachBoundedText(t.text, 1024)) }
    val recent = previous.reversed().map { it.contextTurn() }.toMutableList()
    while (size(ListSerializer(CoachContext.Turn.serializer()), recent) > 8192) recent.removeAt(0)
    val days = boundedRecords("day", TrackingDay.serializer(), null, emptyList(), "ordinal DESC, id DESC", 14).reversed()
    val activeDayID = work.resolvedDayID ?: work.activeDayID
    val date = diaryDateLabel(work.capturedAt, work.captureTimeZoneID)
    val goal = boundedRecords("goal", GoalRecord.serializer(), "json_extract(CAST(payload AS TEXT), '$.effectiveLocalDate') <= ?",
        listOf(date), "json_extract(CAST(payload AS TEXT), '$.effectiveLocalDate') DESC", 1).firstOrNull()

    val meals = mutableListOf<CoachContext.Meal>()
    val omittedMeals = mutableListOf<CoachContext.MealReference>()
    var additionalMealCount = 0
    if (days.isNotEmpty()) {
        val ids = days.map { it.id.key }
        val placeholders = ids.joinToString(",") { "?" }
        additionalMealCount = maxOf(0, count("SELECT COUNT(*) FROM meal WHERE parent IN ($placeholders)", ids) - 40)
        val mealIDs = ids("SELECT id FROM meal WHERE parent IN ($placeholders) ORDER BY ordinal DESC, id DESC LIMIT 40", ids)
        for (id in mealIDs) {
            val meal = mealRow(id)
            val (itemCount, bytes) = query("SELECT COUNT(*), COALESCE(SUM(length(payload)),0) FROM item WHERE parent = ?", listOf(id.key)) {
                it.moveToFirst(); it.getInt(0) to it.getLong(1)
            }
            val omission = CoachContext.MealReference(id, meal.dayID, meal.revision, itemCount)
            if (bytes > 24_000) { omittedMeals += omission; continue }
            val raw = query("SELECT json_extract(CAST(payload AS TEXT), '$.state') FROM submission WHERE parent = ? ORDER BY ordinal DESC, id DESC LIMIT 1",
                listOf(id.key)) { if (it.moveToFirst()) it.getString(0) else SubmissionState.saved.name }
            val state = SubmissionState.entries.firstOrNull { it.name == raw } ?: throw DiaryError.InvalidData("submission state")
            val projection = CoachContext.Meal(id, meal.dayID, meal.revision, meal.eatenAt, meal.timePrecision, mealItems(id), state)
            if (size(ListSerializer(CoachContext.Meal.serializer()), meals + projection) <= 24_000) meals += projection else omittedMeals += omission
        }
        meals.reverse()
    }

    val lastChanged = activeDayID?.let { day ->
        ids("SELECT id FROM meal WHERE parent = ? AND json_extract(CAST(payload AS TEXT), '$.revision') > 0 AND " +
            "json_extract(CAST(payload AS TEXT), '$.changedRevision') IS NOT NULL ORDER BY json_extract(CAST(payload AS TEXT), '$.changedRevision') DESC LIMIT 1",
            listOf(day.key)).firstOrNull()?.let { id ->
            // Bounded: a meal can hold hundreds of long names.
            CoachContext.Focus.LastChanged(id, mealItems(id).take(8).map { coachBoundedText(it.name, 64) }, trackingDay(day).localDate, mealRow(id).revision)
        }
    }
    val focus = if (lastChanged != null || pendingQuestion != null) CoachContext.Focus(lastChanged, pendingQuestion) else null

    val weightRows = boundedRecords("weight", WeightEntry.serializer(), null, emptyList(), "ordinal DESC, id DESC", 41)
    val workoutRows = query("SELECT w.id, w.parent, json_extract(CAST(w.payload AS TEXT), '$.revision'), json_extract(CAST(w.payload AS TEXT), '$.kind'), " +
        "json_extract(CAST(w.payload AS TEXT), '$.durationMinutes') FROM workout w ORDER BY w.ordinal DESC, w.id DESC LIMIT 101", emptyList()) { c ->
        buildList { while (c.moveToNext()) add(listOf(c.getString(0), c.getString(1), c.getString(2), c.getString(3), c.getString(4))) }
    }
    val workouts = workoutRows.take(100).map { (id, dayID, revision, kind, minutes) ->
        val day = uuid(dayID)
        WorkoutReference(uuid(id), day, trackingDay(day).localDate, revision?.toIntOrNull() ?: throw DiaryError.InvalidData("workout"),
            WorkoutKind.entries.firstOrNull { it.name == kind } ?: throw DiaryError.InvalidData("workout"),
            minutes?.toIntOrNull() ?: throw DiaryError.InvalidData("workout"))
    }.reversed()

    val receipts = work.receipts.map(::coachCommittedReceipt)
    val committed = mutableListOf<CoachCommittedReceipt>()
    for (receipt in receipts) {
        if (size(ListSerializer(CoachCommittedReceipt.serializer()), committed + receipt) > 8192) break
        committed += receipt
    }
    val preferencesTruncated = profile.preferences != head.profile.preferences
    var context = CoachContext(profile, work.capturedAt, work.captureTimeZoneID, activeDayID, days, meals, weightRows.take(40).reversed(), recent,
        goal = goal, workouts = workouts, omittedWorkoutCount = maxOf(0, count("SELECT COUNT(*) FROM workout", emptyList()) - 100),
        omittedWeightCount = maxOf(0, count("SELECT COUNT(*) FROM weight", emptyList()) - 40),
        pendingMealID = work.pendingMealID, pendingMealRevision = work.pendingMealRevision, additionalMealCount = additionalMealCount,
        omittedMeals = omittedMeals,
        // iOS compares with sequence - 1; Android ordinals are contiguous, so that is the rows read.
        truncated = recent.size < previous.size || omittedMeals.isNotEmpty() || additionalMealCount > 0 || preferencesTruncated,
        diaryRevision = head.revision.toInt(), preferencesTruncated = preferencesTruncated,
        // shortcut: iOS lists the turn's resolved photo references; Android validates each ID resolves, so it lists the IDs.
        attachedPhotoIDs = work.photoIDs, committedReceipts = committed, omittedReceiptCount = receipts.size - committed.size,
        replyTo = work.submissionManifest?.reply?.let { replyContext(it) }, focus = focus)
    while (size(CoachContext.serializer(), context) > 60_000 && context.meals.isNotEmpty()) {
        val meal = context.meals.first()
        context = context.copy(meals = context.meals.drop(1),
            omittedMeals = context.omittedMeals + CoachContext.MealReference(meal.id, meal.dayID, meal.revision, meal.items.size), truncated = true)
    }
    while (size(CoachContext.serializer(), context) > 60_000 && context.workouts?.isNotEmpty() == true) {
        context = context.copy(workouts = context.workouts!!.drop(1), omittedWorkoutCount = (context.omittedWorkoutCount ?: 0) + 1, truncated = true)
    }
    if (size(CoachContext.serializer(), context) > 60_000) throw CoachError.LimitExceeded
    return context
}

/** One bounded read of what the turn quotes; missing records are explicit, never guessed. */
private fun DiaryDatabase.Tx.replyContext(reply: CoachReply): CoachContext.Reply {
    val value = CoachContext.Reply(reply.target, reply.excerpt)
    return try {
        when (val target = reply.target) {
            is CoachReply.Target.Message -> value.copy(turn = (coachTurnWithoutPhotos(target.turnID) ?: throw DiaryError.NotFound).contextTurn())
            is CoachReply.Target.Meal, is CoachReply.Target.Item -> {
                val mealID = if (target is CoachReply.Target.Item) target.mealID else (target as CoachReply.Target.Meal).mealID
                if (target is CoachReply.Target.Item && mealItems(mealID).none { it.id == target.itemID }) throw DiaryError.NotFound
                try {
                    val meal = coachMealDetail(mealID)
                    if (size(CoachContext.Meal.serializer(), meal) <= 8192) value.copy(meal = meal) else value
                } catch (_: CoachError.LimitExceeded) { value } // ids only; the model uses get_meal
            }
            is CoachReply.Target.Day -> value.also { trackingDay(target.dayID) }
            is CoachReply.Target.Weight -> value.copy(weight = byID("weight", WeightEntry.serializer(), target.weightID))
            is CoachReply.Target.Workout -> byID("workout", WorkoutSession.serializer(), target.workoutID)
                .let { if (size(WorkoutSession.serializer(), it) <= 8192) value.copy(workout = it) else value } // else ids only
        }
    } catch (e: DiaryError) {
        if (e != DiaryError.NotFound) throw e
        value.copy(unavailable = true)
    }
}

/** iOS `coachMealDetail`: one meal with as many items as fit, photo metadata and its pending review. */
internal fun DiaryDatabase.Tx.coachMealDetail(id: UUID): CoachContext.Meal {
    val meal = mealWithoutPhotoBytes(id) ?: throw DiaryError.NotFound
    var value = CoachContext.Meal(id, meal.dayID, meal.revision, meal.eatenAt, meal.timePrecision, emptyList(),
        meal.submissions.lastOrNull()?.state ?: SubmissionState.saved, meal.items.size)
    for (item in meal.items) {
        if (size(CoachContext.Meal.serializer(), value.copy(items = value.items + item)) > 48_000) break
        value = value.copy(items = value.items + item, omittedItemCount = value.omittedItemCount - 1)
    }
    val pending = meal.submissions.lastOrNull { it.state == SubmissionState.awaitingReview }
    value = value.copy(photos = meal.photos.map { CoachContext.Meal.Photo(it.id, it.role) }, omittedPhotoCount = 0,
        review = pending?.proposal?.let { CoachContext.Meal.Review(pending.id, it.baseRevision, it.items) })
    if (size(CoachContext.Meal.serializer(), value) > 60_000) throw CoachError.LimitExceeded
    return value
}

@Serializable
private data class ReceiptFacts(
    val id: UUID? = null,
    val mealID: UUID? = null,
    val dayID: UUID? = null,
    val localDate: String? = null,
    val effectiveLocalDate: String? = null,
    val targetLocalDate: String? = null,
    val state: SubmissionState? = null,
    val items: List<FoodItem>? = null,
    val item: FoodItem? = null,
    val value: Double? = null,
    val unit: String? = null,
    val kind: String? = null,
    val durationMinutes: Int? = null,
)

fun coachCommittedReceipt(receipt: CoachReceipt): CoachCommittedReceipt {
    var value = CoachCommittedReceipt(receipt.operationKey, receipt.turnID, receipt.dayID, receipt.mealID, receipt.itemID, receipt.weightID,
        receipt.workoutID, receipt.goalID, receipt.destination, receipt.committedRevision)
    val foodPrefix = receipt.turnID.key + "/food/"
    if (receipt.operationKey.startsWith(foodPrefix)) {
        val date = receipt.operationKey.removePrefix(foodPrefix)
        if (validLocalDate(date)) value = value.copy(targetLocalDate = date)
    }
    // Unrecognized legacy results remain replay authority without invented presentation facts.
    val facts = runCatching { SwiftJson.decodeFromString(ReceiptFacts.serializer(), receipt.resultJSON) }.getOrNull() ?: return value
    if (value.targetLocalDate == null && facts.targetLocalDate?.let(::validLocalDate) == true) value = value.copy(targetLocalDate = facts.targetLocalDate)
    if (receipt.dayID != null && facts.id == receipt.dayID && facts.localDate?.let(::validLocalDate) == true) value = value.copy(targetLocalDate = facts.localDate)
    if (receipt.goalID != null && facts.id == receipt.goalID && facts.effectiveLocalDate?.let(::validLocalDate) == true) {
        value = value.copy(targetLocalDate = facts.effectiveLocalDate)
    }
    value = value.copy(submissionState = facts.state)
    if (receipt.weightID != null && facts.id == receipt.weightID) value = value.copy(weightValue = facts.value, weightUnit = facts.unit)
    if (receipt.workoutID != null && facts.id == receipt.workoutID) value = value.copy(workoutKind = facts.kind, workoutMinutes = facts.durationMinutes)
    var items = emptyList<FoodItem>()
    if (facts.state == SubmissionState.saved || facts.state == SubmissionState.awaitingReview) {
        if (receipt.mealID != null && facts.id == receipt.mealID && facts.dayID == receipt.dayID) items = facts.items.orEmpty()
        if (receipt.mealID != null && facts.mealID == receipt.mealID && facts.item != null && facts.item.id == receipt.itemID) items = listOf(facts.item)
    }
    try { validateItems(items) } catch (_: DiaryError) { return value }
    return value.copy(items = items.map { CoachCommittedItem(it.id, it.name, it.quantity, it.unit, it.nutrition, it.provenance, it.uncertain) })
}

private fun receiptLine(receipts: List<CoachReceipt>): String? {
    val parts = receipts.mapNotNull { r ->
        if (r.mealID == null && r.itemID == null) null
        else "saved key=${r.operationKey}" + (r.mealID?.let { " meal=${it.key}" } ?: "") + (r.itemID?.let { " item=${it.key}" } ?: "")
    }
    return if (parts.isEmpty()) null else coachBoundedText("[" + parts.joinToString("; ") + "]", 1024)
}

private fun CoachTurn.contextTurn() = CoachContext.Turn(id, capturedAt, coachBoundedText(text, 1024),
    assistantText?.let { coachBoundedText(it, 1024) }, receiptLine(receipts))

private fun DiaryDatabase.Tx.mealRow(id: UUID): DiaryMeal =
    boundedRecords("meal", DiaryMeal.serializer(), "id = ?", listOf(id.key), "ordinal", 1).firstOrNull() ?: throw DiaryError.NotFound

private fun DiaryDatabase.Tx.mealItems(id: UUID): List<FoodItem> =
    boundedRecords("item", FoodItem.serializer(), "parent = ?", listOf(id.key), "ordinal", 201)

private fun <T> DiaryDatabase.Tx.byID(table: String, serializer: KSerializer<T>, id: UUID): T =
    boundedRecords(table, serializer, "id = ?", listOf(id.key), "ordinal", 1).firstOrNull() ?: throw DiaryError.NotFound

private fun DiaryDatabase.Tx.count(sql: String, args: List<String>) = query(sql, args) { it.moveToFirst(); it.getInt(0) }

private fun DiaryDatabase.Tx.ids(sql: String, args: List<String>): List<UUID> =
    query(sql, args) { c -> buildList { while (c.moveToNext()) add(c.getString(0)) } }.map(::uuid)

private fun uuid(text: String?): UUID = runCatching { UUID.fromString(text) }.getOrElse { throw DiaryError.InvalidData("coach context id") }

private fun <T> size(serializer: KSerializer<T>, value: T) = SwiftJson.encodeToString(serializer, value).toByteArray().size

private val UUID.key get() = toString().uppercase()
