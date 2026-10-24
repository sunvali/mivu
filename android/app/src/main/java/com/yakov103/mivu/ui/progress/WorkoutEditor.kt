package com.yakov103.mivu.ui.progress

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.yakov103.mivu.R
import com.yakov103.mivu.diary.MealTimePrecision
import com.yakov103.mivu.diary.WorkoutKind
import com.yakov103.mivu.diary.WorkoutSession
import com.yakov103.mivu.ui.CaptureDialog
import com.yakov103.mivu.ui.coach.AskPip
import com.yakov103.mivu.ui.today.isLargeText
import java.text.NumberFormat
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale

internal val WorkoutKind.title get() = when (this) {
    WorkoutKind.strength -> "Strength"
    WorkoutKind.cardio -> "Cardio"
    WorkoutKind.other -> "Other"
}

private val WorkoutKind.tag get() = "workout${title}"

/** iOS `setID`: the first exercise's first set has the plain tag; later ones add their indices. */
private fun setTag(prefix: String, exercise: Int, set: Int) = if (exercise == 0) (if (set == 0) prefix else "$prefix$set") else "$prefix${exercise}_$set"

/** iOS `WorkoutEditorView` as an M3 full-screen dialog: kind, duration, exercises with their sets, and an optional estimate. */
@Composable
fun WorkoutEditorScreen(model: WorkoutEditorViewModel, onClose: () -> Unit) {
    LaunchedEffect(model.saved) { if (model.saved) onClose() }
    val form = model.form
    val enabled = model.loaded && !model.saving
    fun edit(next: WorkoutForm) { model.form = next }
    CaptureDialog(
        title = if (model.editing) "Edit workout" else "Add workout manually",
        closeTag = "cancelWorkout", saveTag = "saveWorkout",
        canSave = form.valid && model.loaded, saving = model.saving, dirty = model.dirty,
        discardTitle = "Discard changes to this workout?", discardMessage = null,
        onClose = onClose, onSave = model::save, textSave = true,
    ) {
        EditorSection("Workout · ${model.localDate}")
        KindChoice(form.kind, enabled) { edit(form.copy(kind = it)) }
        EditorField(form.duration, { edit(form.copy(duration = it)) }, "Duration in minutes", "workoutDuration", enabled = enabled,
            keyboard = KeyboardType.Number,
            error = "Enter a duration from 1 to 1,440 minutes.".takeIf { form.duration.isNotEmpty() && !form.durationValid })

        EditorSection("Exercise details", Modifier.padding(top = 8.dp))
        val large = isLargeText()
        form.exercises.forEachIndexed { e, exercise ->
            fun setExercise(next: WorkoutExerciseFields) = edit(form.copy(exercises = form.exercises.toMutableList().also { it[e] = next }))
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                EditorField(exercise.name, { setExercise(exercise.copy(name = it)) }, "Exercise", if (e == 0) "workoutExercise" else "workoutExercise$e",
                    enabled = enabled, keyboard = KeyboardType.Text)
                exercise.sets.forEachIndexed { s, set ->
                    fun setSet(next: WorkoutSetFields) = setExercise(exercise.copy(sets = exercise.sets.toMutableList().also { it[s] = next }))
                    val reps = @Composable { m: Modifier ->
                        EditorField(set.repetitions, { setSet(set.copy(repetitions = it)) }, "Repetitions", setTag("workoutRepetitions", e, s), m,
                            enabled = enabled, keyboard = KeyboardType.Number)
                    }
                    val load = @Composable { m: Modifier ->
                        EditorField(set.load, { setSet(set.copy(load = it)) }, "Load (kg, blank for bodyweight)", setTag("workoutLoad", e, s), m,
                            enabled = enabled)
                    }
                    if (large) { reps(Modifier.fillMaxWidth()); load(Modifier.fillMaxWidth()) }
                    else Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) { reps(Modifier.weight(1f)); load(Modifier.weight(1.4f)) }
                    if (exercise.sets.size > 1) {
                        EditorButton("Remove set ${s + 1}", setTag("removeWorkoutSet", e, s), enabled) {
                            setExercise(exercise.copy(sets = exercise.sets.filterIndexed { i, _ -> i != s }))
                        }
                    }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    EditorButton("Add set", if (e == 0) "addWorkoutSet" else "addWorkoutSet$e", enabled) {
                        setExercise(exercise.copy(sets = exercise.sets + WorkoutSetFields()))
                    }
                    EditorButton("Remove exercise", "removeWorkoutExercise$e", enabled) {
                        edit(form.copy(exercises = form.exercises.filterIndexed { i, _ -> i != e }))
                    }
                }
                if (!exercise.valid) {
                    ErrorLine("Enter an exercise name and 1–10,000 repetitions per set. Load can be blank for bodyweight, or 0–100,000 kg.")
                }
            }
        }
        EditorButton("Add exercise", "addWorkoutExercise", enabled) { edit(form.copy(exercises = form.exercises + WorkoutExerciseFields())) }
        EditorNote("Leave an unused exercise blank for a simple session. Leave load blank for bodyweight.")

        EditorSection("Optional estimate", Modifier.padding(top = 8.dp))
        EditorField(form.burn, { edit(form.copy(burn = it)) }, "Estimated burn (kcal)", "workoutBurn", enabled = enabled, last = true,
            error = "Enter 0–100,000 kcal, or leave this blank.".takeIf { !validOptionalNonnegative(form.burn) })
        EditorNote("An estimate, shown separately from recorded food.")
        model.loadError?.let { LoadError(it, "Reload workout") { model.reload() } }
    }
    model.saveError?.let { SaveFailed("Could not save workout", it) { model.saveError = null } }
}

/** M3 segmented buttons; stacked radio rows from 150% text, where three labels no longer fit across. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun KindChoice(kind: WorkoutKind, enabled: Boolean, onChoose: (WorkoutKind) -> Unit) {
    val kinds = WorkoutKind.entries
    if (LocalDensity.current.fontScale >= 1.5f) {
        Column(Modifier.selectableGroup()) {
            kinds.forEach { option ->
                Row(
                    Modifier.fillMaxWidth().heightIn(min = 48.dp).testTag(option.tag)
                        .selectable(option == kind, enabled = enabled, role = Role.RadioButton) { onChoose(option) },
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    RadioButton(option == kind, onClick = null, enabled = enabled)
                    Text(option.title, style = MaterialTheme.typography.bodyLarge)
                }
            }
        }
    } else {
        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
            kinds.forEachIndexed { i, option ->
                SegmentedButton(option == kind, { onChoose(option) }, SegmentedButtonDefaults.itemShape(i, kinds.size),
                    Modifier.heightIn(min = 48.dp).testTag(option.tag), enabled = enabled) { Text(option.title) }
            }
        }
    }
}

@Composable
private fun EditorButton(text: String, tag: String, enabled: Boolean, onClick: () -> Unit) {
    OutlinedButton(onClick, Modifier.heightIn(min = 48.dp).testTag(tag), enabled = enabled) { Text(text) }
}

@Composable
private fun ErrorLine(text: String) {
    Text(text, Modifier.padding(horizontal = 4.dp).semantics { liveRegion = LiveRegionMode.Polite }, style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.error)
}

/** iOS Ask Pip excerpt: "Strength · 45 min · Fri 23 Oct". */
internal fun workoutExcerpt(session: WorkoutSession, localDate: String): String =
    "${session.kind.title} · ${session.durationMinutes} min · " +
        runCatching { LocalDate.parse(localDate).format(DateTimeFormatter.ofPattern("EEE d MMM", Locale.US)) }.getOrDefault(localDate)

/** iOS `WorkoutDetailView`: the session, its exercises, Edit, Delete (after the iOS confirmation) and Ask Pip. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WorkoutDetailScreen(
    model: WorkoutDetailViewModel,
    onBack: () -> Unit,
    onEdit: (localDate: String, sessionID: java.util.UUID) -> Unit,
    onAskPip: (AskPip) -> Unit,
) {
    LaunchedEffect(model.deleted) { if (model.deleted) onBack() }
    var confirming by rememberSaveable { mutableStateOf(false) }
    val detail = model.detail
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Workout", Modifier.semantics { heading() }) },
                navigationIcon = { IconButton(onBack) { Icon(painterResource(R.drawable.ic_arrow_back), contentDescription = "Back") } },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background),
            )
        },
        containerColor = MaterialTheme.colorScheme.background,
    ) { padding ->
        Column(
            Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            when {
                detail != null -> {
                    val (session, day) = detail
                    val number = NumberFormat.getNumberInstance(Locale.US)
                    val body = MaterialTheme.typography.bodyLarge
                    Text(session.kind.title, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.SemiBold)
                    Text("${session.durationMinutes} minutes", style = body)
                    Text(if (session.timePrecision == MealTimePrecision.dateOnly) "Time unspecified"
                        else session.performedAt.atZone(ZoneId.of(day.timeZoneID)).format(DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT)), style = body)
                    Text(session.estimatedBurnKcal?.let { "Estimated burn: ${number.format(it)} kcal" } ?: "Estimated burn: unknown", style = body)
                    EditorSection("Exercises", Modifier.padding(top = 8.dp))
                    if (session.exercises.isEmpty()) Text("No exercise details recorded.", style = body)
                    session.exercises.forEach { exercise ->
                        Column(Modifier.semantics(mergeDescendants = true) {}) {
                            Text(exercise.name, style = MaterialTheme.typography.titleMedium)
                            exercise.sets.forEachIndexed { i, set ->
                                Text("Set ${i + 1}: ${set.repetitions} repetitions · ${set.loadKg?.let { "${number.format(it)} kg" } ?: "bodyweight"}", style = body)
                            }
                        }
                    }
                    Row(Modifier.padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        FilledTonalButton({ onEdit(day.localDate, session.id) }, Modifier.heightIn(min = 48.dp).testTag("editWorkout"),
                            enabled = !model.deleting) { Text("Edit") }
                        OutlinedButton({ onAskPip(AskPip.Workout(session.id, workoutExcerpt(session, day.localDate))) },
                            Modifier.heightIn(min = 48.dp).testTag("askPipWorkout")) {
                            Icon(painterResource(R.drawable.ic_auto_awesome), contentDescription = null)
                            Text("Ask Pip", Modifier.padding(start = 8.dp))
                        }
                    }
                    TextButton({ confirming = true }, Modifier.heightIn(min = 48.dp).testTag("deleteWorkout"), enabled = !model.deleting) {
                        Text("Delete workout", color = MaterialTheme.colorScheme.error)
                    }
                    model.deleteError?.let { ErrorLine(it) }
                    if (confirming) DeleteConfirmation(session, day.localDate, onDismiss = { confirming = false }) {
                        confirming = false; model.delete(session)
                    }
                }
                model.loading -> CircularProgressIndicator(Modifier.align(Alignment.CenterHorizontally).padding(24.dp))
                else -> {
                    Text(model.loadError ?: "Workout unavailable", style = MaterialTheme.typography.bodyLarge)
                    TextButton(model::reload, Modifier.heightIn(min = 48.dp)) { Text("Reload workout") }
                }
            }
        }
    }
}

@Composable
private fun DeleteConfirmation(session: WorkoutSession, localDate: String, onDismiss: () -> Unit, onDelete: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Delete ${session.kind.title.lowercase()} workout on $localDate?") },
        text = { Text("This removes only this workout and its exercise details. Meals, weights and other workouts are preserved.") },
        confirmButton = {
            TextButton(onDelete, Modifier.heightIn(min = 48.dp).testTag("confirmDeleteWorkout")) {
                Text("Delete workout", color = MaterialTheme.colorScheme.error)
            }
        },
        dismissButton = { TextButton(onDismiss, Modifier.heightIn(min = 48.dp)) { Text("Cancel") } },
    )
}
