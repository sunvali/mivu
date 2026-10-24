@file:UseSerializers(SwiftUUID::class, SwiftDate::class)

package com.yakov103.mivu.ui.coach

import android.database.SQLException
import android.net.Uri
import androidx.annotation.VisibleForTesting
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.yakov103.mivu.analysis.ResponsesClient
import com.yakov103.mivu.coach.CoachActivity
import com.yakov103.mivu.coach.CoachEngine
import com.yakov103.mivu.coach.CoachError
import com.yakov103.mivu.coach.CoachReplyLines
import com.yakov103.mivu.connection.SessionError
import com.yakov103.mivu.diary.CoachTurn
import com.yakov103.mivu.diary.CoachTurnState
import com.yakov103.mivu.diary.MealPhoto
import com.yakov103.mivu.diary.PhotoRole
import com.yakov103.mivu.diary.Reconciliation
import com.yakov103.mivu.diary.SwiftDate
import com.yakov103.mivu.diary.SwiftJson
import com.yakov103.mivu.diary.SwiftUUID
import com.yakov103.mivu.diary.goalOn
import com.yakov103.mivu.diary.reconcileCoachCapture
import com.yakov103.mivu.pip.CompanionContext
import com.yakov103.mivu.pip.CompanionEvent
import com.yakov103.mivu.pip.CompanionOutput
import com.yakov103.mivu.pip.CompanionPose
import com.yakov103.mivu.pip.CompanionPresentation
import com.yakov103.mivu.pip.CompanionSubmission
import com.yakov103.mivu.pip.CompanionSurface
import com.yakov103.mivu.pip.CompanionTouch
import com.yakov103.mivu.pip.MotionPolicy.Playback
import com.yakov103.mivu.ui.composer.MealComposerViewModel.Companion.MAX_PHOTOS
import com.yakov103.mivu.ui.composer.MealComposerViewModel.Companion.MAX_TEXT
import java.io.File
import java.io.IOException
import java.text.NumberFormat
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.combine
import kotlinx.serialization.Serializable
import kotlinx.serialization.UseSerializers
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

/** The composer's unsent message: text, prepared photo files, an optional quote and the ID its capture will carry. */
@Serializable
data class CoachDraft(
    val text: String = "",
    val photos: List<String> = emptyList(),
    val reply: CoachReply? = null,
    val submissionID: UUID = UUID.randomUUID(),
) {
    val canSend: Boolean get() = text.isNotBlank() || photos.isNotEmpty()

    /** Nothing a handoff may replace: no text, photos or quote. */
    val isEmpty: Boolean get() = text.isBlank() && photos.isEmpty() && reply == null
}

/**
 * A send that may have committed: the draft and the context it went with, kept until the store answers, so the reconcile
 * rebuilds the exact payload (photo IDs are their file names, created at the capture instant).
 */
@Serializable
private data class CoachAttempt(val draft: CoachDraft, val context: CoachCaptureContext) {
    fun payload() = CoachSubmissionPayload(draft.submissionID, draft.text, draft.photos.map {
        MealPhoto(UUID.fromString(File(it).nameWithoutExtension), File(it).readBytes(), context.capturedAt, PhotoRole.unspecified)
    }, context, reply = draft.reply)
}

/** iOS `CoachViewModel.message(for:)`, each string verbatim ("iPhone" becomes "phone" where it appears). */
fun coachMessage(error: Throwable): String = when {
    error == ResponsesClient.Failure.UsageUnavailable -> "ChatGPT is busy right now. Your message is saved; try again soon."
    CoachEngine.isTransient(error) -> "You're offline. Your message is saved and I'll reply when you're back online."
    error is CancellationException || error == SessionError.SessionChanged -> "The connection changed. Your message is saved; tap Try again."
    error == ResponsesClient.Failure.QuotaReached -> "You've reached your ChatGPT usage limit. Your message is saved; see Manage usage in Settings."
    error == DiaryError.StaleRevision -> "Something changed while I was working. Check it, then try again."
    error == DiaryError.InvalidAmountUnitChange -> error.message.orEmpty()
    error == DiaryError.AmbiguousDay -> "Which day is this for?"
    error == CoachError.UngroundedConfirmation -> "I need a little more detail to log that."
    error is SQLException -> "Couldn't save that. Your message is kept; tap Try again." // iOS DiaryError.persistenceFailed
    else -> "Something went wrong. Your message is saved; tap Try again."
}

private val RECOVERY = setOf(CoachTurnState.needsRetry, CoachTurnState.waitingForConnection, CoachTurnState.waitingForNetwork)

class CoachViewModel(
    private val repository: DiaryRepository,
    private val profileID: UUID,
    private val drain: () -> Unit,
    val isConnected: () -> Boolean,
    val activity: StateFlow<Pair<UUID, CoachActivity>?>,
    private val saved: SavedStateHandle,
    /** Prepares a picked photo as a JPEG file in the draft's folder (`preparePhoto`); off the main thread. */
    private val prepare: (Uri) -> File = { throw IOException("photo import unavailable") },
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
    private val _undoing = MutableStateFlow(emptySet<String>())

    val timeline: StateFlow<CoachTimelineState> = _timeline.asStateFlow()

    /** Receipts whose Undo is being written; their buttons wait. */
    val undoing: StateFlow<Set<String>> = _undoing.asStateFlow()

    /** The last failed action, shown until the next one succeeds. */
    val message: StateFlow<String?> = _message.asStateFlow()

    private val _draft = MutableStateFlow(
        saved.get<String>(DRAFT)?.let { runCatching { SwiftJson.decodeFromString(CoachDraft.serializer(), it) }.getOrNull() }
            ?.let { it.copy(photos = it.photos.filter { path -> File(path).exists() }) } // the cache may be cleared
            ?: CoachDraft(),
    )
    val draft: StateFlow<CoachDraft> = _draft.asStateFlow()
    private var attempt: CoachAttempt? = saved.get<String>(ATTEMPT)?.let { runCatching { SwiftJson.decodeFromString(CoachAttempt.serializer(), it) }.getOrNull() }
    private val _sending = MutableStateFlow(false)
    val sending: StateFlow<Boolean> = _sending.asStateFlow()
    private val _importing = MutableStateFlow(false)
    val importing: StateFlow<Boolean> = _importing.asStateFlow()
    private val _logging = MutableStateFlow<String?>(null)

    /** "Logging to today · 2,100 kcal goal": the active day and its kcal goal, whichever exist. */
    val logging: StateFlow<String?> = _logging.asStateFlow()

    private val presentation = CompanionPresentation(System::currentTimeMillis).apply { attach(profileID) }
    private var playback = Playback.Hidden
    private var typing = false
    private var caret = 0
    private var deadline: Job? = null
    private val _companion = MutableStateFlow(CompanionOutput(CompanionPose.Resting, Playback.Hidden, null))

    /** Pip's pose on Coach, resolved from the composer, the worker and the latest exchange. */
    val companion: StateFlow<CompanionOutput> = _companion.asStateFlow()

    init {
        viewModelScope.launch {
            // Subscribed before the first read, so a change committed meanwhile is not missed.
            repository.changes.onSubscription { emit(Unit) }.conflate().collect {
                if (loaded && error == null) refresh() else replace()
                readLogging()
            }
        }
        viewModelScope.launch { combine(activity, _message, _sending, _timeline) { _, _, _, _ -> }.collect { resolveCompanion() } }
    }

    fun updateText(value: String) { if (!_sending.value) store(_draft.value.copy(text = value.take(MAX_TEXT))) }

    /** Starts an unsent message for the person to finish; never replaces text they already typed. */
    fun prefill(text: String): Boolean {
        if (_sending.value || _draft.value.text.isNotBlank()) return false
        store(_draft.value.copy(text = text.take(MAX_TEXT)))
        return true
    }

    /**
     * A Diary handoff quote, then its unsent [draft] (iOS `startReply` then `prefill`). The quote never replaces a message
     * already started (text, photos or a quote); false when it was not taken. A null [reply] only prefills.
     */
    fun startReply(reply: CoachReply?, draft: String? = null): Boolean {
        val started = reply != null && reply.excerpt.isNotBlank() && !_sending.value && _draft.value.isEmpty
        if (started) store(_draft.value.copy(reply = reply!!.copy(excerpt = reply.excerpt.take(280))))
        draft?.let(::prefill)
        return started
    }

    fun cancelReply() { if (!_sending.value) store(_draft.value.copy(reply = null)) }

    fun removePhoto(path: String) {
        if (_sending.value) return
        store(_draft.value.copy(photos = _draft.value.photos - path))
        // A send that may have committed still needs these bytes to reconcile; storeAttempt deletes them once it resolves.
        if (attempt?.draft?.photos?.contains(path) != true) File(path).delete()
    }

    /** iOS `importSelections`: each picked image is prepared off the main thread, up to [MAX_PHOTOS]; the rest are reported. */
    fun importPhotos(uris: List<Uri>) {
        if (_importing.value || _sending.value || uris.isEmpty()) return
        _importing.value = true
        viewModelScope.launch {
            val failed = mutableListOf<Int>()
            val skipped = mutableListOf<Int>()
            try {
                uris.forEachIndexed { index, uri ->
                    if (_draft.value.photos.size >= MAX_PHOTOS) { skipped += index + 1; return@forEachIndexed }
                    try {
                        addPrepared(uri)
                    } catch (e: CancellationException) {
                        throw e
                    } catch (_: Exception) {
                        failed += index + 1
                    }
                }
            } finally {
                _importing.value = false
                // The meal composer's words (MealComposerScreen's limit alert), shown in the caption.
                fun photos(positions: List<Int>) = positions.joinToString { "Photo $it" }
                if (failed.isNotEmpty() || skipped.isNotEmpty()) _message.value = listOfNotNull(
                    failed.takeIf { it.isNotEmpty() }?.let { "${photos(it)} from this selection could not be imported." },
                    skipped.takeIf { it.isNotEmpty() }?.let { "${photos(it)} ${if (it.size == 1) "was" else "were"} not added: a meal holds up to 8 photos." },
                ).joinToString(" ")
            }
        }
    }

    /**
     * A camera capture, prepared on the same path as a picked photo; the raw [file] is deleted either way. A failure keeps
     * the note and the other photos and says so in iOS words.
     */
    fun addCapturedPhoto(file: File) {
        if (_importing.value || _sending.value || _draft.value.photos.size >= MAX_PHOTOS) { file.delete(); return }
        _importing.value = true
        viewModelScope.launch {
            try {
                addPrepared(Uri.fromFile(file))
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                _message.value = PHOTO_NOT_TAKEN
            } finally {
                file.delete()
                _importing.value = false
            }
        }
    }

    private suspend fun addPrepared(uri: Uri) {
        val file = withContext(Dispatchers.IO) { prepare(uri) }
        store(_draft.value.copy(photos = _draft.value.photos + file.path))
        // One curious look per draft: the event is keyed by the draft's submission.
        presentation.receive(CompanionEvent(profileID, _draft.value.submissionID, CompanionEvent.Kind.PhotoAdded, System.currentTimeMillis()))
        resolveCompanion()
    }

    /** Saves the draft as a Coach turn; false when there is nothing to send or a send or import is running. */
    fun send(): Boolean = sendJob() != null

    /** Where Pip may move on screen: the motion policy, including the screen's own covering picker or sheet. */
    fun reportPlayback(playback: Playback) {
        if (this.playback == playback) return
        this.playback = playback
        resolveCompanion()
    }

    /** The field's focus, voice listening, and the caret's place across the field (0...60) for Pip's gaze. */
    fun reportComposer(focused: Boolean, listening: Boolean, caret: Int) {
        val typing = focused || listening
        if (typing == this.typing && caret == this.caret) return
        this.typing = typing
        this.caret = caret
        resolveCompanion()
    }

    /** False when the touch cannot start a reaction: the caller only twitches an ear. */
    fun touchPip(kind: CompanionTouch): Boolean = presentation.touch(kind).also { if (it) resolveCompanion() }

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

    /** iOS sendTap: anything being composed is set aside for the one-tap message and put back afterwards. */
    private fun sendTap(text: String, reply: CoachReply) {
        if (_sending.value || _importing.value) return
        val kept = _draft.value
        val composing = kept.canSend || kept.reply != null
        store(if (composing) CoachDraft(text, reply = reply) else kept.copy(text = text, reply = reply))
        val job = sendJob() ?: return store(kept)
        if (composing) viewModelScope.launch { job.join(); store(kept) }
    }

    private fun sendJob(): Job? {
        val draft = _draft.value
        if (_sending.value || _importing.value || !draft.canSend) return null
        _sending.value = true // the composer is disabled while sending, so the draft cannot change underneath
        return viewModelScope.launch {
            try {
                val turn = capture(draft)
                _draft.value.photos.forEach { File(it).delete() } // the turn holds the bytes now
                store(CoachDraft())
                storeAttempt(null)
                _message.value = null
                drain()
                val now = System.currentTimeMillis()
                presentation.receive(CompanionSubmission(profileID, turn.id, now))
                presentation.receive(CompanionEvent(profileID, turn.id, CompanionEvent.Kind.Saved, now))
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _message.value = failureMessage(e) // iOS performSend: the input is still here, and nothing claims it saved
            } finally {
                _sending.value = false
                resolveCompanion()
            }
        }
    }

    /**
     * Saves [start] against the current head, rebuilding the context once when the head moved. An uncertain failure is
     * reconciled with the same payload: a committed capture counts as sent, so it is never saved twice.
     */
    private suspend fun capture(start: CoachDraft): CoachTurn {
        var draft = start
        attempt?.let { previous ->
            // An earlier send may have committed: ask the store about that exact payload before sending again.
            val prior = try {
                read { reconcileCoachCapture(previous.payload()) }
            } catch (_: IOException) {
                // Its photos are gone (the cache was cleared): the submission ID is the identity, so a stored turn is this one.
                read { coachTurn(previous.draft.submissionID) }?.let { Reconciliation.Accepted(it) } ?: Reconciliation.Absent
            }
            when (prior) {
                is Reconciliation.Accepted -> if (previous.draft == draft) return prior.turn else if (draft.submissionID == previous.draft.submissionID) {
                    draft = draft.copy(submissionID = UUID.randomUUID()).also(::store) // edited since: a new message
                }
                Reconciliation.ConflictingPayload -> {
                    store(draft.copy(submissionID = UUID.randomUUID()))
                    storeAttempt(null)
                    throw DiaryError.StaleRevision
                }
                Reconciliation.Absent -> Unit // nothing committed: the same ID is free
            }
            storeAttempt(null)
        }
        for (round in 0..1) {
            val (context, revision) = read {
                val h = head()
                CoachCaptureContext(Instant.now().truncatedTo(ChronoUnit.SECONDS), h.profile.timeZoneID, h.activeDayID, h.previousDayConfirmedAt,
                    h.activeConversationSegmentID) to h.revision
            }
            val next = CoachAttempt(draft, context).also(::storeAttempt) // kept before the write, so a lost answer can be reconciled
            try {
                return read { beforeCaptureForTest?.invoke(); captureCoachSubmission(next.payload(), revision).also { afterCaptureForTest?.invoke() } }
            } catch (e: CancellationException) {
                throw e
            } catch (e: DiaryError.StaleRevision) {
                if (round == 1) throw e // the transaction refused before writing: rebuild the context once
            } catch (e: Exception) {
                val prior = runCatching { read { reconcileCoachCapture(next.payload()) } }.getOrNull()
                if (prior is Reconciliation.Accepted) return prior.turn
                throw e
            }
        }
        error("unreachable")
    }

    private fun store(draft: CoachDraft) {
        _draft.value = draft
        saved[DRAFT] = SwiftJson.encodeToString(CoachDraft.serializer(), draft)
    }

    private fun storeAttempt(value: CoachAttempt?) {
        // Photos kept only for the resolved attempt (removed from the draft meanwhile) go with it.
        attempt?.draft?.photos?.filter { it !in _draft.value.photos && value?.draft?.photos?.contains(it) != true }?.forEach { File(it).delete() }
        attempt = value
        saved[ATTEMPT] = value?.let { SwiftJson.encodeToString(CoachAttempt.serializer(), it) }
    }

    private fun resolveCompanion() {
        val state = _timeline.value
        val latest = state.exchanges.lastOrNull()?.takeIf { it.turn.id == state.latestID }?.turn?.state
        val output = presentation.resolve(CompanionContext(CompanionSurface.Coach, isTyping = typing && !_sending.value,
            isProcessing = activity.value != null, needsRecovery = _message.value != null || latest in RECOVERY, playback, caret))
        _companion.value = output
        deadline?.cancel()
        deadline = output.nextDeadline?.let { at -> viewModelScope.launch { delay(at - System.currentTimeMillis()); resolveCompanion() } }
    }

    private suspend fun readLogging() {
        _logging.value = try {
            read {
                read { tx ->
                    val head = tx.head
                    val today = LocalDate.now(ZoneId.of(head.profile.timeZoneID)).toString()
                    val day = head.activeDayID?.let(tx::day)
                    val kcal = goalOn(day?.localDate ?: today, tx.goals())?.targets?.kcal
                    listOfNotNull(day?.let { "Logging to " + CoachReplyLines.dayLabel(it.localDate, today) },
                        kcal?.let { "${NumberFormat.getIntegerInstance().format(it)} kcal goal" }).joinToString(" · ").ifEmpty { null }
                }
            }
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            null
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
        _message.value = coachMessage(e)
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

    companion object {
        private const val DRAFT = "coachDraft"
        private const val ATTEMPT = "coachAttempt"

        /** Runs after the store commits a capture, so a test can lose its acknowledgement. */
        @VisibleForTesting internal var afterCaptureForTest: (() -> Unit)? = null
        /** Runs before the capture writes, so a test can fail a send that never committed. */
        @VisibleForTesting internal var beforeCaptureForTest: (() -> Unit)? = null
    }
}
