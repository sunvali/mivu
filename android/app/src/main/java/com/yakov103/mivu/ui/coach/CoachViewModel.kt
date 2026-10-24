package com.yakov103.mivu.ui.coach

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.yakov103.mivu.coach.CoachActivity
import com.yakov103.mivu.diary.CoachCaptureContext
import com.yakov103.mivu.diary.CoachExchange
import com.yakov103.mivu.diary.CoachPageRequest
import com.yakov103.mivu.diary.CoachReply
import com.yakov103.mivu.diary.CoachSubmissionPayload
import com.yakov103.mivu.diary.DiaryDatabase
import com.yakov103.mivu.diary.DiaryError
import com.yakov103.mivu.diary.DiaryRepository
import com.yakov103.mivu.diary.captureCoachSubmission
import com.yakov103.mivu.diary.chooseCoachDay
import com.yakov103.mivu.diary.coachPage
import com.yakov103.mivu.diary.retryCoachTurn
import com.yakov103.mivu.diary.undoCoachChange
import com.yakov103.mivu.ui.coach.CoachHistoryWindow.Direction
import com.yakov103.mivu.ui.coach.CoachHistoryWindow.EdgeState
import com.yakov103.mivu.ui.today.failureMessage
import java.time.Instant
import java.util.UUID
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.conflate
import kotlinx.coroutines.flow.onSubscription
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

// Port of the iOS CoachViewModel timeline paths (ios/Mivu/Coach/CoachViewModel.swift: answer/sendTap :200-215, chooseDay
// :517, retry :534, undo :700) over the Task 4 window. The window is touched only on the main thread; reads run on IO.

/** What the Coach timeline shows: resident exchanges oldest first, both paging edges, and the conversation's newest turn. */
data class CoachTimelineState(
    val exchanges: List<CoachExchange> = emptyList(),
    val earlier: EdgeState = EdgeState.Exhausted,
    val later: EdgeState = EdgeState.Exhausted,
    /** The conversation's newest turn while the window holds it; question chips and follow-ups show only there. */
    val latestID: UUID? = null,
    val loaded: Boolean = false,
    val error: String? = null,
    /** Local dates of the days turns were captured on, by day ID, for "Log to <date>". */
    val days: Map<UUID, String> = emptyMap(),
)

class CoachViewModel(
    private val repository: DiaryRepository,
    private val profileID: UUID,
    private val drain: () -> Unit,
    val isConnected: () -> Boolean,
    val activity: StateFlow<Pair<UUID, CoachActivity>?>,
    @Suppress("unused") private val saved: SavedStateHandle, // the composer draft (Task 6) lives here
) : ViewModel() {
    private val window = CoachHistoryWindow()
    private val _timeline = MutableStateFlow(CoachTimelineState())
    private val _message = MutableStateFlow<String?>(null)
    private var loaded = false
    private var error: String? = null
    private var visible = emptySet<UUID>()
    private var following = true
    private var generation = 0
    private var days = emptyMap<UUID, String>()
    private var sending = false
    private val _undoing = MutableStateFlow(emptySet<String>())

    val timeline: StateFlow<CoachTimelineState> = _timeline.asStateFlow()

    /** Receipts whose Undo is being written; their buttons wait. */
    val undoing: StateFlow<Set<String>> = _undoing.asStateFlow()

    /** The last failed action, shown until the next one succeeds. */
    val message: StateFlow<String?> = _message.asStateFlow()

    init {
        viewModelScope.launch {
            // Subscribed before the first read, so a change committed meanwhile is not missed.
            repository.changes.onSubscription { emit(Unit) }.conflate().collect { if (loaded && error == null) refresh() else replace() }
        }
    }

    /** The reader's visible rows (pins against eviction) and whether they sit at the newest message. */
    fun viewport(visible: Set<UUID>, atLatest: Boolean) {
        this.visible = visible
        following = atLatest
    }

    fun loadEarlier(visible: Set<UUID>) = load(Direction.earlier, visible)

    fun loadLater(visible: Set<UUID>) = load(Direction.later, visible)

    /** Reads the latest page when the window lacks it (or the last read failed); the screen scrolls after it returns. */
    fun jumpToLatest(): Job = viewModelScope.launch {
        following = true
        if (window.newerCursor == null || error != null) replace()
    }

    /** A direct diary edit, not a chat exchange; the card re-reads availability from the change. */
    fun undo(operationKey: String) {
        if (operationKey in _undoing.value) return // a second tap cannot race the first
        _undoing.value += operationKey
        viewModelScope.launch {
            try { act { undoCoachChange(operationKey) } } finally { _undoing.value -= operationKey }
        }
    }

    fun retry(turnID: UUID) = viewModelScope.launch { if (act { retryCoachTurn(turnID) }) drain() }

    fun chooseDay(turnID: UUID, usePrevious: Boolean) = viewModelScope.launch { if (act { chooseCoachDay(turnID, usePrevious) }) drain() }

    /** Answers Coach's question with one tap: the chosen record is quoted and the label is the message. */
    fun answer(target: CoachReply.Target, label: String, excerpt: String) = sendTap(label, CoachReply(target, excerpt.take(280)))

    /** Asks Coach to finish what an incomplete exchange could not, quoting what already saved. */
    fun finishRest(turnID: UUID) {
        val turn = window.exchanges.firstOrNull { it.turn.id == turnID }?.turn ?: return
        val quoted = turn.assistantText.orEmpty().trim().ifEmpty { "Photo" }.take(280)
        sendTap(turn.text.trim().ifEmpty { "Finish the rest" }, CoachReply(CoachReply.Target.Message(turnID, fromPip = true), quoted))
    }

    /** A Coach photo's bytes, read by ID when its thumbnail is shown; null when it is gone. */
    suspend fun turnPhoto(turnID: UUID, photoID: UUID): ByteArray? = runCatching { read { coachPhotoBytes(turnID, photoID) } }.getOrNull()

    suspend fun mealPhoto(mealID: UUID, photoID: UUID): ByteArray? = runCatching { read { photoBytes(mealID, photoID) } }.getOrNull()

    // iOS sendTap. shortcut: no composer draft exists until Task 6, which sets its draft aside here and puts it back after.
    private fun sendTap(text: String, reply: CoachReply) {
        if (sending) return
        sending = true
        viewModelScope.launch {
            try { if (act { capture(text, reply) }) drain() } finally { sending = false }
        }
    }

    /** Saves a Coach turn against the current head; a head that moved meanwhile is read again once. */
    private fun DiaryDatabase.capture(text: String, reply: CoachReply) {
        val id = UUID.randomUUID()
        val at = Instant.now()
        for (attempt in 0..1) {
            val h = head()
            val context = CoachCaptureContext(at, h.profile.timeZoneID, h.activeDayID, h.previousDayConfirmedAt, h.activeConversationSegmentID)
            try {
                captureCoachSubmission(CoachSubmissionPayload(id, text, emptyList(), context, reply = reply), h.revision)
                return
            } catch (e: DiaryError.StaleRevision) {
                if (attempt == 1) throw e
            }
        }
    }

    /** Runs one write off the main thread; a failure is shown and returns false. */
    private suspend fun act(write: DiaryDatabase.() -> Unit): Boolean = try {
        read(write)
        _message.value = null
        true
    } catch (e: CancellationException) {
        throw e
    } catch (e: Exception) {
        _message.value = failureMessage(e)
        false
    }

    private suspend fun <T> read(block: DiaryDatabase.() -> T): T = withContext(Dispatchers.IO) { repository.database(profileID).block() }

    private fun load(direction: Direction, visible: Set<UUID>) {
        this.visible = visible
        val reservation = window.reserve(direction, visible) ?: return
        publish()
        viewModelScope.launch {
            try {
                if (window.complete(reservation, read { coachPage(reservation.request) })) readDays()
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                window.fail(reservation, "Could not load messages. Try again.")
            } finally {
                window.exited(reservation.id) // the read has returned, so a retired reservation frees its slot
                publish()
            }
        }
    }

    /** Replaces the window with the latest page; in-flight page reads are retired and keep their slots until they exit. */
    private suspend fun replace() {
        window.retireAll()
        if (!window.reserveReplacement(visible)) return
        val page = try {
            read { coachPage(CoachPageRequest.Latest) }
        } catch (e: Exception) {
            window.releaseReplacement() // the read has exited
            if (e is CancellationException) throw e
            error = "Could not load this conversation. Try again."
            loaded = true
            publish()
            return
        }
        window.reset(page)
        generation++
        loaded = true
        error = null
        readDays()
        publish()
    }

    /**
     * iOS change refresh: resident pages are read again by range and updated in place. Newer turns never join a page here;
     * they mark the later edge, which loads as a page while the reader follows the latest (or waits for Jump to latest).
     */
    private suspend fun refresh() {
        val started = generation
        val spans = window.spans
        val cursor = window.newerCursor
        if (spans.isEmpty()) return replace() // an empty conversation has no cursor to page after: read the latest again
        val (reread, hasNewer) = try {
            read {
                spans.associateWith { coachPage(CoachPageRequest.Range(it.first, it.last), CoachHistoryWindow.maximumExchanges).exchanges } to
                    (cursor != null && coachPage(CoachPageRequest.After(cursor), 1).exchanges.isNotEmpty())
            }
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            return // the rows on screen stay; the next change reads again
        }
        if (started != generation) return // a replacement landed meanwhile
        window.refresh(reread, hasNewer)
        readDays()
        publish()
        if (following && hasNewer) load(Direction.later, visible)
    }

    private suspend fun readDays() {
        val missing = window.exchanges.filter { it.turn.needsDayChoice == true }.mapNotNull { it.turn.activeDayID }.filter { it !in days }.toSet()
        if (missing.isEmpty()) return
        days = days + try {
            read { read { tx -> missing.mapNotNull { id -> tx.day(id)?.let { id to it.localDate } }.toMap() } }
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            emptyMap()
        }
    }

    private fun publish() {
        if (!loaded) return
        val exchanges = window.exchanges
        _timeline.value = CoachTimelineState(exchanges, window.edgeState(Direction.earlier), window.edgeState(Direction.later),
            exchanges.lastOrNull()?.turn?.id?.takeIf(window::isLatest), loaded = true, error, days)
    }
}
