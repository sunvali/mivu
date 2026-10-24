package com.yakov103.mivu.ui.progress

import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.yakov103.mivu.R
import com.yakov103.mivu.coach.CoachWeightReference
import com.yakov103.mivu.diary.DayStatus
import com.yakov103.mivu.diary.DiaryRepository
import com.yakov103.mivu.diary.RecordPage
import com.yakov103.mivu.diary.TopFood
import com.yakov103.mivu.diary.WeightEntry
import com.yakov103.mivu.diary.WorkoutSession
import com.yakov103.mivu.diary.deleteWeight
import com.yakov103.mivu.diary.diaryDateLabel
import com.yakov103.mivu.diary.hasDays
import com.yakov103.mivu.diary.progressRange
import com.yakov103.mivu.diary.topFoods
import com.yakov103.mivu.diary.weightHistory
import com.yakov103.mivu.diary.workoutHistory
import com.yakov103.mivu.progress.ProgressInsights
import com.yakov103.mivu.progress.ProgressRange
import com.yakov103.mivu.progress.ProgressSnapshot
import com.yakov103.mivu.progress.kcal
import com.yakov103.mivu.ui.coach.AskPip
import com.yakov103.mivu.ui.today.tabular
import java.text.NumberFormat
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

enum class ProgressDetailKind(val title: String) {
    Calendar("Calendar"), Calories("Calories"), Burn("Estimated burn"), TopFoods("Top foods"), Macros("Macros"), Weight("Weight"), Workouts("Workouts"),
}

/** One loaded window of a detail screen: the range ending [end], and whether the diary has older days. */
class DetailWindow(val end: String, val today: String, val snapshot: ProgressSnapshot, val foods: List<TopFood>, val hasEarlier: Boolean,
    val latestWeight: CoachWeightReference?)

/** A ledger page with each record's day label (iOS `weightDates` / `workoutDates`). */
class Ledger<T>(val page: RecordPage<T>, val dates: Map<UUID, String>)

/**
 * iOS `ProgressDetail` plus the weight ledger and workout list: the range's window paged back a whole window at a time
 * until [hasDays] says the diary has nothing older, and 30-record ledger pages. Everything reloads on diary changes.
 */
class ProgressDetailViewModel(private val repository: DiaryRepository, private val profileID: UUID, val kind: ProgressDetailKind,
    val range: ProgressRange) : ViewModel() {
    /** Null follows today; otherwise the window's last date. */
    private var endingOn by mutableStateOf<String?>(null)
    var window by mutableStateOf<DetailWindow?>(null); private set
    var windowError by mutableStateOf<String?>(null); private set
    var weights by mutableStateOf<Ledger<WeightEntry>?>(null); private set
    var workouts by mutableStateOf<Ledger<WorkoutSession>?>(null); private set
    var ledgerError by mutableStateOf<String?>(null); private set
    /** Null for the newest page; otherwise the cursor the shown page starts after. */
    var before by mutableStateOf<Long?>(null); private set
    private var loads: Job? = null

    init {
        reload()
        viewModelScope.launch { repository.changes.collect { reload() } }
    }

    /** The window being asked for has loaded; another one shows loading, never stale numbers. */
    val loadedWindow: DetailWindow? get() = window?.takeIf { it.end == (endingOn ?: it.today) }

    fun earlier() { window?.let { shown -> endingOn = shift(shown.end, -range.days); reload() } }
    fun later() { window?.let { shown -> endingOn = minOf(shown.today, shift(shown.end, range.days)).takeIf { it != shown.today }; reload() } }
    fun older() { (weights?.page ?: workouts?.page)?.cursor?.let { before = it; reload() } }
    fun latest() { before = null; reload() }

    fun reload() {
        loads?.cancel()
        loads = viewModelScope.launch(Dispatchers.IO) {
            val db = repository.database(profileID)
            if (kind != ProgressDetailKind.Workouts) try {
                val (zone, today) = progressToday(db)
                val end = endingOn ?: today
                val progress = db.progressRange(end, ProgressSnapshot.loadDays(range), includeDailyReports = true)
                val start = ProgressSnapshot.rangeStart(progress, range)
                window = DetailWindow(end, today, ProgressSnapshot(progress, range, zone, today),
                    if (kind == ProgressDetailKind.TopFoods) db.topFoods(start, progress.endLocalDate, 200) else emptyList(),
                    db.hasDays(start), progress.latestWeight)
                windowError = null
            } catch (e: CancellationException) { throw e } catch (_: Exception) { windowError = "Could not load this range. Your diary is preserved." }
            try {
                val zone = db.head().profile.timeZoneID
                fun label(dayID: UUID?, at: java.time.Instant) = dayID?.let { id -> db.read { it.day(id) }?.localDate } ?: diaryDateLabel(at, zone)
                when (kind) {
                    ProgressDetailKind.Weight -> weights = db.weightHistory(before).let { p -> Ledger(p, p.values.associate { it.id to label(it.dayID, it.measuredAt) }) }
                    ProgressDetailKind.Workouts -> workouts = db.workoutHistory(before).let { p -> Ledger(p, p.values.associate { it.id to label(it.dayID, it.performedAt) }) }
                    else -> Unit
                }
                ledgerError = null
            } catch (e: CancellationException) { throw e } catch (_: Exception) {
                ledgerError = if (kind == ProgressDetailKind.Weight) "Could not load measurements. Your diary is preserved." else "Could not load workouts. Your diary is preserved."
            }
        }
    }

    /** Deletes one weigh-in at the revision on screen; a stale or failed delete says so and keeps the ledger. */
    fun delete(entry: WeightEntry) {
        viewModelScope.launch(Dispatchers.IO) {
            try { repository.database(profileID).deleteWeight(entry.id, entry.revision) }
            catch (e: CancellationException) { throw e } catch (_: Exception) { ledgerError = "Could not delete this weight. It may have changed elsewhere, such as in Coach." }
        }
    }

    private fun shift(date: String, days: Int) = LocalDate.parse(date).plusDays(days.toLong()).toString()
}

private fun format(date: String, pattern: String) =
    runCatching { LocalDate.parse(date).format(DateTimeFormatter.ofPattern(pattern, Locale.US)) }.getOrDefault(date)

private fun number(value: Double) = NumberFormat.getNumberInstance(Locale.US).format(value)

/** iOS `weightPrompt`: "Weight · 72.5 kg · Fri 23 Oct". */
internal fun weightExcerpt(entry: WeightEntry, localDate: String) = "Weight · ${number(entry.value)} ${entry.unit} · ${format(localDate, "EEE d MMM")}"

/** A detail screen: the card's chart at full width over a window you page by range (buttons or a horizontal swipe). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProgressDetailScreen(
    model: ProgressDetailViewModel,
    onBack: () -> Unit,
    onEditWeight: (UUID) -> Unit,
    onAddWeight: () -> Unit,
    onAddWorkout: (localDate: String) -> Unit,
    onOpenWorkout: (UUID) -> Unit,
    onAskPip: (AskPip) -> Unit,
) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(model.kind.title, Modifier.semantics { heading() }) },
                navigationIcon = {
                    IconButton(onBack, Modifier.testTag("progressDetailBack")) { Icon(painterResource(R.drawable.ic_arrow_back), contentDescription = "Back") }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background),
            )
        },
        containerColor = MaterialTheme.colorScheme.background,
    ) { padding ->
        LazyColumn(
            Modifier.fillMaxSize().padding(padding).testTag("progressDetailList"),
            contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 4.dp, bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            if (model.kind == ProgressDetailKind.Workouts) {
                workoutList(model, onAddWorkout, onOpenWorkout, onAskPip)
                return@LazyColumn
            }
            item(key = "pager") { Pager(model) }
            val window = model.loadedWindow
            when {
                window != null -> content(model, window, onEditWeight, onAddWeight, onAskPip)
                model.windowError != null -> item(key = "error") {
                    Column {
                        Text(model.windowError!!, color = MaterialTheme.colorScheme.error)
                        TextButton(model::reload, Modifier.heightIn(min = 48.dp)) { Text("Retry") }
                    }
                }
                else -> item(key = "loading") { CircularProgressIndicator(Modifier.padding(24.dp)) }
            }
        }
    }
}

/** iOS's Earlier / dates / Later row; Earlier stops at the diary's first day. */
@Composable
private fun Pager(model: ProgressDetailViewModel) {
    val window = model.loadedWindow
    val shown = model.window
    val dates = shown?.let {
        val start = LocalDate.parse(it.end).minusDays(model.range.days - 1L).toString()
        "${format(start, if (start.take(4) == it.end.take(4)) "MMM d" else "MMM d, yyyy")} – ${format(it.end, "MMM d, yyyy")}"
    }.orEmpty()
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        TextButton(model::earlier, Modifier.heightIn(min = 48.dp).testTag("progressDetailEarlier"), enabled = window?.hasEarlier == true) {
            Icon(painterResource(R.drawable.ic_chevron_left), contentDescription = null)
            Text("Earlier")
        }
        Text(dates, Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
        TextButton(model::later, Modifier.heightIn(min = 48.dp).testTag("progressDetailLater"), enabled = window != null && window.end < window.today) {
            Text("Later")
            Icon(painterResource(R.drawable.ic_chevron_right), contentDescription = null)
        }
    }
}

/** A horizontal swipe on a chart pages by one window: right for earlier, left for later. */
private fun Modifier.swipePaging(model: ProgressDetailViewModel) = pointerInput(model) {
    var dx = 0f
    detectHorizontalDragGestures(onDragStart = { dx = 0f }, onDragEnd = {
        val window = model.loadedWindow
        if (dx > 80.dp.toPx() && window?.hasEarlier == true) model.earlier()
        else if (dx < -80.dp.toPx() && window != null && window.end < window.today) model.later()
    }) { _, amount -> dx += amount }
}

private fun LazyListScope.content(
    model: ProgressDetailViewModel, window: DetailWindow, onEditWeight: (UUID) -> Unit, onAddWeight: () -> Unit, onAskPip: (AskPip) -> Unit,
) {
    val snapshot = window.snapshot
    when (model.kind) {
        ProgressDetailKind.Calories -> {
            item(key = "chart") {
                var selected by remember(window) { mutableStateOf<Int?>(null) }
                Column(Modifier.swipePaging(model)) { CaloriesCard(snapshot, selected) { selected = it } }
            }
            item(key = "daysTitle") { SectionTitle("Days") }
            items(snapshot.days.reversed(), key = { it.localDate }) { day -> DayRow(dayTitle(day), ProgressInsights.plainResult(day), ProgressInsights.band(day)) }
        }
        ProgressDetailKind.Macros -> {
            item(key = "card") { MacrosCard(snapshot, null, large = false) }
            val goal = snapshot.goal?.targets
            val a = snapshot.averages
            items(listOf(Triple("Protein", a.protein, goal?.protein), Triple("Carbs", a.carbs, goal?.carbs), Triple("Fat", a.fat, goal?.fat)), key = { it.first }) {
                DayRow(it.first, ProgressInsights.plainMacro(it.second, it.third))
            }
            item(key = "footer") { Footnote("Averages use complete days only.") }
        }
        ProgressDetailKind.Calendar -> {
            items(ProgressInsights.calendarRows(snapshot.days, snapshot.range), key = { it.title }) { CalendarRowView(it) }
            item(key = "footer") { Footnote("Teal: near your target. Orange: further off. Grey: logged, not judged yet. Empty: no log.") }
        }
        ProgressDetailKind.Burn -> {
            item(key = "card") { BurnCard(snapshot) }
            item(key = "howTitle") { SectionTitle("How it's worked out") }
            val complete = snapshot.loadedDays.filter { it.status == DayStatus.Closed }.mapNotNull { it.foodTotals?.kcal }
            item(key = "complete") { DayRow("Complete days", complete.size.toString()) }
            item(key = "intake") { DayRow("Average intake", if (complete.isEmpty()) "—" else kcal(complete.average())) }
            item(key = "weighIns") { DayRow("Weigh-ins", snapshot.loadedTrend.size.toString()) }
            ProgressInsights.slopePerDay(snapshot.loadedTrend)?.let { slope ->
                item(key = "change") {
                    DayRow("Weight change", "${NumberFormat.getNumberInstance(Locale.US).apply { minimumFractionDigits = 2; maximumFractionDigits = 2 }.format(slope * 7)} kg a week")
                }
            }
            item(key = "footer") { Footnote("Each kilogram of body weight stores about 7,700 kcal. Burn = average intake minus the energy your trend stored or released per day.") }
        }
        ProgressDetailKind.TopFoods -> {
            if (window.foods.isEmpty()) item(key = "empty") { ProgressPlaceholder(R.drawable.ic_restaurant, "No saved foods with known calories in this range.") }
            items(window.foods.withIndex().toList(), key = { it.index }) { (_, food) ->
                DayRow(food.name, "${if (food.count == 1) "once" else "${food.count} times"} · ${kcal(food.kcal)}")
            }
            item(key = "footer") { Footnote("Foods with unknown calories and meals still being analyzed are left out.") }
        }
        ProgressDetailKind.Weight -> weightDetail(model, window, onEditWeight, onAddWeight, onAskPip)
        ProgressDetailKind.Workouts -> Unit
    }
}

@Composable
private fun Footnote(text: String) =
    Text(text, Modifier.padding(top = 4.dp), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)

/** iOS `weightDetail`: the latest measurement, the window's weigh-ins with a spoken summary, then the measurement ledger. */
private fun LazyListScope.weightDetail(
    model: ProgressDetailViewModel, window: DetailWindow, onEditWeight: (UUID) -> Unit, onAddWeight: () -> Unit, onAskPip: (AskPip) -> Unit,
) {
    window.latestWeight?.let { latest ->
        item(key = "latest") {
            ProgressCard(color = com.yakov103.mivu.ui.theme.MivuTheme.colors.summarySurface) {
                Column(Modifier.semantics(mergeDescendants = true) {}) {
                    Text("Latest measurement", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text("${number(latest.record.value)} ${latest.record.unit}", style = MaterialTheme.typography.displaySmall.tabular(),
                        fontWeight = FontWeight.SemiBold, color = com.yakov103.mivu.ui.theme.MivuTheme.colors.protein)
                    Text(latest.localDate, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
    item(key = "chart") {
        // iOS `weights`: one kilogram value per measured date in the window.
        val weights = window.snapshot.let { s -> s.loadedTrend.filter { it.localDate >= (s.days.firstOrNull()?.localDate ?: "") } }
        var selected by remember(window) { mutableStateOf<Int?>(null) }
        ProgressCard(Modifier.swipePaging(model)) {
            Text("Measurements · ${model.range.title}", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            if (weights.isEmpty()) Text("Insufficient measurements for a weight trend.")
            else {
                TrendChart(weights.map { it.localDate to it.raw }, weightChartSummary(weights.map { it.localDate to it.raw }, window.snapshot), 180.dp,
                    Modifier.testTag("weightChart"), selected = selected, onSelect = { selected = it })
                if (weights.size < 2) Text("One measurement; a trend needs another date.")
                selected?.let { weights.getOrNull(it) }?.let {
                    Text("Selected ${it.localDate}: ${oneDecimal(it.raw)} kg", Modifier.testTag("selectedWeight"))
                }
            }
        }
    }
    ledgerSection(model, "Measurement ledger", "Older measurements", "Latest measurements", "Retry loading measurements",
        model.weights?.page?.values?.sortedByDescending { it.measuredAt }.orEmpty(), key = { it.id }) { entry ->
        val date = model.weights?.dates?.get(entry.id).orEmpty()
        WeightRow(entry, date, onEdit = { onEditWeight(entry.id) }, onAskPip = { onAskPip(AskPip.Weight(entry.id, weightExcerpt(entry, date))) },
            onDelete = { model.delete(entry) })
    }
    item(key = "addWeight") {
        OutlinedButton(onAddWeight, Modifier.heightIn(min = 48.dp).testTag("logWeight")) {
            Icon(painterResource(R.drawable.ic_add), contentDescription = null)
            Text("Add weight manually", Modifier.padding(start = 8.dp))
        }
    }
}

/** iOS `weightSummary`: the count, seven-day average and change, then every measured date. */
private fun weightChartSummary(points: List<Pair<String, Double>>, snapshot: ProgressSnapshot): String {
    val samples = points.joinToString("; ") { "${it.first}: ${oneDecimal(it.second)} kg" }
    val trend = snapshot.loadedTrend
    val last = trend.lastOrNull()
    val change = last?.let { l -> trend.lastOrNull { ProgressInsights.days(it.localDate, l.localDate) >= 7 }?.let { l.trend - it.trend } }
    return "Weight chart: ${points.size} measured dates. " +
        (last?.let { "Trend ${oneDecimal(it.trend)} kg on ${it.localDate}." } ?: "Trend: insufficient data.") + " " +
        (change?.let { "Seven-day change ${oneDecimal(it)} kg." } ?: "Seven-day change: insufficient data.") + " " + samples
}

private fun <T> LazyListScope.ledgerSection(
    model: ProgressDetailViewModel, title: String, older: String, latest: String, retry: String, rows: List<T>, key: (T) -> Any,
    row: @Composable (T) -> Unit,
) {
    item(key = "ledgerTitle") { SectionTitle(title) }
    model.ledgerError?.let { message ->
        item(key = "ledgerError") {
            Column {
                Text(message, color = MaterialTheme.colorScheme.error)
                TextButton(model::reload, Modifier.heightIn(min = 48.dp)) { Text(retry) }
            }
        }
    }
    items(rows, key = key) { row(it) }
    val page = model.weights?.page ?: model.workouts?.page
    if (page?.hasMore == true) item(key = "older") { TextButton(model::older, Modifier.heightIn(min = 48.dp)) { Text(older) } }
    if (model.before != null) item(key = "latest") { TextButton(model::latest, Modifier.heightIn(min = 48.dp)) { Text(latest) } }
}

/** A weigh-in: tap to edit; Ask Pip and Delete beside it, and as TalkBack actions on the row. */
@Composable
private fun WeightRow(entry: WeightEntry, date: String, onEdit: () -> Unit, onAskPip: () -> Unit, onDelete: () -> Unit) {
    var confirming by rememberSaveable { mutableStateOf(false) }
    Row(verticalAlignment = Alignment.CenterVertically) {
        Row(
            Modifier.weight(1f).heightIn(min = 48.dp).clickable(onClickLabel = "Edit weight", onClick = onEdit).testTag("editWeight")
                .semantics(mergeDescendants = true) {
                    customActions = listOf(CustomAccessibilityAction("Ask Pip") { onAskPip(); true },
                        CustomAccessibilityAction("Delete weight") { confirming = true; true })
                },
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(date, Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
            Text("${number(entry.value)} ${entry.unit}", style = MaterialTheme.typography.bodyLarge.tabular())
        }
        IconButton(onAskPip, Modifier.testTag("askPipWeight")) { Icon(painterResource(R.drawable.ic_auto_awesome), contentDescription = "Ask Pip") }
        IconButton({ confirming = true }, Modifier.testTag("deleteWeight")) { Icon(painterResource(R.drawable.ic_delete), contentDescription = "Delete weight") }
    }
    if (confirming) AlertDialog(
        onDismissRequest = { confirming = false },
        title = { Text("Delete the weight on $date?") },
        text = { Text("This removes only this measurement. Meals, workouts and other weights are preserved.") },
        confirmButton = {
            TextButton({ confirming = false; onDelete() }, Modifier.heightIn(min = 48.dp)) { Text("Delete weight", color = MaterialTheme.colorScheme.error) }
        },
        dismissButton = { TextButton({ confirming = false }, Modifier.heightIn(min = 48.dp)) { Text("Cancel") } },
    )
}

/** iOS `workoutList`: add, then every workout newest first (opens its detail; Ask Pip beside it), paged by 30. */
private fun LazyListScope.workoutList(model: ProgressDetailViewModel, onAdd: (String) -> Unit, onOpen: (UUID) -> Unit, onAskPip: (AskPip) -> Unit) {
    item(key = "add") {
        OutlinedButton({ onAdd(model.window?.today ?: LocalDate.now().toString()) }, Modifier.heightIn(min = 48.dp).testTag("logWorkout")) {
            Icon(painterResource(R.drawable.ic_add), contentDescription = null)
            Text("Add workout manually", Modifier.padding(start = 8.dp))
        }
    }
    val ledger = model.workouts
    if (ledger == null && model.ledgerError == null) item(key = "loading") { CircularProgressIndicator(Modifier.padding(24.dp)) }
    if (ledger != null && ledger.page.values.isEmpty()) item(key = "empty") {
        Text("No workouts recorded yet.", color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
    ledgerSection(model, "Workouts", "Older workouts", "Latest workouts", "Retry loading workouts",
        ledger?.page?.values?.sortedByDescending { it.performedAt }.orEmpty(), key = { it.id }) { session ->
        val date = ledger?.dates?.get(session.id).orEmpty()
        val ask = { onAskPip(AskPip.Workout(session.id, workoutExcerpt(session, date))) }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(
                Modifier.weight(1f).heightIn(min = 48.dp).clickable { onOpen(session.id) }.testTag("workoutRow")
                    .semantics(mergeDescendants = true) { customActions = listOf(CustomAccessibilityAction("Ask Pip") { ask(); true }) },
                verticalArrangement = Arrangement.Center,
            ) {
                Text(session.kind.title, style = MaterialTheme.typography.titleMedium)
                Text("$date · ${session.durationMinutes} minutes", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            IconButton(ask, Modifier.testTag("askPipWorkout")) { Icon(painterResource(R.drawable.ic_auto_awesome), contentDescription = "Ask Pip") }
        }
    }
}
