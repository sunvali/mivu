package com.yakov103.mivu.widget

import com.yakov103.mivu.diary.DayCompleteness
import com.yakov103.mivu.diary.DayCutoff
import com.yakov103.mivu.diary.DiaryDatabase
import com.yakov103.mivu.diary.dayNutritionTotals
import com.yakov103.mivu.diary.diaryDateLabel
import com.yakov103.mivu.diary.goalOn
import java.time.Instant
import java.time.ZoneId
import kotlinx.serialization.Serializable

// Port of ios/Shared/WidgetSnapshot.swift and ios/Mivu/WidgetSnapshotWriter.swift.

/** Today's calories for the home-screen widget, written by the app; the widget never opens the diary. Times are epoch ms. */
@Serializable
data class WidgetSnapshot(
    val day: String,
    val eaten: Double,
    val target: Double?,
    val hasDiary: Boolean,
    val rolloverAt: Long,
    val writtenAt: Long,
) {
    /** The new waking day has started: nothing eaten yet, same target. */
    fun afterRollover(): WidgetSnapshot = copy(eaten = 0.0)

    val ringFraction: Double get() = if (target == null || target <= 0) 0.0 else minOf(eaten / target, 1.0)

    companion object {
        /** The next waking-day start strictly after [afterMillis], in the day's own zone so travel cannot shift it. */
        fun nextRollover(afterMillis: Long, timeZoneID: String, cutoffHour: Int): Long {
            val zone = runCatching { ZoneId.of(timeZoneID, ZoneId.SHORT_IDS) }.getOrDefault(ZoneId.systemDefault())
            val after = Instant.ofEpochMilli(afterMillis)
            val date = after.atZone(zone).toLocalDate()
            // atZone moves a time in a DST gap forward to the next existing one, as iOS `.nextTime`.
            val today = date.atTime(cutoffHour, 0).atZone(zone).toInstant()
            val next = if (today.isAfter(after)) today else date.plusDays(1).atTime(cutoffHour, 0).atZone(zone).toInstant()
            return next.toEpochMilli()
        }
    }
}

/**
 * One bounded read, as Today's: the head, the active day's meals and the goal for that date. The rollover counts from the
 * day's start, so a day left open past the cutoff reads as over instead of lasting until tomorrow.
 */
fun DiaryDatabase.widgetSnapshot(now: Instant, cutoffHour: Int = DayCutoff.hour): WidgetSnapshot = read { tx ->
    val day = tx.head.activeDayID?.let(tx::day)
    val zone = day?.timeZoneID ?: tx.head.profile.timeZoneID
    val date = day?.localDate ?: diaryDateLabel(now, zone)
    val eaten = day?.let { dayNutritionTotals(tx.dayMeals(it.id), it.completeness == DayCompleteness.complete).kcal }
    WidgetSnapshot(date, eaten ?: 0.0, goalOn(date, tx.goals())?.targets?.kcal, hasDiary = true,
        rolloverAt = WidgetSnapshot.nextRollover((day?.startAt ?: now).toEpochMilli(), zone, cutoffHour), writtenAt = now.toEpochMilli())
}
