package com.yakov103.mivu.ui.progress

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.yakov103.mivu.diary.DiaryError
import com.yakov103.mivu.diary.DiaryRepository
import com.yakov103.mivu.diary.GoalRecord
import com.yakov103.mivu.diary.NutritionValues
import com.yakov103.mivu.diary.RecordPage
import com.yakov103.mivu.diary.TrackingDay
import com.yakov103.mivu.diary.WeightEntry
import com.yakov103.mivu.diary.WorkoutBurnSource
import com.yakov103.mivu.diary.WorkoutDraft
import com.yakov103.mivu.diary.WorkoutExercise
import com.yakov103.mivu.diary.WorkoutKind
import com.yakov103.mivu.diary.WorkoutSession
import com.yakov103.mivu.diary.WorkoutSet
import com.yakov103.mivu.diary.createWorkout
import com.yakov103.mivu.diary.deleteWorkout
import com.yakov103.mivu.diary.goal
import com.yakov103.mivu.diary.goalHistory
import com.yakov103.mivu.diary.recordWeight
import com.yakov103.mivu.diary.setGoals
import com.yakov103.mivu.diary.setWeight
import com.yakov103.mivu.diary.trackingDay
import com.yakov103.mivu.diary.updateWeight
import com.yakov103.mivu.diary.updateWorkout
import com.yakov103.mivu.diary.weight
import com.yakov103.mivu.diary.workout
import com.yakov103.mivu.ui.today.failureMessage
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

// The Progress editors' state and saves (iOS ProgressEditorViews.swift). Each save is one of the store writes Coach's
// weight, workout and goal tools use; the revision the editor loaded guards it, so a change made elsewhere while the
// editor was open (Coach, a rollover) fails the save and keeps the draft instead of overwriting.

private val Number = Regex("""[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?""")

/** iOS `ProgressDate.number`: trimmed, `.` or `,` as the decimal mark, finite; null when blank or not a number. */
fun progressNumber(text: String): Double? {
    val trimmed = text.trim().replace(',', '.')
    return if (Number.matches(trimmed)) trimmed.toDouble().takeIf { it.isFinite() } else null
}

/** Blank, or a positive number. */
internal fun validOptional(text: String) = text.isBlank() || (progressNumber(text) ?: 0.0) > 0

/** Blank, or 0–100,000. */
internal fun validOptionalNonnegative(text: String) = text.isBlank() || progressNumber(text)?.let { it in 0.0..100_000.0 } == true

/** A stored number as a field shows it: whole numbers without ".0". */
internal fun fieldText(value: Double?): String = when {
    value == null -> ""
    value == Math.rint(value) && kotlin.math.abs(value) < 1e15 -> value.toLong().toString()
    else -> value.toString()
}

/** The alert message for a failed editor save; [preserved] says the draft is kept. */
internal fun editorFailure(e: Throwable, preserved: String): String = when (e) {
    DiaryError.StaleRevision -> "This changed elsewhere, such as in Coach. $preserved"
    is DiaryError.InvalidData, DiaryError.WrongOwner, DiaryError.NotFound -> failureMessage(e)
    else -> "Could not save on this phone. $preserved"
}

/** iOS `GoalEditorValues`: the goal editor's fields for [localDate]; blank means no target. */
data class GoalEditorValues(
    val localDate: String,
    val original: GoalRecord?,
    val kcal: String,
    val carbs: String,
    val protein: String,
    val fat: String,
    val weight: String,
    val exerciseCredit: Boolean,
) {
    val expectedRevision: Int? get() = original?.revision
    val valid: Boolean get() = listOf(kcal, carbs, protein, fat, weight).all(::validOptional)
    val hasEditedTargets: Boolean get() = this != of(original, localDate)

    fun record(zone: String) = GoalRecord(original?.id ?: UUID.randomUUID(), localDate, zone, original?.revision ?: 0,
        NutritionValues(progressNumber(kcal), progressNumber(carbs), progressNumber(protein), progressNumber(fat)),
        progressNumber(weight), exerciseCredit)

    companion object {
        fun of(goal: GoalRecord?, localDate: String) = GoalEditorValues(localDate, goal, fieldText(goal?.targets?.kcal),
            fieldText(goal?.targets?.carbs), fieldText(goal?.targets?.protein), fieldText(goal?.targets?.fat), fieldText(goal?.goalWeightKg),
            goal?.exerciseCreditEnabled ?: false)
    }
}

/** Runs [body] on IO and reports a failure through [onError]; rethrows cancellation. */
private suspend fun <T> attempt(onError: (Exception) -> Unit, body: () -> T): T? = try {
    withContext(Dispatchers.IO) { body() }
} catch (e: CancellationException) {
    throw e
} catch (e: Exception) {
    onError(e); null
}

/**
 * iOS `MorningWeightEditorView` ("Add weight manually") and, with [weightID], `WeightCorrectionView` ("Edit weight").
 * Without a day or weight it records now, starting or reusing today's waking day; with [dayID] it sets that day's weight.
 */
class WeightEditorViewModel(
    private val repository: DiaryRepository,
    private val profileID: UUID,
    val dayID: UUID?,
    val weightID: UUID?,
) : ViewModel() {
    var value by mutableStateOf("")
    var initial by mutableStateOf<WeightEntry?>(null); private set
    var localDate by mutableStateOf<String?>(null); private set
    var loaded by mutableStateOf(dayID == null && weightID == null); private set
    var loadError by mutableStateOf<String?>(null); private set
    var saving by mutableStateOf(false); private set
    var saveError by mutableStateOf<String?>(null)
    var saved by mutableStateOf(false); private set

    val correcting get() = weightID != null
    val unit get() = initial?.unit ?: "kg"
    val dirty get() = value != fieldText(initial?.value)
    val valid get() = progressNumber(value)?.let { it > 0 && it <= 1000 } == true

    init { if (!loaded) load() }

    fun load() {
        loadError = null
        viewModelScope.launch {
            val draft = value
            val (weight, date) = attempt({ loadError = "Could not load this day's saved weight. Your entry is preserved." }) {
                repository.database(profileID).read { tx ->
                    if (weightID != null) tx.weight(weightID).let { it to it.dayID?.let(tx::day)?.localDate }
                    else tx.dayWeight(dayID!!) to tx.trackingDay(dayID).localDate
                }
            } ?: return@launch
            initial = weight; localDate = date
            if (value == draft) value = fieldText(weight?.value)
            loaded = true
        }
    }

    fun save() {
        val number = progressNumber(value)?.takeIf { valid && loaded && !saving } ?: return
        saving = true
        viewModelScope.launch {
            attempt({ saveError = editorFailure(it, "Your entry is preserved.") }) {
                val db = repository.database(profileID)
                val existing = initial
                when {
                    existing != null -> db.updateWeight(existing.id, number, existing.revision)
                    dayID != null -> db.setWeight(dayID, number, unit, expectedRevision = null)
                    else -> db.recordWeight(number)
                }
            }?.let { saved = true }
            saving = false
        }
    }
}

/** iOS `GoalEditorView`: goals effective from a date, loaded for that exact date, and the goal history pages. */
class GoalEditorViewModel(
    private val repository: DiaryRepository,
    private val profileID: UUID,
    today: (ZoneId) -> LocalDate = { LocalDate.now(it) },
) : ViewModel() {
    var zone by mutableStateOf(ZoneId.systemDefault().id); private set
    var values by mutableStateOf(GoalEditorValues.of(null, LocalDate.now().toString()))
    private var original by mutableStateOf(values)
    var loading by mutableStateOf(true); private set
    var goalLoaded by mutableStateOf(false); private set
    var loadError by mutableStateOf<String?>(null); private set
    var history by mutableStateOf<RecordPage<GoalRecord>?>(null); private set
    var historyBefore by mutableStateOf<Long?>(null); private set
    var historyError by mutableStateOf<String?>(null); private set
    /** A date the person picked while targets were edited: the screen asks before loading it. */
    var pendingDate by mutableStateOf<String?>(null)
    var saving by mutableStateOf(false); private set
    var saveError by mutableStateOf<String?>(null)
    var saved by mutableStateOf(false); private set
    private var goalJob: Job? = null
    private var historyJob: Job? = null

    val dirty get() = values != original

    init {
        viewModelScope.launch {
            withContext(Dispatchers.IO) { runCatching { repository.database(profileID).head().profile.timeZoneID }.getOrNull() }?.let { zone = it }
            loadDate(today(ZoneId.of(zone)).toString())
            loadHistory()
            // As iOS on a change generation: reload the history, and the goal only if it never loaded.
            repository.changes.collect { if (!goalLoaded) loadGoal(); loadHistory() }
        }
    }

    fun requestDate(date: String) {
        if (date == values.localDate) return
        if (values.hasEditedTargets) pendingDate = date else loadDate(date)
    }

    fun loadDate(date: String) {
        pendingDate = null
        values = GoalEditorValues.of(null, date).also { original = it }
        loadGoal()
    }

    fun loadGoal() {
        goalJob?.cancel()
        loading = true; goalLoaded = false; loadError = null
        val date = values.localDate
        goalJob = viewModelScope.launch {
            val draft = values
            var failed = false
            val goal = attempt({ failed = true }) { repository.database(profileID).goal(date, exact = true) }
            loading = false
            if (failed) { loadError = "Could not load saved goals. Your draft is preserved."; return@launch }
            if (values == draft) values = GoalEditorValues.of(goal, date).also { original = it }
            goalLoaded = true
        }
    }

    fun pageHistory(before: Long?) { historyBefore = before; loadHistory() }

    private fun loadHistory() {
        historyJob?.cancel()
        historyError = null
        val before = historyBefore
        historyJob = viewModelScope.launch {
            attempt({ historyError = "Could not load goal history. Your draft is preserved." }) {
                repository.database(profileID).goalHistory(before)
            }?.let { history = it }
        }
    }

    fun save() {
        if (!goalLoaded || loading || saving || !values.valid) return
        val goal = values.record(zone)
        val expected = values.expectedRevision
        saving = true
        viewModelScope.launch {
            attempt({ saveError = editorFailure(it, "Your entries are preserved.") }) {
                repository.database(profileID).setGoals(goal, expected)
            }?.let { saved = true }
            saving = false
        }
    }
}

/** One set's fields: repetitions 1–10,000, load blank (bodyweight) or 0–100,000 kg. */
data class WorkoutSetFields(val repetitions: String = "", val load: String = "") {
    val valid get() = repetitions.toIntOrNull()?.let { it in 1..10_000 } == true && validOptionalNonnegative(load)
    val record get() = if (valid) WorkoutSet(repetitions.toInt(), progressNumber(load)) else null

    companion object {
        fun of(set: WorkoutSet) = WorkoutSetFields(set.repetitions.toString(), fieldText(set.loadKg))
    }
}

/** One exercise's fields; a blank exercise is left out of the session. */
data class WorkoutExerciseFields(val name: String = "", val sets: List<WorkoutSetFields> = listOf(WorkoutSetFields())) {
    val isBlank get() = name.isBlank() && sets.all { it.repetitions.isEmpty() && it.load.isEmpty() }
    val valid get() = isBlank || (name.isNotBlank() && sets.all { it.valid })
    val record get() = if (valid && !isBlank) WorkoutExercise(name.trim(), sets.mapNotNull { it.record }) else null

    companion object {
        fun of(exercise: WorkoutExercise) = WorkoutExerciseFields(exercise.name, exercise.sets.map(WorkoutSetFields::of))
    }
}

/** The workout editor's whole form, so an unchanged form is equal to the one it started from. */
data class WorkoutForm(
    val kind: WorkoutKind = WorkoutKind.strength,
    val duration: String = "",
    val exercises: List<WorkoutExerciseFields> = listOf(WorkoutExerciseFields()),
    val burn: String = "",
) {
    val durationValid get() = duration.toIntOrNull()?.let { it in 1..1440 } == true
    val valid get() = durationValid && validOptionalNonnegative(burn) && exercises.all { it.valid }

    /** The estimate keeps its source while unchanged; a new figure is the person's own. */
    fun draft(session: WorkoutSession?): WorkoutDraft {
        val estimate = progressNumber(burn)
        val source = when {
            estimate == null -> null
            estimate == session?.estimatedBurnKcal -> session.burnSource
            else -> WorkoutBurnSource.userEstimate
        }
        return WorkoutDraft(kind, duration.toInt(), exercises.mapNotNull { it.record }, estimate, source)
    }

    companion object {
        fun of(session: WorkoutSession) = WorkoutForm(session.kind, session.durationMinutes.toString(),
            session.exercises.map(WorkoutExerciseFields::of), fieldText(session.estimatedBurnKcal))
    }
}

/** iOS `WorkoutEditorView`: a new workout on [localDate] (on [dayID] when given), or [sessionID] edited in place. */
class WorkoutEditorViewModel(
    private val repository: DiaryRepository,
    private val profileID: UUID,
    val localDate: String,
    private val dayID: UUID?,
    private val sessionID: UUID?,
) : ViewModel() {
    var form by mutableStateOf(WorkoutForm())
    private var original by mutableStateOf(WorkoutForm())
    var session by mutableStateOf<WorkoutSession?>(null); private set
    var loaded by mutableStateOf(sessionID == null); private set
    var loadError by mutableStateOf<String?>(null); private set
    var saving by mutableStateOf(false); private set
    var saveError by mutableStateOf<String?>(null)
    var saved by mutableStateOf(false); private set

    val editing get() = sessionID != null
    val dirty get() = form != original

    init { reload() }

    fun reload() { sessionID?.let(::load) }

    private fun load(id: UUID) {
        loadError = null
        viewModelScope.launch {
            val value = attempt({ loadError = "Could not load this workout. It may have been removed." }) {
                repository.database(profileID).read { it.workout(id) }
            } ?: return@launch
            session = value
            form = WorkoutForm.of(value).also { original = it }
            loaded = true
        }
    }

    fun save() {
        if (!form.valid || !loaded || saving) return
        val current = session
        val draft = form.draft(current)
        saving = true
        viewModelScope.launch {
            attempt({ saveError = editorFailure(it, "Your entries are preserved.") }) {
                val db = repository.database(profileID)
                when {
                    current != null -> db.updateWorkout(current.copy(kind = draft.kind, durationMinutes = draft.durationMinutes,
                        exercises = draft.exercises, estimatedBurnKcal = draft.estimatedBurnKcal, burnSource = draft.burnSource), current.revision)
                    dayID != null -> db.createWorkout(dayID, draft)
                    else -> db.createWorkout(localDate, draft)
                }
            }?.let { saved = true }
            saving = false
        }
    }
}

/** iOS `WorkoutDetailView`: the session and its day, read again after every diary change, and its deletion. */
class WorkoutDetailViewModel(private val repository: DiaryRepository, private val profileID: UUID, val sessionID: UUID) : ViewModel() {
    var detail by mutableStateOf<Pair<WorkoutSession, TrackingDay>?>(null); private set
    var loading by mutableStateOf(true); private set
    var loadError by mutableStateOf<String?>(null); private set
    var deleting by mutableStateOf(false); private set
    var deleteError by mutableStateOf<String?>(null); private set
    var deleted by mutableStateOf(false); private set

    init {
        viewModelScope.launch {
            load()
            repository.changes.collect { if (!deleting && !deleted) load() }
        }
    }

    fun reload() { viewModelScope.launch { load() } }

    private suspend fun load() {
        loading = true; loadError = null
        var failed = false
        val value = attempt({ failed = true }) {
            repository.database(profileID).read { tx -> tx.workout(sessionID).let { it to tx.trackingDay(it.dayID) } }
        }
        loading = false
        detail = value
        if (failed) loadError = "Could not load this workout. It may have been removed."
    }

    /** Deletes the revision on screen; a change made since then fails rather than deleting what the person did not see. */
    fun delete(session: WorkoutSession) {
        if (deleting) return
        deleting = true; deleteError = null
        viewModelScope.launch {
            attempt({ deleteError = "Could not complete action. ${editorFailure(it, "The workout is unchanged.")}" }) {
                repository.database(profileID).deleteWorkout(session.id, session.revision)
            }?.let { deleted = true }
            deleting = false
        }
    }
}
