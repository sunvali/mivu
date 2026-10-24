package com.yakov103.mivu.ui.coach

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.yakov103.mivu.R
import com.yakov103.mivu.diary.CoachDayCursor
import com.yakov103.mivu.diary.CoachDayPage
import com.yakov103.mivu.diary.CoachSegmentSummary
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

// Port of ios/Mivu/Coach/CoachHistoryView.swift: CoachHistoryModel and the Chat history list with its date sheet, as an
// M3 screen with a DatePickerDialog. Every string is the iOS one.

/** iOS CoachHistoryModel: one bounded page at a time; a generation counter drops late results. Main thread only. */
class CoachHistoryModel(private val load: suspend (date: String?, before: CoachDayCursor?) -> CoachDayPage) {
    data class State(
        val page: CoachDayPage? = null,
        val dateFilter: String? = null,
        val isLoading: Boolean = false,
        val errorMessage: String? = null,
    )

    private val _state = MutableStateFlow(State())
    val state: StateFlow<State> = _state.asStateFlow()
    private var generation = 0L

    fun invalidate() {
        generation++
        _state.update { it.copy(page = null, errorMessage = null, isLoading = false) }
    }

    suspend fun show(date: String? = null) {
        generation++
        _state.update { it.copy(page = null, dateFilter = date, errorMessage = null) }
        fetch(null, generation)
    }

    /** The next page replaces this one, so each screenful stays bounded; ignored while a load runs. */
    suspend fun earlier() {
        val s = _state.value
        if (s.isLoading || s.page?.hasMore != true) return
        fetch(s.page.cursor ?: return, generation)
    }

    private suspend fun fetch(before: CoachDayCursor?, operation: Long) {
        val filter = _state.value.dateFilter
        _state.update { it.copy(isLoading = true) }
        try {
            val result = load(filter, before)
            if (generation == operation && _state.value.dateFilter == filter) _state.update { it.copy(page = result, errorMessage = null) }
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            if (generation == operation && _state.value.dateFilter == filter) {
                _state.update { it.copy(errorMessage = "Chat history is unavailable. Try again.") }
            }
        } finally {
            if (generation == operation) _state.update { it.copy(isLoading = false) }
        }
    }
}

/** Chat history: newest conversation first; a row opens Coach at its first message. [zone] is the profile's. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CoachHistoryScreen(model: CoachViewModel, zone: ZoneId, onOpen: (CoachSeekTarget.Turn) -> Unit, onClose: () -> Unit) {
    val history = remember(model) { CoachHistoryModel(model::historyPage) }
    val state by history.state.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    var choosing by rememberSaveable { mutableStateOf(false) }
    LaunchedEffect(history) { history.show() }
    DisposableEffect(history) { onDispose { history.invalidate() } }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Chat history", Modifier.semantics { heading() }) },
                navigationIcon = {
                    IconButton(onClose) { Icon(painterResource(R.drawable.ic_arrow_back), contentDescription = "Navigate up") }
                },
                actions = {
                    IconButton({ choosing = true }) { Icon(painterResource(R.drawable.ic_calendar), contentDescription = "Choose date") }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background),
            )
        },
        containerColor = MaterialTheme.colorScheme.background,
    ) { padding ->
        LazyColumn(Modifier.fillMaxSize().padding(padding).testTag("coachHistoryList")) {
            state.dateFilter?.let { date ->
                item {
                    ListItem(headlineContent = { Text("Selected date") }, trailingContent = { Text(date) })
                    TextButton({ scope.launch { history.show() } }, Modifier.padding(horizontal = 8.dp).heightIn(min = 48.dp)) {
                        Text("Show all chat history")
                    }
                    HorizontalDivider()
                }
            }
            val page = state.page
            when {
                state.errorMessage != null -> item {
                    Message("History unavailable", state.errorMessage!!) {
                        TextButton({ scope.launch { history.show(state.dateFilter) } }, Modifier.heightIn(min = 48.dp)) { Text("Try again") }
                    }
                }
                state.isLoading && page == null -> item {
                    Column(Modifier.fillMaxWidth().padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        CircularProgressIndicator()
                        Text("Loading chat history", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                page?.segments?.isEmpty() == true -> item {
                    val date = state.dateFilter
                    Message(if (date == null) "No saved chat" else "No chat for this date",
                        date?.let { "No saved conversation is labeled $it." } ?: "Your saved conversations will appear here.")
                }
            }
            items(page?.segments.orEmpty(), key = { it.segmentID }) { row ->
                Row(row) { onOpen(CoachSeekTarget.Turn(row.firstTurnID)) }
                HorizontalDivider()
            }
            if (page?.hasMore == true) item {
                OutlinedButton({ scope.launch { history.earlier() } }, Modifier.fillMaxWidth().padding(16.dp).heightIn(min = 48.dp),
                    enabled = !state.isLoading) { Text("Earlier conversations") }
            }
        }
    }
    if (choosing) ChooseDate(zone, onDismiss = { choosing = false }) { label ->
        choosing = false
        scope.launch { history.show(label) }
    }
}

@Composable
private fun Row(row: CoachSegmentSummary, onClick: () -> Unit) {
    Column(
        Modifier.fillMaxWidth().clickable(onClickLabel = "Open conversation", role = Role.Button, onClick = onClick).heightIn(min = 64.dp).padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(row.displayLocalDate, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
        Text(captureLabel(row), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(row.preview, style = MaterialTheme.typography.bodyLarge, maxLines = 2, overflow = TextOverflow.Ellipsis)
    }
}

/** iOS ContentUnavailableView: a title, its description and an optional action. */
@Composable
private fun Message(title: String, description: String, action: @Composable () -> Unit = {}) {
    Column(Modifier.fillMaxWidth().padding(horizontal = 32.dp, vertical = 48.dp), horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Icon(painterResource(R.drawable.ic_coach), null, Modifier.size(48.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(title, Modifier.semantics { heading() }, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold,
            textAlign = TextAlign.Center)
        Text(description, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
        action()
    }
}

/** "24 Oct 2026, 08:12:05 · Europe/London": the first capture in the row's own zone. */
private fun captureLabel(row: CoachSegmentSummary): String {
    val zone = runCatching { ZoneId.of(row.displayTimeZoneID) }.getOrDefault(ZoneOffset.UTC)
    return DateTimeFormatter.ofPattern("d MMM yyyy, HH:mm:ss", Locale.US).withZone(zone).format(row.firstCapturedAt) + " · " +
        row.displayTimeZoneID
}

/** iOS date sheet: the picked calendar date is the label, as read in the profile zone. DatePicker dates are UTC midnights. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ChooseDate(zone: ZoneId, onDismiss: () -> Unit, onChoose: (String) -> Unit) {
    val picker = rememberDatePickerState(LocalDate.now(zone).atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli())
    DatePickerDialog(
        onDismissRequest = onDismiss,
        confirmButton = {
            TextButton({ picker.selectedDateMillis?.let { onChoose(Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate().toString()) } },
                enabled = picker.selectedDateMillis != null) { Text("Show date") }
        },
        dismissButton = { TextButton(onDismiss) { Text("Cancel") } },
    ) {
        // The note lives in the title slot: a sibling of DatePicker in the dialog draws over the title.
        DatePicker(picker, Modifier.weight(1f, fill = false), title = {
            Column(Modifier.padding(start = 24.dp, end = 12.dp, top = 16.dp)) {
                Text("Conversation date")
                Text("Choose the date shown in your conversation. Separate visits remain separate choices.",
                    style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        })
    }
}
