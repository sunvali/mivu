package com.yakov103.mivu.ui.coach

import com.yakov103.mivu.coach.CoachReplyLines
import com.yakov103.mivu.diary.CoachTurnState
import com.yakov103.mivu.diary.DayCompleteness
import com.yakov103.mivu.diary.DiaryDatabase
import com.yakov103.mivu.diary.dayNutritionTotals
import com.yakov103.mivu.diary.goalOn
import java.text.NumberFormat
import java.time.LocalDate
import java.time.ZoneId
import java.util.Locale

/** What Pip says beside the Coach composer (iOS `PipLine`). Pure, so the copy is pinned by tests rather than by the view. */
sealed interface PipLine {
    data class Say(val text: String) : PipLine
    data class Working(val text: String) : PipLine
    data class Problem(val text: String, val detail: String?, val canRetry: Boolean) : PipLine
    data object Connect : PipLine

    companion object {
        fun current(hour: Int, mealsLogged: Boolean, typing: Boolean, connected: Boolean, processing: Boolean, withPhotos: Boolean,
                    recovery: Boolean, error: String?, turnState: CoachTurnState?, onDevice: Boolean): PipLine? {
            if (recovery) return when (turnState) {
                CoachTurnState.waitingForConnection -> Connect
                CoachTurnState.waitingForNetwork -> Problem(if (onDevice) "I'll finish this when you're back in Mivu."
                    else "I’m offline. I’ll pick this up when you’re back.", error, false)
                CoachTurnState.needsClarification -> Problem("I need a bit more detail. My question is above.", error, false)
                CoachTurnState.needsRetry -> Problem("That one didn’t go through.", error, true)
                else -> Problem("Something went wrong.", error, false)
            }
            if (processing) return Working(if (withPhotos) "Looking at your photo…" else "Counting that up…")
            if (!connected) return Connect
            if (typing) return null
            if (mealsLogged) return Say("Anything else to log?")
            return Say(when (hour) {
                in 4..10 -> "Morning! What’s for breakfast?"
                in 11..14 -> "Ready for lunch?"
                in 15..17 -> "What have you had today?"
                in 18..21 -> "What’s for dinner?"
                else -> "Anything to log?"
            })
        }
    }
}

data class CoachDayChip(val text: String, val spoken: String)

/**
 * The logging day and its intake, e.g. "Today · 1,240 / 2,000 kcal". A saved food without calories makes the figure a lower
 * bound ("1,240+"), as on Today; unknown intake reads "—", never zero.
 */
fun coachDayChip(localDate: String, today: String, kcal: Double?, kcalPartial: Boolean, mealsLogged: Boolean, goal: Double?): CoachDayChip {
    val day = CoachReplyLines.dayLabel(localDate, today)
    val whole = NumberFormat.getIntegerInstance()
    val eaten = kcal?.let { whole.format(it) + if (kcalPartial) "+" else "" } ?: if (mealsLogged) "—" else "0"
    val spokenEaten = kcal?.let { (if (kcalPartial) "at least " else "") + whole.format(it) } ?: if (mealsLogged) "unknown" else "0"
    val target = goal?.let { whole.format(it) }
    return CoachDayChip("${day.replaceFirstChar { it.titlecase(Locale.getDefault()) }} · $eaten" + (target?.let { " / $it" } ?: "") + " kcal",
        "Logging to $day, $spokenEaten" + (target?.let { " of $it" } ?: "") + " kcal")
}

data class CoachDay(val chip: CoachDayChip, val mealsLogged: Boolean)

/** The active day's chip, in one bounded read; null without an active day. */
internal fun DiaryDatabase.coachDay(): CoachDay? = read { tx ->
    val head = tx.head
    val day = head.activeDayID?.let(tx::day) ?: return@read null
    val meals = tx.dayMeals(day.id)
    val today = LocalDate.now(ZoneId.of(head.profile.timeZoneID)).toString()
    // revision > 0 is a saved meal, as dayNutritionTotals counts.
    val partial = meals.filter { it.revision > 0 }.any { meal -> meal.items.any { it.nutrition.kcal == null } }
    CoachDay(coachDayChip(day.localDate, today, dayNutritionTotals(meals, day.completeness == DayCompleteness.complete).kcal, partial,
        meals.isNotEmpty(), goalOn(day.localDate, tx.goals())?.targets?.kcal), meals.isNotEmpty())
}
