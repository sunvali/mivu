package com.yakov103.mivu.ui.diary

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.PlainTooltip
import androidx.compose.material3.SelectableDates
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TooltipBox
import androidx.compose.material3.TooltipDefaults
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.material3.rememberTooltipState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.yakov103.mivu.R
import com.yakov103.mivu.diary.WorkoutSession
import com.yakov103.mivu.ui.theme.MivuTheme
import com.yakov103.mivu.ui.today.MealRow
import com.yakov103.mivu.ui.today.WhiteCard
import java.time.LocalDate
import java.time.ZoneOffset
import java.util.UUID

private val Gutter = 16.dp

/**
 * Port of iOS HistoryView in Material 3 Expressive direction B: a week strip over the selected day's summary, meals and
 * workouts. Weight and workout entry arrive in milestone 6; "Log meal" for a past day waits for a day-targeted composer.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DiaryScreen(
    viewModel: DiaryViewModel,
    onOpenMeal: (UUID) -> Unit,
    onAskPip: () -> Unit,
    onEnterNutrition: (dayID: UUID) -> Unit,
    onProfile: () -> Unit,
) {
    val state = viewModel.state.collectAsStateWithLifecycle().value
    val snackbar = remember { SnackbarHostState() }
    LaunchedEffect(viewModel) { viewModel.messages.collect { snackbar.showSnackbar(it, withDismissAction = true) } }
    var choosingDate by rememberSaveable { mutableStateOf(false) }
    var addMenu by rememberSaveable { mutableStateOf(false) }

    Column(Modifier.fillMaxSize()) {
        TopAppBar(
            title = {
                Text("Diary", Modifier.semantics { heading() }, style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
            },
            actions = {
                ToolbarButton("Choose date", R.drawable.ic_calendar, "chooseDiaryDate", enabled = state?.week != null) { choosingDate = true }
                ToolbarButton("Ask Pip", R.drawable.ic_auto_awesome, "diaryAskPip", onClick = onAskPip)
                Box {
                    ToolbarButton("Add to this day", R.drawable.ic_add, "diaryAddMenu", enabled = state?.recordedDayID != null) { addMenu = true }
                    DropdownMenu(addMenu, onDismissRequest = { addMenu = false }, shape = RoundedCornerShape(16.dp)) {
                        DropdownMenuItem(
                            text = { Text("Enter nutrition manually") },
                            onClick = { addMenu = false; state?.recordedDayID?.let(onEnterNutrition) },
                            leadingIcon = { Icon(painterResource(R.drawable.ic_numbers), contentDescription = null) },
                            modifier = Modifier.testTag("enterNutritionForDay"),
                        )
                    }
                }
                ToolbarButton("Profile and settings", R.drawable.ic_profile, "profileSettings", onClick = onProfile)
            },
            colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background),
        )
        Box(Modifier.weight(1f).fillMaxWidth()) {
            if (state != null) DiaryContent(state, viewModel, onOpenMeal)
            SnackbarHost(snackbar, Modifier.align(Alignment.BottomCenter).padding(horizontal = Gutter))
        }
    }
    if (choosingDate && state != null) {
        ChooseDate(state.selected, state.earliest, state.today, onDismiss = { choosingDate = false }) { date ->
            choosingDate = false
            viewModel.select(date)
        }
    }
}

@Composable
private fun DiaryContent(state: DiaryUiState, viewModel: DiaryViewModel, onOpenMeal: (UUID) -> Unit) {
    val detail = state.detail
    LazyColumn(
        Modifier.fillMaxSize(),
        contentPadding = PaddingValues(top = 4.dp, bottom = 16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item(key = "week") {
            WeekStrip(state.selected, state.today, state.earliest, viewModel.firstDay, state.week, state.activeDayID, viewModel::select)
        }
        val padded = Modifier.padding(horizontal = Gutter)
        state.error?.let { error -> item(key = "error") { LoadFailure(error, viewModel::retry, padded) } }
        when {
            state.error == null && (state.week == null || (state.recordedDayID != null && detail == null)) -> item(key = "loading") {
                Box(Modifier.fillMaxWidth().heightIn(min = 120.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
            }
            state.week != null && state.recordedDayID == null -> item(key = "nothing") { NothingLogged(dayTitle(state.selected), padded) }
            detail != null -> {
                item(key = "summary") {
                    DaySummaryCard(dayTitle(state.selected), detail, state.week!!.getValue(state.selected).totals, state.activeDayID,
                        { skip -> viewModel.setSkipped(detail.day.id, skip) }, padded)
                }
                item(key = "mealsHeader") { SectionHeader("Meals", padded) }
                if (detail.meals.isEmpty()) item(key = "noMeals") {
                    WhiteCard(padded) {
                        Text("No meals recorded for this day.", Modifier.padding(20.dp), style = MaterialTheme.typography.bodyLarge,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                items(detail.meals, key = { it.id }) { meal ->
                    WhiteCard(padded.testTag("historyMeal"), onClick = { onOpenMeal(meal.id) }) {
                        MealRow(meal, viewModel::photoBytes, Modifier.padding(16.dp))
                    }
                }
                if (detail.workouts.isNotEmpty()) {
                    item(key = "workoutsHeader") { SectionHeader("Workouts", padded) }
                    items(detail.workouts.sortedBy { it.performedAt }, key = { it.id }) { WorkoutRow(it, padded) }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ToolbarButton(label: String, icon: Int, tag: String, enabled: Boolean = true, onClick: () -> Unit) {
    TooltipBox(TooltipDefaults.rememberPlainTooltipPositionProvider(), tooltip = { PlainTooltip { Text(label) } }, state = rememberTooltipState()) {
        IconButton(onClick, Modifier.testTag(tag), enabled = enabled) { Icon(painterResource(icon), contentDescription = label) }
    }
}

@Composable
private fun SectionHeader(text: String, modifier: Modifier) {
    Text(text, modifier.padding(top = 12.dp).semantics { heading() }, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
}

/** Read-only until workout detail arrives in milestone 6. */
@Composable
private fun WorkoutRow(workout: WorkoutSession, modifier: Modifier) {
    WhiteCard(modifier) {
        Row(
            Modifier.heightIn(min = 56.dp).padding(horizontal = 20.dp, vertical = 12.dp).semantics(mergeDescendants = true) {},
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Icon(painterResource(R.drawable.ic_fitness_center), contentDescription = null, tint = MaterialTheme.colorScheme.primary)
            Text("Workout", Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold)
            Text("${workout.durationMinutes} minutes", style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun NothingLogged(title: String, modifier: Modifier) {
    Surface(modifier.fillMaxWidth(), shape = RoundedCornerShape(28.dp), color = MivuTheme.colors.summarySurface) {
        Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(title, Modifier.semantics { heading() }, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
            Column(
                Modifier.fillMaxWidth().padding(vertical = 24.dp).semantics(mergeDescendants = true) {},
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Icon(painterResource(R.drawable.ic_today), contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                Text("Nothing logged", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                Text("Ask Pip to add what you ate on this day.", style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable
private fun LoadFailure(message: String, onRetry: () -> Unit, modifier: Modifier) {
    WhiteCard(modifier) {
        Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(message, Modifier.semantics { liveRegion = LiveRegionMode.Polite }, style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
            FilledTonalButton(onRetry, Modifier.heightIn(min = 48.dp).testTag("retryDiaryHistory")) { Text("Retry") }
        }
    }
}

/** iOS date sheet: earliest record through today, "Show date" or "Cancel". DatePicker dates are UTC midnights. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ChooseDate(selected: LocalDate, earliest: LocalDate?, today: LocalDate, onDismiss: () -> Unit, onChoose: (LocalDate) -> Unit) {
    fun LocalDate.millis() = atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()
    val first = minOf(earliest ?: today, today)
    val picker = rememberDatePickerState(
        initialSelectedDateMillis = selected.millis(),
        yearRange = first.year..today.year,
        selectableDates = object : SelectableDates {
            override fun isSelectableDate(utcTimeMillis: Long) = utcTimeMillis in first.millis()..today.millis()
            override fun isSelectableYear(year: Int) = year in first.year..today.year
        },
    )
    DatePickerDialog(
        onDismissRequest = onDismiss,
        confirmButton = {
            TextButton(
                onClick = { picker.selectedDateMillis?.let { onChoose(java.time.Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate()) } },
                modifier = Modifier.testTag("applyDiaryDate"),
                enabled = picker.selectedDateMillis != null,
            ) { Text("Show date") }
        },
        dismissButton = { TextButton(onDismiss) { Text("Cancel") } },
    ) {
        DatePicker(picker, title = {
            Text("Choose date", Modifier.padding(start = 24.dp, end = 12.dp, top = 16.dp))
        })
    }
}
