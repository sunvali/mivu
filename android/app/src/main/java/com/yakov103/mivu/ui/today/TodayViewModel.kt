package com.yakov103.mivu.ui.today

import android.text.format.DateFormat
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.yakov103.mivu.diary.DiaryMeal
import com.yakov103.mivu.diary.DiaryRepository
import com.yakov103.mivu.diary.GoalRecord
import com.yakov103.mivu.diary.TrackingDay
import com.yakov103.mivu.diary.WorkoutSession
import com.yakov103.mivu.diary.dailyProgress
import com.yakov103.mivu.diary.nutritionTotals
import com.yakov103.mivu.diary.startDay
import java.text.NumberFormat
import java.time.Instant
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale
import java.util.UUID
import kotlin.math.abs
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.onStart
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

/** iOS `todayGoal`: the kcal target, what is left, and the progress bar's fraction and spoken value. */
data class GoalSummary(
    val target: String,
    val remaining: String?,
    val progress: Float?,
    val progressValue: String?,
    val exerciseAdjusted: String?,
)

/** Today's read model, formatted as iOS `TodayView` shows it. A null number is shown as "—". */
data class TodayUiState(
    val displayDate: String,
    val activeDayID: UUID?,
    val kcal: String?,
    val protein: String?,
    val carbs: String?,
    val fat: String?,
    val unknownNote: Boolean,
    val goal: GoalSummary?,
    val meals: List<DiaryMeal>,
    val sampleMode: Boolean,
    val savedReceipt: UUID?,
) {
    val hasDay get() = activeDayID != null
}

private class TodayData(val day: TrackingDay?, val meals: List<DiaryMeal>, val goals: List<GoalRecord>, val workouts: List<WorkoutSession>)

class TodayViewModel(private val repository: DiaryRepository, private val profileID: UUID, sampleMode: Boolean) : ViewModel() {
    private val receipt = MutableStateFlow<UUID?>(null)

    val state: StateFlow<TodayUiState?> = combine(
        repository.changes.onStart { emit(Unit) }.map { load() }.flowOn(Dispatchers.IO),
        receipt,
    ) { data, saved ->
        // Coach and Diary own other days' receipts; Today shows one only while its meal is on this day.
        todayUiState(data.day, data.meals, data.goals, data.workouts, sampleMode, saved?.takeIf { id -> data.meals.any { it.id == id } },
            Locale.getDefault(), DateFormat.getBestDateTimePattern(Locale.getDefault(), "EEEEMMMMd"))
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)

    /** The "Saved on this phone" receipt after a capture screen saves [mealID]. */
    fun showReceipt(mealID: UUID) { receipt.value = mealID }

    /** No confirmation, as iOS: a repeated start reuses the open day. */
    fun startNewDay() {
        viewModelScope.launch(Dispatchers.IO) {
            val db = repository.database(profileID)
            // shortcut: a failed start (a concurrent write) is dropped like a no-op tap; surface it once Today has an error banner.
            runCatching { db.startDay(Instant.now(), db.head().revision) }
        }
    }

    private fun load(): TodayData = repository.database(profileID).read { tx ->
        val day = tx.head.activeDayID?.let(tx::day)
        if (day == null) TodayData(null, emptyList(), emptyList(), emptyList())
        else TodayData(day, tx.dayMeals(day.id), tx.goals(), tx.dayWorkouts(day.id))
    }
}

internal fun todayUiState(
    day: TrackingDay?,
    meals: List<DiaryMeal>,
    goals: List<GoalRecord>,
    workouts: List<WorkoutSession>,
    sampleMode: Boolean,
    savedReceipt: UUID?,
    locale: Locale,
    datePattern: String,
): TodayUiState {
    // Swift `.number.precision(.fractionLength(0))`: grouped, rounded half-even.
    val number = NumberFormat.getIntegerInstance(locale)
    fun Double.text(): String = number.format(this)
    fun grams(value: Double?) = value?.let { "${it.text()} g" }

    val progress = day?.let { dailyProgress(listOf(it), meals, goals, workouts, it.localDate) }
    val totals = progress?.foodTotals ?: nutritionTotals(emptyList())
    val goal = progress?.goal?.targets?.kcal?.let { target ->
        val recorded = progress.foodTotals?.kcal
        val left = progress.remainingFromRecorded.kcal
        GoalSummary(
            target = "${target.text()} kcal goal",
            remaining = left?.let { "${abs(it).text()} ${if (it < 0) "above goal" else "to goal"}" },
            progress = recorded?.takeIf { target > 0 }?.let { minOf(it / target, 1.0).toFloat() },
            progressValue = recorded?.takeIf { target > 0 }?.let { "${it.text()} of ${target.text()} kilocalories" },
            exerciseAdjusted = progress.exerciseAdjustedKcalRemaining?.takeIf { progress.goal.exerciseCreditEnabled }
                ?.let { "Exercise-adjusted remaining: ${it.text()} kcal" },
        )
    }
    return TodayUiState(
        displayDate = day?.let {
            runCatching { LocalDate.parse(it.localDate).format(DateTimeFormatter.ofPattern(datePattern, locale)) }.getOrDefault(it.localDate)
        } ?: "Your waking day",
        activeDayID = day?.id,
        kcal = totals.kcal?.text(),
        protein = grams(totals.protein),
        carbs = grams(totals.carbs),
        fat = grams(totals.fat),
        unknownNote = totals.unknownItemCount > 0,
        goal = goal,
        meals = meals.sortedByDescending { it.capturedAt },
        sampleMode = sampleMode,
        savedReceipt = savedReceipt,
    )
}
