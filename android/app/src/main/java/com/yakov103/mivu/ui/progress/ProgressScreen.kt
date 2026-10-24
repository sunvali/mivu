package com.yakov103.mivu.ui.progress

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import com.yakov103.mivu.R
import com.yakov103.mivu.coach.CoachProgress
import com.yakov103.mivu.diary.DiaryDatabase
import com.yakov103.mivu.diary.DiaryRepository
import com.yakov103.mivu.diary.TopFood
import com.yakov103.mivu.diary.progressRange
import com.yakov103.mivu.diary.topFoods
import com.yakov103.mivu.diary.wakingDateLabel
import com.yakov103.mivu.pip.CompanionOutput
import com.yakov103.mivu.pip.CompanionPose
import com.yakov103.mivu.pip.CompanionRuntime
import com.yakov103.mivu.pip.CompanionSurface
import com.yakov103.mivu.pip.MivuMotion
import com.yakov103.mivu.pip.MotionPolicy.Playback
import com.yakov103.mivu.pip.PipAssets
import com.yakov103.mivu.pip.PipCompanion
import com.yakov103.mivu.pip.PipGestureLibrary
import com.yakov103.mivu.pip.PipRigScene
import com.yakov103.mivu.pip.rememberMotionPlayback
import com.yakov103.mivu.progress.ProgressRange
import com.yakov103.mivu.progress.ProgressSnapshot
import java.time.Instant
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale
import java.util.UUID
import kotlin.random.Random
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.mapLatest
import kotlinx.coroutines.flow.merge
import kotlinx.coroutines.flow.onStart
import kotlinx.coroutines.flow.stateIn

sealed interface ProgressUiState {
    data object Loading : ProgressUiState
    data class Loaded(val snapshot: ProgressSnapshot, val foods: List<TopFood>, val progress: CoachProgress) : ProgressUiState
    /** [last] is the report still on screen: a failed range switch keeps it, a new day never does (iOS `shows`). */
    data class Failed(val message: String, val last: Loaded?) : ProgressUiState
}

/** The profile zone and the date Progress ends on: the open day's date, else today's waking date (iOS `today`). */
internal fun progressToday(db: DiaryDatabase): Pair<String, String> {
    val head = db.head()
    val zone = head.profile.timeZoneID
    return zone to (head.activeDayID?.let { id -> db.read { it.day(id) }?.localDate } ?: wakingDateLabel(Instant.now(), zone))
}

/**
 * iOS `DiaryProgressView` loading: [loadDays][ProgressSnapshot.loadDays] days ending today's waking date, reloaded on
 * every diary change. A range switch keeps the last report until the new one lands. [read] is the display progress read
 * (a seam for tests only).
 */
@OptIn(ExperimentalCoroutinesApi::class)
class ProgressViewModel(
    private val repository: DiaryRepository,
    private val profileID: UUID,
    private val read: (DiaryDatabase, String, Int) -> CoachProgress = { db, end, days -> db.progressRange(end, days, includeDailyReports = true) },
) : ViewModel() {
    private val _range = MutableStateFlow(ProgressRange.Week)
    val range: StateFlow<ProgressRange> = _range
    private val retries = MutableSharedFlow<Unit>(extraBufferCapacity = 1)
    @Volatile private var last: ProgressUiState.Loaded? = null

    val state: StateFlow<ProgressUiState> = combine(_range, merge(repository.changes, retries).onStart { emit(Unit) }) { range, _ -> range }
        .mapLatest(::load)
        .flowOn(Dispatchers.IO)
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), ProgressUiState.Loading)

    fun select(range: ProgressRange) { _range.value = range }

    fun retry() { retries.tryEmit(Unit) }

    private fun load(range: ProgressRange): ProgressUiState {
        var today: String? = null
        return try {
            val db = repository.database(profileID)
            val (zone, end) = progressToday(db)
            today = end
            val progress = read(db, end, ProgressSnapshot.loadDays(range))
            val foods = db.topFoods(ProgressSnapshot.rangeStart(progress, range), progress.endLocalDate, 4)
            ProgressUiState.Loaded(ProgressSnapshot(progress, range, zone, end), foods, progress).also { last = it }
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            ProgressUiState.Failed("Could not load progress. Your diary is preserved.", last?.takeIf { it.progress.endLocalDate == today })
        }
    }
}

/** iOS `dates(_:)`: "Oct 18 – Oct 24", with years beyond a month. */
internal fun rangeDates(progress: CoachProgress, range: ProgressRange): String {
    val pattern = DateTimeFormatter.ofPattern(if (range.days > 30) "MMM d, yyyy" else "MMM d", Locale.US)
    fun f(date: String) = runCatching { LocalDate.parse(date).format(pattern) }.getOrDefault(date)
    return "${f(ProgressSnapshot.rangeStart(progress, range))} – ${f(progress.endLocalDate)}"
}

/**
 * Port of iOS `DiaryProgressView`: the range picker, an optional load failure, the headline with Pip presenting, the
 * weight and average-day cards, and "More" rows that each open a full detail screen (Goals opens the goal editor).
 */
@Composable
fun ProgressScreen(
    model: ProgressViewModel,
    onOpenDetail: (ProgressDetailKind) -> Unit,
    onOpenGoals: () -> Unit,
    onOpenDiary: () -> Unit,
) {
    val state by model.state.collectAsStateWithLifecycle()
    val range by model.range.collectAsStateWithLifecycle()
    val loaded = when (val s = state) {
        is ProgressUiState.Loaded -> s
        is ProgressUiState.Failed -> s.last
        ProgressUiState.Loading -> null
    }
    val failure = (state as? ProgressUiState.Failed)?.message
    val pip = rememberProgressPip(loaded?.snapshot?.headline?.celebrates)
    val large = LocalDensity.current.fontScale >= 1.5f
    if (loaded == null) {
        Column(Modifier.fillMaxSize().padding(24.dp), verticalArrangement = Arrangement.spacedBy(16.dp, Alignment.CenterVertically),
            horizontalAlignment = Alignment.CenterHorizontally) {
            if (failure != null) Failure(failure, model::retry) else {
                CircularProgressIndicator()
                Text("Loading progress…", style = MaterialTheme.typography.bodyLarge)
            }
        }
        return
    }
    val snapshot = loaded.snapshot
    LazyColumn(
        Modifier.fillMaxSize().testTag("progressList"),
        contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 4.dp, bottom = 24.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item(key = "range") {
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().testTag("progressRange")) {
                ProgressRange.entries.forEachIndexed { i, option ->
                    SegmentedButton(
                        selected = option == range,
                        onClick = { if (option != range) { model.select(option); pip.react(CompanionPose.ProgressRange) } },
                        shape = SegmentedButtonDefaults.itemShape(i, ProgressRange.entries.size),
                        modifier = Modifier.heightIn(min = 48.dp),
                    ) { Text(option.title, maxLines = 1) }
                }
            }
        }
        // The last report stays on screen during a range switch, so a failed switch must still say so.
        if (failure != null) item(key = "failure") { Failure(failure, model::retry) }
        item(key = "headline") {
            HeadlineCard(snapshot, rangeDates(loaded.progress, snapshot.range), large, onOpenDiary) { ProgressPip(pip, if (large) 120.dp else 150.dp) }
        }
        item(key = "weightTitle") { SectionTitle("Weight") }
        item(key = "weight") { WeightCard(snapshot) { onOpenDetail(ProgressDetailKind.Weight) } }
        item(key = "macrosTitle") { SectionTitle("Average day") }
        item(key = "macros") { MacrosCard(snapshot, { onOpenDetail(ProgressDetailKind.Macros) }, large) }
        item(key = "moreTitle") { SectionTitle("More") }
        item(key = "more") {
            ProgressCard {
                Column(Modifier.padding(horizontal = 0.dp)) {
                    MoreRow("progressCalendar", R.drawable.ic_calendar, "Calendar", "${snapshot.loggedDays} of ${snapshot.days.size} days logged") {
                        onOpenDetail(ProgressDetailKind.Calendar)
                    }
                    MoreDivider()
                    MoreRow("progressCalories", R.drawable.ic_whatshot, "Calories", snapshot.averageKcal?.let { "avg ${com.yakov103.mivu.progress.kcal(it)}" } ?: "No complete days") {
                        onOpenDetail(ProgressDetailKind.Calories)
                    }
                    MoreDivider()
                    MoreRow("progressBurn", R.drawable.ic_favorite, "Estimated burn", snapshot.burnSummary) { onOpenDetail(ProgressDetailKind.Burn) }
                    MoreDivider()
                    MoreRow("progressTopFoods", R.drawable.ic_restaurant, "Top foods", loaded.foods.firstOrNull()?.name ?: "None yet") {
                        onOpenDetail(ProgressDetailKind.TopFoods)
                    }
                    MoreDivider()
                    MoreRow("openWorkouts", R.drawable.ic_fitness_center, "Workouts", "${loaded.progress.workoutTotal ?: 0} recorded") {
                        onOpenDetail(ProgressDetailKind.Workouts)
                    }
                    MoreDivider()
                    MoreRow("progressGoals", R.drawable.ic_target, "Goals", "Manage", onOpenGoals)
                }
            }
        }
    }
}

@Composable
private fun Failure(message: String, onRetry: () -> Unit) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(message, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium, textAlign = TextAlign.Center)
        TextButton(onRetry, Modifier.heightIn(min = 48.dp)) { Text("Retry loading progress") }
    }
}

/** A one-shot asked for; a fresh id replays the same pose (two taps in a row). */
private data class PipReaction(val pose: CompanionPose, val level: Int = 0, val id: UUID = UUID.randomUUID())

/** Progress's one Pip: what it shows now, the runtime once the rig loads, and the requests that make it react. */
internal class ProgressPipState(val output: CompanionOutput?, val runtime: CompanionRuntime?, val react: (CompanionPose) -> Unit, val onTouch: () -> Unit)

/**
 * The iOS Progress Pip task: dressed with the chart card and glasses, an entrance once per visit (a cheer when the
 * headline celebrates), then presenting, cheerful or calm. A range switch and each tap play a one-shot first. Remove
 * animations shows the still pose; leaving the tab (or the screen stopping) hides it and stops the runtime.
 */
@Composable
private fun rememberProgressPip(celebrates: Boolean?): ProgressPipState {
    val context = LocalContext.current
    val assets = produceState<Pair<PipRigScene, PipGestureLibrary>?>(null) {
        value = runCatching { PipAssets.load(context) }.getOrNull() // a missing rig keeps the still image
    }.value
    val scope = rememberCoroutineScope()
    val runtime = assets?.let { (scene, library) ->
        remember(scene) { CompanionRuntime(library, scene, scope, { System.nanoTime() / 1_000_000 }, Random.Default).apply { showsProgressProps = true } }
    }
    val playback = rememberMotionPlayback()
    var reaction by remember { mutableStateOf<PipReaction?>(null) }
    var entered by remember { mutableStateOf(false) }
    var taps by remember { mutableIntStateOf(0) }
    var output by remember { mutableStateOf<CompanionOutput?>(null) }
    // Waits for the rig too, so the entrance is never spent before Pip can show it.
    LaunchedEffect(celebrates, playback, reaction, runtime) {
        val cheer = celebrates ?: return@LaunchedEffect
        if (runtime == null) return@LaunchedEffect
        val presenting = if (cheer) CompanionPose.PresentingCheer else CompanionPose.PresentingCalm
        if (playback == Playback.Hidden) { output = CompanionOutput(presenting, playback, null); return@LaunchedEffect }
        // A one-shot first (entrance, range switch, tap), then back to holding the chart.
        val oneShot = reaction?.pose ?: if (entered) null else if (cheer) CompanionPose.ProgressEntranceCheer else CompanionPose.ProgressEntrance
        entered = true
        if (oneShot != null && playback == Playback.Animated) {
            output = CompanionOutput(oneShot, playback, UUID.randomUUID(), tapLevel = reaction?.level ?: 0)
            delay(Math.round(lifetime(oneShot) * 1000))
            // Clearing the request reruns this effect, which settles Pip back into holding the chart.
            if (reaction != null) { reaction = null; return@LaunchedEffect }
        }
        output = CompanionOutput(presenting, playback, null)
    }
    return ProgressPipState(output, runtime, react = { reaction = PipReaction(it) }) {
        reaction = PipReaction(CompanionPose.ProgressTap, taps); taps++ // each tap plays the next silly gesture
    }
}

private fun lifetime(pose: CompanionPose) = when (pose) {
    CompanionPose.ProgressRange -> MivuMotion.progressRange
    CompanionPose.ProgressTap -> MivuMotion.progressTap
    else -> MivuMotion.progressEntrance
}

/** Pip stands on the right, mirrored to face the verdict and the bars (the rig itself only faces right). Decorative. */
@Composable
private fun ProgressPip(pip: ProgressPipState, size: Dp) {
    val mirror = Modifier.graphicsLayer { scaleX = -1f }
    Box(Modifier.size(size * (399.8f / 455.5f), size), contentAlignment = Alignment.Center) {
        if (pip.runtime != null && pip.output != null) PipCompanion(pip.output, CompanionSurface.Today, size, pip.runtime, { pip.onTouch() }, mirror)
        else Image(painterResource(R.drawable.pip_preview), contentDescription = null, mirror.size(size))
    }
}
