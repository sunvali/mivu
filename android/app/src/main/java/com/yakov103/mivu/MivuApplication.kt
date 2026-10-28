package com.yakov103.mivu

import android.app.Application
import android.app.job.JobInfo
import android.app.job.JobScheduler
import android.content.ComponentName
import android.net.ConnectivityManager
import android.net.Network
import androidx.annotation.VisibleForTesting
import com.yakov103.mivu.analysis.GeminiNano
import com.yakov103.mivu.analysis.MealAnalysisWorker
import com.yakov103.mivu.analysis.NutritionTable
import com.yakov103.mivu.analysis.ResponsesClient
import com.yakov103.mivu.analysis.SampleAnalyzer
import com.yakov103.mivu.coach.CoachInferenceInput
import com.yakov103.mivu.coach.CoachInferenceResult
import com.yakov103.mivu.coach.CoachJobService
import com.yakov103.mivu.coach.CoachReplyNotification
import com.yakov103.mivu.coach.CoachWorker
import com.yakov103.mivu.connection.AuthSession
import com.yakov103.mivu.connection.ChatGPTConnection
import com.yakov103.mivu.connection.CredentialStore
import com.yakov103.mivu.diary.Bootstrap
import com.yakov103.mivu.day.MorningReminder
import com.yakov103.mivu.diary.DayCutoff
import com.yakov103.mivu.diary.CoachTurnState
import com.yakov103.mivu.diary.DiaryRepository
import com.yakov103.mivu.diary.rollOverDay
import com.yakov103.mivu.quick.QuickAction
import com.yakov103.mivu.widget.CaloriesWidget
import com.yakov103.mivu.widget.WidgetSnapshot
import com.yakov103.mivu.widget.widgetSnapshot
import java.time.Instant
import java.time.ZoneId
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.conflate
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.merge
import kotlinx.coroutines.flow.onStart
import kotlinx.coroutines.flow.filterIsInstance
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonObject

class MivuApplication : Application() {
    val repository by lazy { DiaryRepository(this) }
    /** The process scope: work here outlives any screen, such as a disconnect deleting the session. */
    val scope = CoroutineScope(SupervisorJob())
    /** A shortcut, tile or widget request the shell has not opened yet; it sets this back to null once it navigates. */
    val quickRequest = MutableStateFlow<QuickAction?>(null)
    val analysisWorker by lazy { MealAnalysisWorker(repository, SampleAnalyzer::analyze) }

    /** Finishes captured meals once the diary is ready; live analysis (milestone 5) replaces this. A failure stays needsRetry. */
    fun drainSampleAnalysis() {
        if (!SampleMode.enabled) return
        scope.launch {
            val ready = repository.bootstrapState.filterIsInstance<Bootstrap.Ready>().first()
            runCatching { analysisWorker.drain(ready.profileID) }
        }
    }

    /** iOS Today's rollover on launch and on return: starts the new waking day once the cutoff has passed. */
    fun rollOverDay(): Job = scope.launch(Dispatchers.IO) {
        val ready = repository.bootstrapState.filterIsInstance<Bootstrap.Ready>().first()
        runCatching { repository.database(ready.profileID).rollOverDay(Instant.now()) } // the next activity starts the day instead
    }

    private val widgetRefresh = MutableSharedFlow<Unit>(extraBufferCapacity = 1, onBufferOverflow = BufferOverflow.DROP_OLDEST)

    /** Republishes the Calories widget without a diary write, such as after the day cutoff changes. */
    fun refreshWidget() { widgetRefresh.tryEmit(Unit) }

    /** iOS `publishWidgetSnapshot` on every read-model change: after each write (a rollover is one) and diary switch. */
    private fun publishWidget() = scope.launch(Dispatchers.IO) {
        combine(repository.bootstrapState, merge(repository.changes, widgetRefresh).onStart { emit(Unit) }) { state, _ -> state }
            .conflate()
            .collect { state ->
                val snapshot = when (state) {
                    is Bootstrap.Ready -> runCatching { repository.database(state.profileID).widgetSnapshot(Instant.now()) }
                        .getOrNull() ?: return@collect // a failed read keeps the last snapshot
                    is Bootstrap.Choose -> Instant.now().let { now ->
                        WidgetSnapshot("", 0.0, null, false, WidgetSnapshot.nextRollover(now.toEpochMilli(),
                            ZoneId.systemDefault().id, DayCutoff.hour), now.toEpochMilli())
                    }
                    else -> return@collect // still opening, or failed: keep the last snapshot
                }
                CaloriesWidget.publish(this@MivuApplication, snapshot)
            }
    }

    // The one ChatGPT connection for the process; the debug proof screen shares it so refresh rotation has one owner.
    val chatGPT by lazy {
        val store = CredentialStore(this)
        ChatGPTConnection(store, AuthSession(store), ResponsesClient(), getSharedPreferences("chatgpt", MODE_PRIVATE), scope,
            GeminiNano(), lazy { NutritionTable.bundled(this) })
    }

    /** The launch restore of the chosen ChatGPT account; Coach work waits for it, as iOS `start` runs restore before `resume`. */
    @VisibleForTesting internal lateinit var restored: Job

    override fun onCreate() {
        super.onCreate()
        DayCutoff.load(DiaryRepository.preferences(this))
        // A force-stop clears alarms with no broadcast: every launch rebooks the reminder (or cancels it when off).
        MorningReminder.schedule(this)
        restored = scope.launch(Dispatchers.IO) { chatGPT.restore() }
        chatGPT.refreshNano()
        publishWidget()
        // Restore spools (`cacheDir/archive-*`) left by a process that died mid-restore; none can be in use this early.
        scope.launch(Dispatchers.IO) { cacheDir.listFiles().orEmpty().filter { it.name.startsWith("archive-") }.forEach { it.deleteRecursively() } }
        // As iOS, turns waiting for a connection run once the connection can infer.
        scope.launch { chatGPT.state.map { it.canInfer }.distinctUntilChanged().collect { if (it) drainCoach(retryWaiting = true) } }
    }

    /** Replaces the ChatGPT binding in instrumented tests, so they run scripted inference only. */
    @VisibleForTesting internal var coachInferenceForTest: (() -> suspend (List<CoachInferenceInput>, JsonObject) -> CoachInferenceResult)? = null
    val coachWorker by lazy { CoachWorker(repository, { coachInferenceForTest?.invoke() ?: chatGPT.inference() }, scope = scope) }
    private val watchingNetwork = AtomicBoolean(false)

    /** Runs saved Coach turns once the diary is ready; the returned job finishes when the worker is idle, whoever started it. */
    fun drainCoach(retryWaiting: Boolean = false): Job = scope.launch {
        val ready = repository.bootstrapState.filterIsInstance<Bootstrap.Ready>().first()
        restored.join() // a cold start must not save a healthy turn as waiting for a connection
        coachWorker.drain(ready.profileID, includeWaitingForConnection = chatGPT.state.value.canInfer, retryWaiting = retryWaiting)
        coachWorker.awaitIdle()
    }

    /**
     * The open diary, bootstrapping it when nothing has yet (a job can start the process without a screen); null when the
     * person must choose a diary or it failed to open.
     */
    suspend fun readyProfile(): UUID? = ((repository.bootstrapState.value ?: repository.bootstrap()) as? Bootstrap.Ready)?.profileID

    /** [readyProfile] that never creates the first diary (iOS `loadDiary(createDefaultProfile: false)`): setup belongs to the app. */
    suspend fun existingProfile(): UUID? = if (withContext(Dispatchers.IO) { repository.hasDiary() }) readyProfile() else null

    /** iOS `hasPendingWork`: a turn the worker would run now. Waiting for a connection counts only when ChatGPT can infer. */
    suspend fun hasPendingWork(): Boolean {
        val profileID = readyProfile() ?: return false
        return withContext(Dispatchers.IO) {
            runCatching { repository.database(profileID).nextPendingCoachTurn(chatGPT.state.value.canInfer) != null }.getOrDefault(false)
        }
    }

    /** Finishes saved Coach turns in [CoachJobService] after the app leaves the screen. Replaces a pending job with the same ID. */
    fun scheduleBackgroundDrain() {
        val jobs = getSystemService(JobScheduler::class.java)
        val job = JobInfo.Builder(COACH_JOB, ComponentName(this, CoachJobService::class.java))
            .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
        // iOS continueInBackground; a stopped job posts the saved note for shared turns (expireFollowed).
        if (jobs.schedule(job.setExpedited(true).build()) == JobScheduler.RESULT_FAILURE) jobs.schedule(job.setExpedited(false).build())
    }

    /** Set by [MainActivity] while it is started: replies to shared messages are not posted while Mivu is on screen. */
    @Volatile var screenVisible = false
    /** Shared turns whose reply is not posted yet; [expireFollowed] posts the saved note for them if the job is stopped. */
    @VisibleForTesting internal val followed: MutableSet<UUID> = ConcurrentHashMap.newKeySet()

    /** iOS `CoachReplyNotification.follow` for a turn saved from outside the app: finishes it in [CoachJobService], then posts. */
    fun followReply(turnID: UUID) {
        followed += turnID
        scheduleBackgroundDrain()
        scope.launch {
            drainCoach().join()
            val turn = existingProfile()?.let { id -> withContext(Dispatchers.IO) { runCatching { repository.database(id).coachTurn(turnID) }.getOrNull() } }
            if (turn != null && !screenVisible) CoachReplyNotification.post(this@MivuApplication, turn)
            followed -= turnID
        }
    }

    /** iOS `onExpire`: the job was stopped, so each followed turn still running gets the saved note; its reply replaces it. */
    fun expireFollowed() {
        val turns = followed.toList()
        followed.clear()
        if (turns.isEmpty()) return
        scope.launch(Dispatchers.IO) {
            val db = existingProfile()?.let { repository.database(it) } ?: return@launch
            fun running(id: UUID) = runCatching { db.coachTurn(id) }.getOrNull()
                ?.takeIf { it.state == CoachTurnState.captured || it.state == CoachTurnState.analyzing }
            for (id in turns) {
                if (screenVisible || running(id) == null) continue
                CoachReplyNotification.postSaved(this@MivuApplication, id)
                // A reply that landed meanwhile may have been posted just before the note: put it back on top.
                if (running(id) == null && !screenVisible) runCatching { db.coachTurn(id) }.getOrNull()?.let { CoachReplyNotification.post(this@MivuApplication, it) }
            }
        }
    }

    /** Resumes Coach turns now and whenever a network becomes available (the callback also fires for the current one). */
    fun watchNetworkForCoach() {
        if (!watchingNetwork.compareAndSet(false, true)) return
        getSystemService(ConnectivityManager::class.java).registerDefaultNetworkCallback(object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) { drainCoach(retryWaiting = true) }
        })
    }

    companion object {
        const val COACH_JOB = 1
    }
}
