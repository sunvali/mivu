package com.yakov103.mivu.ui.today

import android.text.format.DateFormat
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.yakov103.mivu.diary.DiaryError
import com.yakov103.mivu.diary.DiaryMeal
import com.yakov103.mivu.diary.DiaryRepository
import com.yakov103.mivu.diary.GoalRecord
import com.yakov103.mivu.diary.TrackingDay
import com.yakov103.mivu.diary.WeightEntry
import com.yakov103.mivu.diary.WorkoutSession
import com.yakov103.mivu.diary.dailyProgress
import com.yakov103.mivu.diary.diaryDateLabel
import com.yakov103.mivu.diary.moveMeal
import com.yakov103.mivu.diary.wakingDayTitle
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
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.mapNotNull
import kotlinx.coroutines.flow.merge
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.withContext
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flowOn
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
    val lateReceipt: LateReceipt? = null,
    /** The day's morning weight, as "72.5 kg"; null when none is logged. */
    val weight: String? = null,
    /** A goal is in effect, even one without a kcal target: Today offers "Edit goals" instead of "Set a goal". */
    val hasGoal: Boolean = false,
) {
    val hasDay get() = activeDayID != null
}

/** iOS Today's late-meal receipt: "Added to Yesterday", and "Move to Sat, Oct 24" while that date is still today. */
data class LateReceipt(val added: String, val moveTo: String?)

private class TodayData(
    val day: TrackingDay?, val meals: List<DiaryMeal>, val goals: List<GoalRecord>, val workouts: List<WorkoutSession>, val weight: WeightEntry?,
)

class TodayViewModel(private val repository: DiaryRepository, val profileID: UUID, sampleMode: Boolean) : ViewModel() {
    private val receipt = MutableStateFlow<UUID?>(null)
    private val retries = MutableSharedFlow<Unit>(extraBufferCapacity = 1)
    private val _loadFailed = MutableStateFlow(false)

    /** The last read failed. [state] keeps the last good read, or stays null when there was none. */
    val loadFailed: StateFlow<Boolean> = _loadFailed

    val state: StateFlow<TodayUiState?> = combine(
        merge(repository.changes, retries).onStart { emit(Unit) }.mapNotNull {
            try { load().also { _loadFailed.value = false } } catch (_: Exception) { _loadFailed.value = true; null }
        }.flowOn(Dispatchers.IO),
        receipt,
    ) { data, saved ->
        // Coach and Diary own other days' receipts; Today shows one only while its meal is on this day.
        todayUiState(data.day, data.meals, data.goals, data.workouts, sampleMode, saved?.takeIf { id -> data.meals.any { it.id == id } },
            Locale.getDefault(), DateFormat.getBestDateTimePattern(Locale.getDefault(), "EEEEMMMMd"), Instant.now(), data.weight)
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)

    /** Reads the day again after a failed read. */
    fun retry() { retries.tryEmit(Unit) }

    /** The "Saved on this phone" receipt after a capture screen saves [mealID]. */
    fun showReceipt(mealID: UUID) { receipt.value = mealID }

    private val _messages = Channel<String>(Channel.BUFFERED)

    /** One-shot failure messages for the snackbar, as iOS's "Could not complete action" alert. */
    val messages: Flow<String> = _messages.receiveAsFlow()

    /** No confirmation, as iOS: a repeated start reuses the open day. A write that raced this one is retried once. */
    fun startNewDay() {
        viewModelScope.launch(Dispatchers.IO) {
            val db = repository.database(profileID)
            val start = { db.startDay(Instant.now(), db.head().revision) }
            try {
                try { start() } catch (_: DiaryError.StaleRevision) { start() }
            } catch (e: Exception) {
                _messages.send("Could not complete action. ${failureMessage(e)}")
            }
        }
    }

    /** iOS `moveToCalendarDay`: a late meal moves to its calendar date. Starting before the cutoff opens that date. */
    fun moveToCalendarDay(mealID: UUID) {
        viewModelScope.launch(Dispatchers.IO) {
            try {
                val db = repository.database(profileID)
                val meal = db.read { it.meal(mealID) } ?: throw DiaryError.NotFound
                // One write, so a failed move leaves no new day behind.
                db.transaction(db.head().revision) { tx ->
                    val day = tx.startDay(Instant.now())
                    tx.moveMeal(mealID, day.id, null, expectedRevision = meal.revision, expectedDayID = meal.dayID)
                }
            } catch (e: Exception) {
                _messages.send("Could not complete action. ${failureMessage(e)}")
            }
        }
    }

    /** The first photo's bytes for a meal thumbnail, read off the main thread. */
    suspend fun photoBytes(mealID: UUID, photoID: UUID): ByteArray? =
        withContext(Dispatchers.IO) { runCatching { repository.database(profileID).photoBytes(mealID, photoID) }.getOrNull() }

    private fun load(): TodayData = repository.database(profileID).read { tx ->
        val day = tx.head.activeDayID?.let(tx::day)
        if (day == null) TodayData(null, emptyList(), emptyList(), emptyList(), null)
        else TodayData(day, tx.dayMeals(day.id), tx.goals(), tx.dayWorkouts(day.id), tx.dayWeight(day.id))
    }
}

/** iOS `DiaryError.errorDescription` for the errors a Today action can meet, else iOS's fallback. */
internal fun failureMessage(e: Throwable): String = when (e) {
    is DiaryError.InvalidData -> "This diary contains invalid or unsupported data."
    DiaryError.WrongOwner -> "The profile changed. Please try again."
    DiaryError.NotFound -> "This diary entry no longer exists."
    else -> "Could not save on this phone. Your input is still here."
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
    now: Instant = Instant.now(),
    weight: WeightEntry? = null,
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
        // iOS `.number.precision(.fractionLength(1))`.
        weight = weight?.let { w -> "${NumberFormat.getNumberInstance(locale).apply { minimumFractionDigits = 1; maximumFractionDigits = 1 }.format(w.value)} ${w.unit}" },
        hasGoal = progress?.goal != null,
        lateReceipt = meals.firstOrNull { it.id == savedReceipt }?.takeIf { day != null }?.let { meal ->
            val date = diaryDateLabel(meal.capturedAt, day!!.timeZoneID)
            if (day.localDate >= date) null
            // Moving opens today's calendar date, so offer it only while that is still the meal's date.
            else LateReceipt("Added to ${wakingDayTitle(day.localDate, relativeTo = date)}",
                wakingDayTitle(date).takeIf { date == diaryDateLabel(now, day.timeZoneID) }?.let { "Move to $it" })
        },
    )
}
