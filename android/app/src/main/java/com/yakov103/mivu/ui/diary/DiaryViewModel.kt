package com.yakov103.mivu.ui.diary

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.yakov103.mivu.diary.DayCompleteness
import com.yakov103.mivu.diary.DayDetail
import com.yakov103.mivu.diary.DayStatus
import com.yakov103.mivu.diary.DiaryDaySummary
import com.yakov103.mivu.diary.DiaryError
import com.yakov103.mivu.diary.DiaryRepository
import com.yakov103.mivu.diary.dayDetail
import com.yakov103.mivu.diary.dayStatus
import com.yakov103.mivu.diary.diaryWeek
import com.yakov103.mivu.diary.earliestRecordDate
import com.yakov103.mivu.diary.setCompleteness
import com.yakov103.mivu.ui.today.failureMessage
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.time.temporal.TemporalAdjusters
import java.time.temporal.WeekFields
import java.util.Locale
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.merge
import kotlinx.coroutines.flow.onStart
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

// Port of iOS DiaryWeek (DiaryWeekStrip.swift) and HistoryView's week and day loading. Dates are diary-day labels:
// the formats are English, as iOS's en_US formatter, because the MVP is English-only.

private val English = Locale.US

/** The seven dates of the week holding [date], starting on [firstDay]. */
internal fun weekDates(date: LocalDate, firstDay: DayOfWeek): List<LocalDate> {
    val start = date.with(TemporalAdjusters.previousOrSame(firstDay))
    return (0L..6L).map(start::plusDays)
}

/** iOS `weekStarts`: every week from the earliest of the records and the selection through the week holding [today]. */
internal fun weekStarts(earliest: LocalDate?, selected: LocalDate, today: LocalDate, firstDay: DayOfWeek): List<LocalDate> {
    val start = weekDates(listOfNotNull(earliest, selected, today).min(), firstDay).first()
    val end = weekDates(maxOf(today, selected), firstDay).first()
    return generateSequence(start) { week -> week.plusWeeks(1).takeIf { it <= end } }.toList()
}

/** Swiping from week [from] to week [to] keeps the weekday and never moves past [today]. */
internal fun shiftedSelection(selected: LocalDate, from: LocalDate, to: LocalDate, today: LocalDate): LocalDate =
    minOf(selected.plusDays(ChronoUnit.DAYS.between(from, to)), today)

internal fun DiaryDaySummary.status(activeDayID: UUID?): DayStatus? = dayStatus(listOfNotNull(day), activeDayID, savedMealCount > 0)

/** iOS `pillLabel`: "Monday 12 October, Open, 2 meals", or ", nothing logged" when the date has no record. */
internal fun pillLabel(date: LocalDate, summary: DiaryDaySummary?, activeDayID: UUID?): String {
    val name = date.format(DateTimeFormatter.ofPattern("EEEE d MMMM", English))
    val status = summary?.status(activeDayID) ?: return "$name, nothing logged"
    val meals = summary.mealCount
    return "$name, ${status.name}, $meals ${if (meals == 1) "meal" else "meals"}"
}

internal fun dayTitle(date: LocalDate): String = date.format(DateTimeFormatter.ofPattern("EEEE, d MMMM", English))

data class DiaryUiState(
    val selected: LocalDate,
    /** The last selectable date: today, or a later record (travel across zones), as iOS `lastDate`. */
    val today: LocalDate,
    val earliest: LocalDate?,
    /** The selected week's summaries by date; null while that week loads. */
    val week: Map<LocalDate, DiaryDaySummary>?,
    /** The selected date's recorded day; null when the date has no record or it is loading. */
    val detail: DayDetail?,
    val activeDayID: UUID?,
    val error: String?,
) {
    val recordedDayID: UUID? get() = week?.get(selected)?.day?.id
}

/**
 * The Diary tab's week and day. The selection starts on the active day (else today) and moves with [select]; every
 * committed diary change reloads it. Meals are read without photo bytes; thumbnails load one at a time.
 */
class DiaryViewModel(
    private val repository: DiaryRepository,
    private val profileID: UUID,
    val sampleMode: Boolean,
    private val calendarToday: (ZoneId) -> LocalDate = { LocalDate.now(it) },
    val firstDay: DayOfWeek = WeekFields.of(Locale.getDefault()).firstDayOfWeek,
) : ViewModel() {
    private val selection = MutableStateFlow<LocalDate?>(null)
    private val retries = MutableSharedFlow<Unit>(extraBufferCapacity = 1)
    private val _state = MutableStateFlow<DiaryUiState?>(null)
    private val _messages = Channel<String>(Channel.BUFFERED)

    /** Null until the first read; a first read that fails is a state with only [DiaryUiState.error]. */
    val state: StateFlow<DiaryUiState?> = _state

    /** One-shot failures for the snackbar, as iOS's "Could not complete action" alert. */
    val messages: Flow<String> = _messages.receiveAsFlow()

    init {
        viewModelScope.launch {
            combine(selection, merge(repository.changes, retries).onStart { emit(Unit) }) { date, _ -> date }.collect { date ->
                // Show the new selection at once; an older week's summaries must not read as this week's.
                if (date != null) _state.update { current ->
                    current?.copy(
                        selected = date,
                        week = current.week.takeIf { weekDates(date, firstDay).first() == weekDates(current.selected, firstDay).first() },
                        detail = current.detail.takeIf { date == current.selected },
                    )
                }
                val loaded = try {
                    withContext(Dispatchers.IO) { load(date) }
                } catch (e: Exception) {
                    _state.value?.copy(error = "Could not load this week. ${failureMessage(e)}")
                        ?: DiaryUiState(date ?: LocalDate.now(), LocalDate.now(), null, null, null, null, failureMessage(e))
                }
                if (selection.value == date) _state.value = loaded
            }
        }
    }

    fun select(date: LocalDate) {
        _state.value?.let { if (date <= it.today) selection.value = date }
    }

    fun retry() { retries.tryEmit(Unit) }

    /** iOS DayStatusChip: skipping stores `untracked`; counting again stores `unknown`, read as open or closed. */
    fun setSkipped(dayID: UUID, skip: Boolean) {
        viewModelScope.launch(Dispatchers.IO) {
            val db = repository.database(profileID)
            val write = { db.setCompleteness(dayID, if (skip) DayCompleteness.untracked else DayCompleteness.unknown, db.head().revision) }
            try {
                try { write() } catch (_: DiaryError.StaleRevision) { write() }
            } catch (e: Exception) {
                _messages.send("Could not complete action. ${failureMessage(e)}")
            }
        }
    }

    /** The first photo's bytes for a meal thumbnail, read off the main thread. */
    suspend fun photoBytes(mealID: UUID, photoID: UUID): ByteArray? =
        withContext(Dispatchers.IO) { runCatching { repository.database(profileID).photoBytes(mealID, photoID) }.getOrNull() }

    private fun load(requested: LocalDate?): DiaryUiState {
        val db = repository.database(profileID)
        val (head, activeDate, latest) = db.read { tx ->
            Triple(tx.head, tx.head.activeDayID?.let(tx::day)?.localDate, tx.days().maxOfOrNull { it.localDate })
        }
        val today = maxOf(calendarToday(ZoneId.of(head.profile.timeZoneID)), latest?.let(LocalDate::parse) ?: LocalDate.MIN)
        val selected = minOf(requested ?: activeDate?.let(LocalDate::parse) ?: today, today)
        val dates = weekDates(selected, firstDay)
        val week = db.diaryWeek(dates.first().toString(), dates.last().toString()).associateBy { LocalDate.parse(it.localDate) }
        return DiaryUiState(
            selected = selected,
            today = today,
            earliest = db.earliestRecordDate()?.let(LocalDate::parse),
            week = week,
            detail = week[selected]?.day?.let { db.dayDetail(it.id) },
            activeDayID = head.activeDayID,
            error = null,
        )
    }
}
