package com.yakov103.mivu.coach

import com.yakov103.mivu.diary.CoachTurn
import com.yakov103.mivu.diary.CoachTurnState
import com.yakov103.mivu.diary.DayCompleteness
import com.yakov103.mivu.diary.DiaryDatabase
import com.yakov103.mivu.diary.DiaryError
import com.yakov103.mivu.diary.FoodItem
import com.yakov103.mivu.diary.GoalRecord
import com.yakov103.mivu.diary.SubmissionState
import com.yakov103.mivu.diary.SwiftJson
import com.yakov103.mivu.diary.WorkoutSession
import com.yakov103.mivu.diary.swift
import com.yakov103.mivu.diary.swiftUUID
import com.yakov103.mivu.diary.trackingDay
import com.yakov103.mivu.diary.weight
import com.yakov103.mivu.diary.workout
import java.math.BigDecimal
import java.math.RoundingMode
import java.text.DecimalFormat
import java.text.DecimalFormatSymbols
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.Locale
import java.util.UUID
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.sign
import kotlinx.serialization.Serializable

// Ports of ios/Mivu/Coach/CoachReplyLines.swift (factLine, progressLine, goalLine, dayLabel, shortDate, number) and
// DiaryDatabase.coachReceiptSummary (ios/Mivu/Diary/DiaryDatabaseQueries.swift:382-466).

/** Short app-written lines used when the model's prose cannot be shown. */
object CoachReplyLines {
    fun factLine(progress: List<CoachProgress>, goals: List<GoalRecord>, workouts: List<WorkoutSession>, preferencesRead: Boolean, today: String): String {
        val sentences = progress.map { progressLine(it, today) }.toMutableList()
        sentences += goals.mapNotNull(::goalLine)
        sentences += workouts.map { "${it.kind.name.replaceFirstChar(Char::uppercase)}, ${it.durationMinutes} minutes." }
        if (preferencesRead) sentences += "Your preferences are up to date."
        return if (sentences.isEmpty()) "I couldn't find anything to add there." else sentences.take(2).joinToString(" ")
    }

    private fun progressLine(progress: CoachProgress, today: String): String {
        val period = progress.period
        if (period != null && period.dayCount > 1) {
            val average = period.averageIntake.kcal ?: return "No finished days in the last ${period.dayCount} days yet."
            val tracked = period.knownIntakeSamples.kcal
            return "Last ${period.dayCount} days: about ${number(average, 10.0)} kcal a day on $tracked tracked ${if (tracked == 1) "day" else "days"}."
        }
        val daily = progress.daily
        val label = if (daily.localDate == today) "Today" else daily.localDate
        val eaten = daily.foodTotals?.kcal?.takeIf { it > 0 } ?: return "There's no food recorded for ${daily.localDate} yet."
        var line = "$label: ${number(eaten)}"
        daily.goal?.targets?.kcal?.let { line += " of ${number(it)}" }
        line += " kcal"
        daily.remainingFromRecorded.kcal?.let { line += if (it >= 0) ", about ${number(it, 10.0)} left" else ", about ${number(-it, 10.0)} over" }
        progress.weight.currentSevenDayAverageKg?.let { line += ". Weight average ${number(it)} kg" }
        return "$line."
    }

    private fun goalLine(goal: GoalRecord): String? {
        val kcal = goal.targets.kcal ?: return null
        return "Goal: ${number(kcal)} kcal a day" + (goal.targets.protein?.let { ", ${number(it)} g protein" } ?: "") + "."
    }

    enum class FollowUp { today, progress }

    /** iOS `followUps`: a completed turn that saved food offers Today; one that saved a weight offers Progress. */
    fun followUps(turn: CoachTurn): List<FollowUp> {
        if (turn.state != CoachTurnState.completed) return emptyList()
        return listOfNotNull(
            FollowUp.today.takeIf { turn.receipts.any { it.mealID != null } },
            FollowUp.progress.takeIf { turn.receipts.any { it.weightID != null && "/delete_weight/" !in it.operationKey } },
        )
    }

    /** "today", "yesterday" or a short date such as "Oct 17"; the year appears only when it differs. */
    fun dayLabel(localDate: String, today: String, locale: Locale = Locale.getDefault()): String {
        if (localDate == today) return "today"
        val day = date(localDate) ?: return localDate
        val now = date(today) ?: return localDate
        if (ChronoUnit.DAYS.between(day, now) == 1L) return "yesterday"
        val pattern = if (localDate.take(4) == today.take(4)) "MMM d" else "MMM d, yyyy"
        return day.format(DateTimeFormatter.ofPattern(pattern, locale))
    }

    fun shortDate(localDate: String, locale: Locale = Locale.getDefault()): String =
        date(localDate)?.format(DateTimeFormatter.ofPattern("MMM d", locale)) ?: localDate

    private fun date(localDate: String) = runCatching { LocalDate.parse(localDate) }.getOrNull()

    /** At most one fraction digit, US grouping; [step] rounds half away from zero first, like Swift `rounded()`. */
    fun number(value: Double, step: Double = 0.0): String {
        val shown = if (step > 0) swiftRounded(value / step) * step else value
        return DecimalFormat("#,##0.#", DecimalFormatSymbols(Locale.US)).apply { roundingMode = RoundingMode.HALF_EVEN }.format(shown)
    }
}

internal fun swiftRounded(value: Double) = sign(value) * floor(abs(value) + 0.5)

@Serializable private data class DeletedPhoto(val id: String)

/** iOS `coachReceiptSummary`: one short sentence per committed receipt of [turnID], from the diary as it is now. */
fun DiaryDatabase.coachCommittedSummary(turnID: UUID): String = read { tx ->
    val turn = tx.coachTurnWithoutPhotos(turnID) ?: throw DiaryError.NotFound
    val summaries = mutableListOf<String>()
    fun number(value: Double) = BigDecimal(value.toString()).stripTrailingZeros().toPlainString()
    fun known(items: List<FoodItem>) = swiftRounded(items.mapNotNull { it.nutrition.kcal }.sum()).toInt()
    for (receipt in turn.receipts) {
        val facts = coachCommittedReceipt(receipt)
        val undo = receipt.operationKey.indexOf("/undo/")
        if (undo >= 0) {
            // An undone log has no meal left, so its names come from the original receipt.
            val key = receipt.operationKey.substring(undo + "/undo/".length)
            val names = if (receipt.mealID != null) tx.mealWithoutPhotoBytes(receipt.mealID)?.items?.map { it.name }.orEmpty()
            else swiftUUID(key.take(36))?.let { tx.coachTurnWithoutPhotos(it) }?.receipts?.firstOrNull { it.operationKey == key }
                ?.let { coachCommittedReceipt(it).items.map { item -> item.name } }.orEmpty()
            val list = if (names.isEmpty()) "that meal" else names.joinToString(", ")
            summaries += if (receipt.mealID == null) "Removed $list." else "Undid the change to $list."
            continue
        }
        val key = receipt.operationKey
        when {
            receipt.mealID != null -> {
                val meal = tx.mealWithoutPhotoBytes(receipt.mealID)
                if (meal == null) { summaries += "This meal was deleted."; continue }
                val state = meal.submissions.lastOrNull()?.state ?: SubmissionState.saved
                val proposalItems = meal.submissions.filter { it.state == SubmissionState.awaitingReview }.flatMap { it.proposal?.items.orEmpty() }
                if (receipt.itemID != null && (meal.items + proposalItems).none { it.id == receipt.itemID }) { summaries += "This item was deleted."; continue }
                summaries += when {
                    receipt.itemID != null && facts.items.isNotEmpty() ->
                        if (state == SubmissionState.awaitingReview) "Your estimate is ready for review."
                        else "Updated " + facts.items.joinToString(", ") { "${it.name} to ${number(it.quantity)} ${it.unit}" } + "."
                    "/scale_meal/" in key && state != SubmissionState.awaitingReview -> {
                        val before = tx.coachUndo(key)?.before?.let { "${known(it)} → " } ?: ""
                        val unknown = meal.items.filter { it.nutrition.kcal == null }.map { it.name }
                        val one = unknown.size == 1
                        val note = if (unknown.isEmpty()) "" else " ${unknown.joinToString(", ")} ${if (one) "has" else "have"} no calories set, so ${if (one) "it isn't" else "they aren't"} counted."
                        "Updated ${meal.items.joinToString(", ") { it.name }}: $before${known(meal.items)} kcal.$note"
                    }
                    "/retry_meal/" in key -> "Trying that meal again."
                    "/move_meal/" in key -> "Moved to ${CoachReplyLines.shortDate(tx.trackingDay(meal.dayID).localDate)}."
                    "/attach_photos/" in key -> if (meal.photos.size == 1) "Added the photo." else "Added ${meal.photos.size} photos."
                    "/delete_photo/" in key -> {
                        val deleted = runCatching { SwiftJson.decodeFromString(DeletedPhoto.serializer(), receipt.resultJSON) }.getOrNull()
                            ?.let { swiftUUID(it.id) }
                        if (deleted != null && meal.photos.none { it.id == deleted }) "Removed the photo." else "Check the meal's photos."
                    }
                    state == SubmissionState.awaitingReview -> "Your estimate is ready for review."
                    else -> {
                        val calories = facts.items.map { it.nutrition?.kcal }
                        val total = if (calories.isEmpty() || null in calories) null else calories.sumOf { it!! }
                        total?.let { "Saved — about **${number(swiftRounded(it / 10) * 10)}** kcal." } ?: "Saved."
                    }
                }
            }
            receipt.weightID != null -> summaries += try {
                tx.weight(receipt.weightID)
                if (facts.weightValue != null && facts.weightUnit != null) "Weight saved: **${number(facts.weightValue)} ${facts.weightUnit}**." else "Weight saved."
            } catch (_: DiaryError.NotFound) { "This weight was deleted." }
            receipt.workoutID != null -> summaries += try {
                tx.workout(receipt.workoutID)
                if (facts.workoutKind != null && facts.workoutMinutes != null) "Workout saved: ${facts.workoutKind}, ${facts.workoutMinutes} minutes." else "Workout saved."
            } catch (_: DiaryError.NotFound) { "This workout was deleted." }
            receipt.goalID != null -> {
                if (tx.boundedRecords("goal", GoalRecord.serializer(), "id = ?", listOf(receipt.goalID.swift), "ordinal", 1).isEmpty()) throw DiaryError.NotFound
                summaries += "Your goals are updated."
            }
            receipt.destination != null -> summaries += "Use the Settings link to continue."
            "/update_preferences" in key -> summaries += "Your preferences are updated."
            receipt.dayID != null -> {
                val day = tx.trackingDay(receipt.dayID)
                summaries += "Marked ${CoachReplyLines.shortDate(day.localDate)} as ${if (day.completeness == DayCompleteness.untracked) "skipped" else "counted"}."
            }
        }
    }
    // Each line is one short sentence; cards do not show every operation's facts, so keep them all.
    summaries.joinToString(" ")
}
