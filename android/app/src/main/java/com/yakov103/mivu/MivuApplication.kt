package com.yakov103.mivu

import android.app.Application
import android.net.ConnectivityManager
import android.net.Network
import com.yakov103.mivu.analysis.MealAnalysisWorker
import com.yakov103.mivu.analysis.ResponsesClient
import com.yakov103.mivu.analysis.SampleAnalyzer
import com.yakov103.mivu.coach.CoachInferenceInput
import com.yakov103.mivu.coach.CoachInferenceResult
import com.yakov103.mivu.coach.CoachWorker
import com.yakov103.mivu.connection.AuthSession
import com.yakov103.mivu.connection.CredentialStore
import com.yakov103.mivu.connection.SessionError
import com.yakov103.mivu.diary.Bootstrap
import com.yakov103.mivu.diary.DiaryRepository
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.filterIsInstance
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.JsonObject

class MivuApplication : Application() {
    val repository by lazy { DiaryRepository(this) }
    private val scope = CoroutineScope(SupervisorJob())
    val analysisWorker by lazy { MealAnalysisWorker(repository, SampleAnalyzer::analyze) }

    /** Finishes captured meals once the diary is ready; live analysis (milestone 5) replaces this. A failure stays needsRetry. */
    fun drainSampleAnalysis() {
        if (!SampleMode.enabled) return
        scope.launch {
            val ready = repository.bootstrapState.filterIsInstance<Bootstrap.Ready>().first()
            runCatching { analysisWorker.drain(ready.profileID) }
        }
    }

    // The one ChatGPT session for the process; the debug proof screen shares it so refresh rotation has one owner.
    val credentials by lazy { CredentialStore(this) }
    private val auth by lazy { AuthSession(credentials) }
    private val client = ResponsesClient()
    private val restoreLock = Mutex()
    private var restored = false
    @Volatile private var model: String? = null

    /** The session with the saved registration restored once, before any sign-in or request uses it. */
    suspend fun connection(): AuthSession = restoreLock.withLock {
        if (!restored) {
            credentials.registrations().firstOrNull()?.let { auth.restore(it.id) }
            restored = true
        }
        auth
    }

    private suspend fun coachInference(input: List<CoachInferenceInput>, tools: JsonObject): CoachInferenceResult {
        val token = connection().accessToken()
        // shortcut: the plan's first catalog model, kept for the process; upgrade when Android gets a model picker.
        val slug = model ?: (client.models(token).firstOrNull()?.slug ?: throw SessionError.NoActiveSession).also { model = it }
        return client.respond(slug, input, tools, token)
    }

    val coachWorker by lazy { CoachWorker(repository, ::coachInference, scope = scope) }
    private val watchingNetwork = AtomicBoolean(false)

    /** Runs saved Coach turns once the diary is ready; the returned job finishes when that pass does. */
    fun drainCoach(): Job = scope.launch {
        val ready = repository.bootstrapState.filterIsInstance<Bootstrap.Ready>().first()
        // iOS `connection.canInfer`: turns waiting for a connection retry only once an account is registered.
        val connected = runCatching { credentials.registrations().isNotEmpty() }.getOrDefault(false)
        coachWorker.drain(ready.profileID, includeWaitingForConnection = connected)?.join()
    }

    /** Resumes Coach turns now and whenever a network becomes available (the callback also fires for the current one). */
    fun watchNetworkForCoach() {
        if (!watchingNetwork.compareAndSet(false, true)) return
        getSystemService(ConnectivityManager::class.java).registerDefaultNetworkCallback(object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) { drainCoach() }
        })
    }
}
