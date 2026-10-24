package com.yakov103.mivu.ui.today

import android.content.SharedPreferences
import android.text.format.DateFormat
import androidx.core.content.edit
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.yakov103.mivu.coach.coachProgress
import com.yakov103.mivu.day.greeting
import com.yakov103.mivu.diary.DiaryDatabase
import com.yakov103.mivu.diary.DiaryError
import com.yakov103.mivu.diary.MorningRecap
import com.yakov103.mivu.diary.morningRecap
import com.yakov103.mivu.diary.recordWeight
import com.yakov103.mivu.pip.CompanionEvent
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
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import java.util.Locale
import java.util.UUID
import kotlin.math.abs
import kotlin.math.roundToLong
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.callbackFlow
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
    /** The morning check-in, on Today and as Coach's weigh-in bubble; null once hidden. */
    val morning: MorningState? = null,
) {
    val hasDay get() = activeDayID != null
}

/** iOS Today's late-meal receipt: "Added to Fri, Oct 23", and "Move to Sat, Oct 24" while that date is still today. */
data class LateReceipt(val added: String, val moveTo: String?)

/**
 * iOS MorningCheckInCard's inputs, shown after a new waking day starts until its first meal or until hidden for [dayID].
 * [recap] is null when the previous day had no meals; [asking] while today has no weight and it was not skipped.
 */
data class MorningState(
    val dayID: UUID,
    val greeting: String,
    val recap: MorningRecap?,
    val todayWeight: WeightEntry?,
    val asking: Boolean,
    val trendKg: Double?,
    val lastKg: Double?,
    /** The open day's date, so the recap can say "Yesterday". */
    val localDate: String,
)

/** iOS @AppStorage keys, shared by Today and Coach. */
object MorningKeys {
    const val DISMISSED = "morningCardDismissedDay"
    const val SKIPPED = "morningWeightSkippedDay"
    const val UNIT = "weightUnit"
}

internal const val KG_PER_LB = 0.45359237

private class TodayData(
    val day: TrackingDay?, val meals: List<DiaryMeal>, val goals: List<GoalRecord>, val workouts: List<WorkoutSession>, val weight: WeightEntry?,
    val morning: MorningState? = null,
)

class TodayViewModel(private val repository: DiaryRepository, val profileID: UUID, sampleMode: Boolean) : ViewModel() {
    private val receipt = MutableStateFlow<UUID?>(null)
    private val retries = MutableSharedFlow<Unit>(extraBufferCapacity = 1)
    private val _loadFailed = MutableStateFlow(false)

    /** The last read failed. [state] keeps the last good read, or stays null when there was none. */
    val loadFailed: StateFlow<Boolean> = _loadFailed

    private val preferences = repository.preferences
    private val _weightUnit = MutableStateFlow(preferences.getString(MorningKeys.UNIT, null) ?: "kg")

    /** The check-in's weight unit, "kg" or "lb"; weights are saved in kilograms. */
    val weightUnit: StateFlow<String> = _weightUnit.asStateFlow()

    /** Dismissal, skip and unit live in preferences, so Today and Coach follow each other. */
    private val preferenceChanges = callbackFlow {
        val listener = SharedPreferences.OnSharedPreferenceChangeListener { prefs, key ->
            if (key == MorningKeys.UNIT) _weightUnit.value = prefs.getString(key, null) ?: "kg"
            if (key == MorningKeys.DISMISSED || key == MorningKeys.SKIPPED) trySend(Unit)
        }
        preferences.registerOnSharedPreferenceChangeListener(listener)
        awaitClose { preferences.unregisterOnSharedPreferenceChangeListener(listener) }
    }

    private val _companionEvents = MutableSharedFlow<CompanionEvent>(extraBufferCapacity = 1)

    /** Pip's saved nod after the morning weigh-in. */
    val companionEvents: SharedFlow<CompanionEvent> = _companionEvents

    val state: StateFlow<TodayUiState?> = combine(
        merge(repository.changes, retries, preferenceChanges).onStart { emit(Unit) }.mapNotNull {
            try { load().also { _loadFailed.value = false } } catch (_: Exception) { _loadFailed.value = true; null }
        }.flowOn(Dispatchers.IO),
        receipt,
    ) { data, saved ->
        // Coach and Diary own other days' receipts; Today shows one only while its meal is on this day.
        todayUiState(data.day, data.meals, data.goals, data.workouts, sampleMode, saved?.takeIf { id -> data.meals.any { it.id == id } },
            Locale.getDefault(), DateFormat.getBestDateTimePattern(Locale.getDefault(), "EEEEMMMMd"), Instant.now(), data.weight)
            .copy(morning = data.morning)
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

    /**
     * iOS `saveMorningWeight`: the weigh-in records on the day that is already open, in kilograms to 0.1; Pip nods once it
     * is saved. False when [kg] is outside 20...400 or the write failed (the failure is reported).
     */
    suspend fun saveMorningWeight(kg: Double): Boolean {
        if (kg !in 20.0..400.0) return false
        return withContext(Dispatchers.IO) {
            try {
                val entry = repository.database(profileID).recordWeight((kg * 10).roundToLong() / 10.0, startNewDay = false)
                _companionEvents.tryEmit(CompanionEvent(profileID, entry.id, CompanionEvent.Kind.Saved, System.currentTimeMillis()))
                true
            } catch (e: Exception) {
                _messages.send("Could not complete action. ${failureMessage(e)}")
                false
            }
        }
    }

    fun skipMorningWeight() { state.value?.morning?.let { m -> preferences.edit { putString(MorningKeys.SKIPPED, m.dayID.toString()) } } }

    /** Hides the check-in on Today and Coach for this waking day only. */
    fun dismissMorning() { state.value?.morning?.let { m -> preferences.edit { putString(MorningKeys.DISMISSED, m.dayID.toString()) } } }

    fun setWeightUnit(unit: String) = preferences.edit { putString(MorningKeys.UNIT, unit) }

    /** The first photo's bytes for a meal thumbnail, read off the main thread. */
    suspend fun photoBytes(mealID: UUID, photoID: UUID): ByteArray? =
        withContext(Dispatchers.IO) { runCatching { repository.database(profileID).photoBytes(mealID, photoID) }.getOrNull() }

    private fun load(): TodayData = repository.database(profileID).read { tx ->
        val day = tx.head.activeDayID?.let(tx::day)
        if (day == null) TodayData(null, emptyList(), emptyList(), emptyList(), null)
        else {
            val meals = tx.dayMeals(day.id)
            val weight = tx.dayWeight(day.id)
            TodayData(day, meals, tx.goals(), tx.dayWorkouts(day.id), weight, if (meals.isEmpty()) tx.morning(day, weight) else null)
        }
    }

    private fun DiaryDatabase.Tx.morning(day: TrackingDay, weight: WeightEntry?): MorningState? {
        if (preferences.getString(MorningKeys.DISMISSED, null) == day.id.toString()) return null
        val recap = morningRecap(day.id) ?: return null
        val progress = coachProgress(day.localDate, 7, includeDailyReports = true)
        return MorningState(
            day.id, greeting(LocalTime.now().hour), recap.takeIf { it.previous.mealCount > 0 }, weight,
            asking = weight == null && preferences.getString(MorningKeys.SKIPPED, null) != day.id.toString(),
            trendKg = progress.weight.changeFromSevenDaysAgoKg,
            lastKg = progress.latestWeight?.record?.let { if (it.unit == "lb") it.value * KG_PER_LB else it.value },
            localDate = day.localDate,
        )
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
            // "Added to" names the day's date, never "Yesterday", as iOS TodayView.swift:606. Moving opens today's calendar
            // date, so it is offered only while that is still the meal's date.
            else LateReceipt("Added to ${wakingDayTitle(day.localDate)}",
                wakingDayTitle(date).takeIf { date == diaryDateLabel(now, day.timeZoneID) }?.let { "Move to $it" })
        },
    )
}
