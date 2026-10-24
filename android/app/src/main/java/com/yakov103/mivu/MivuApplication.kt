package com.yakov103.mivu

import android.app.Application
import android.app.job.JobInfo
import android.app.job.JobScheduler
import android.content.ComponentName
import android.net.ConnectivityManager
import android.net.Network
import androidx.annotation.VisibleForTesting
import com.yakov103.mivu.analysis.MealAnalysisWorker
import com.yakov103.mivu.analysis.ResponsesClient
import com.yakov103.mivu.analysis.SampleAnalyzer
import com.yakov103.mivu.coach.CoachInferenceInput
import com.yakov103.mivu.coach.CoachInferenceResult
import com.yakov103.mivu.coach.CoachJobService
import com.yakov103.mivu.coach.CoachWorker
import com.yakov103.mivu.connection.AuthSession
import com.yakov103.mivu.connection.ChatGPTConnection
import com.yakov103.mivu.connection.CredentialStore
import com.yakov103.mivu.diary.Bootstrap
import com.yakov103.mivu.diary.DiaryRepository
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.filterIsInstance
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonObject

class MivuApplication : Application() {
    val repository by lazy { DiaryRepository(this) }
    /** The process scope: work here outlives any screen, such as a disconnect deleting the session. */
    val scope = CoroutineScope(SupervisorJob())
    val analysisWorker by lazy { MealAnalysisWorker(repository, SampleAnalyzer::analyze) }

    /** Finishes captured meals once the diary is ready; live analysis (milestone 5) replaces this. A failure stays needsRetry. */
    fun drainSampleAnalysis() {
        if (!SampleMode.enabled) return
        scope.launch {
            val ready = repository.bootstrapState.filterIsInstance<Bootstrap.Ready>().first()
            runCatching { analysisWorker.drain(ready.profileID) }
        }
    }

    // The one ChatGPT connection for the process; the debug proof screen shares it so refresh rotation has one owner.
    val chatGPT by lazy {
        val store = CredentialStore(this)
        ChatGPTConnection(store, AuthSession(store), ResponsesClient(), getSharedPreferences("chatgpt", MODE_PRIVATE), scope)
    }

    override fun onCreate() {
        super.onCreate()
        scope.launch(Dispatchers.IO) { chatGPT.restore() }
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
        coachWorker.drain(ready.profileID, includeWaitingForConnection = chatGPT.state.value.canInfer, retryWaiting = retryWaiting)
        coachWorker.awaitIdle()
    }

    /**
     * The open diary, bootstrapping it when nothing has yet (a job can start the process without a screen); null when the
     * person must choose a diary or it failed to open.
     */
    suspend fun readyProfile(): UUID? = ((repository.bootstrapState.value ?: repository.bootstrap()) as? Bootstrap.Ready)?.profileID

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
        // iOS continueInBackground; the saved-message notification is milestone 8.
        if (jobs.schedule(job.setExpedited(true).build()) == JobScheduler.RESULT_FAILURE) jobs.schedule(job.setExpedited(false).build())
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
