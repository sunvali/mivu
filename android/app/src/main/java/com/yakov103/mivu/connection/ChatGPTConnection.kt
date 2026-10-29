package com.yakov103.mivu.connection

import android.content.SharedPreferences
import androidx.annotation.VisibleForTesting
import com.yakov103.mivu.analysis.AvailableModel
import com.yakov103.mivu.analysis.FoodTable
import com.yakov103.mivu.analysis.GeminiNano
import com.yakov103.mivu.analysis.OnDeviceInference
import com.yakov103.mivu.analysis.OnDeviceModel
import com.yakov103.mivu.analysis.ResponsesClient
import com.yakov103.mivu.coach.CoachInferenceInput
import com.yakov103.mivu.coach.CoachInferenceResult
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.json.JsonObject

@Suppress("EnumEntryName") // iOS case names
enum class AccountState { disconnected, connected, planPermissionMissing }

@Suppress("EnumEntryName")
enum class ConnectionNotice(val text: String) {
    cancelled("Connection cancelled"),
    denied("Connection permission declined"),
    unavailable("Connection unavailable. Try again."),
    offline("Can't reach ChatGPT. Check your internet connection, then try again."),
    quota("ChatGPT usage limit reached. Open Manage usage in Settings, then retry when usage is available."),
    permission("Enable ChatGPT plan usage before sending a request."),
    revoked("Reconnect to authorize plan usage."),
    disconnected("Local credentials removed"),
    unconfirmed("Local credentials removed. Remote revocation unconfirmed."),
    storageFailed("Local credentials could not be updated. Try again."),
}

@Suppress("EnumEntryName") // ML Kit `FeatureStatus`, plus AICore still fetching its configuration
enum class NanoStatus { unavailable, downloadable, downloading, preparing, available }

/** iOS `Provider`: `onDevice` is Gemini Nano, a no-account fallback for logging; ChatGPT is the main Coach. */
@Suppress("EnumEntryName")
enum class CoachProvider { chatGPT, onDevice }

data class ConnectionState(
    val account: AccountState = AccountState.disconnected,
    val registrationID: String? = null,
    val models: List<AvailableModel> = emptyList(),
    val selectedModel: String = "",
    val isConnecting: Boolean = false,
    val isDisconnecting: Boolean = false,
    val notice: ConnectionNotice? = null,
    val consented: Boolean = false,
    val planWelcomeSeen: Boolean = false,
    val storedProvider: CoachProvider? = null,
    /** A chosen ChatGPT account is saved, whether or not it restored (iOS reads `selectedRegistrationID`). */
    val savedRegistration: Boolean = false,
    val nano: NanoStatus = NanoStatus.unavailable,
    /** Gemini Nano download progress 0..1 while one runs; it keeps running when the person leaves the screen. */
    val nanoProgress: Float? = null,
    val nanoFailed: Boolean = false,
) {
    val planAuthorized get() = account == AccountState.connected && !isConnecting && !isDisconnecting && models.any { it.slug == selectedModel }

    /** The person's choice while it can answer; otherwise on-device when this phone can run it, then ChatGPT. */
    val provider get() = when {
        storedProvider != null && (storedProvider == CoachProvider.chatGPT || nano == NanoStatus.available) -> storedProvider
        // Someone with a saved ChatGPT connection keeps it until they pick on-device, also while it restores at launch.
        storedProvider == null && (planAuthorized || registrationID != null || savedRegistration) -> CoachProvider.chatGPT
        nano == NanoStatus.available -> CoachProvider.onDevice
        else -> CoachProvider.chatGPT
    }
    /** Whether the current provider can answer a Coach turn now. */
    val canInfer get() = if (provider == CoachProvider.onDevice) nano == NanoStatus.available else planAuthorized
    /** Only ChatGPT tunes onboarding targets; the formula estimate beats the on-device model there. */
    val tunesTargets get() = provider == CoachProvider.chatGPT && planAuthorized
    val showsPlanWelcome get() = account == AccountState.connected && !planWelcomeSeen

    /** iOS `ChatGPTConnectButton.defaultTitle`. */
    val buttonTitle get() = when {
        account == AccountState.planPermissionMissing -> "Enable ChatGPT plan usage"
        registrationID == null -> "Continue with ChatGPT"
        else -> "Reauthorize ChatGPT"
    }
}

/**
 * Port of iOS `ChatGPTConnection` without the sample probe: the account, OpenAI sharing consent, the plan-permission
 * pause, models, the selected model and notices. It holds state only; tokens stay in [auth] and its store.
 */
class ChatGPTConnection(
    private val store: CredentialStoring,
    /** The process's one session; read directly only by the debug proof screen. */
    val auth: AuthSession,
    private val client: ResponsesClient,
    private val prefs: SharedPreferences,
    private val scope: CoroutineScope,
    private val nano: GeminiNano? = null,
    /** The process's one FNDDS table, opened on the first on-device turn. */
    private val table: Lazy<FoodTable>? = null,
) {
    private val _state = MutableStateFlow(ConnectionState(consented = prefs.getBoolean(CONSENT, false),
        planWelcomeSeen = prefs.getBoolean(WELCOME, false), savedRegistration = prefs.getString(SELECTED, null) != null,
        storedProvider = prefs.getString(PROVIDER, null)?.let { name -> CoachProvider.entries.firstOrNull { it.name == name } }))
    val state: StateFlow<ConnectionState> = _state.asStateFlow()

    /** Replaces Gemini Nano in instrumented tests and reports it available. */
    @VisibleForTesting internal var onDeviceForTest: OnDeviceModel? = null
        set(value) {
            field = value
            _state.update { it.copy(nano = if (value != null) NanoStatus.available else NanoStatus.unavailable) }
        }

    // Guards generation and every state change that depends on it; nothing suspends while it is held.
    private val lock = Any()
    private var generation = 0
    private var connecting: Job? = null
    // A sign-in waits for launch restoration so a late restore cannot replace the new session.
    private val restoring = Mutex()

    /** Launch restoration; a session saved before consent stays unused until the person agrees. */
    suspend fun restore() {
        val s = state.value
        if (s.isConnecting || s.isDisconnecting || !s.consented) return
        val revision = synchronized(lock) { generation }
        try {
            // Only the account the person chose; other saved credentials stay unused (iOS `selectedRegistrationID`).
            val selection = prefs.getString(SELECTED, null) ?: return
            restoring.withLock { auth.restore(selection) }
            if (!ifCurrent(revision) { apply(auth.snapshot()) }) return
            if (state.value.account == AccountState.connected) loadModels(revision)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            ifCurrent(revision) { _state.update { it.copy(notice = ConnectionNotice.unavailable) } }
        }
    }

    /** Only the person's "Agree and Continue" calls this. */
    fun recordConsent() {
        prefs.edit().putBoolean(CONSENT, true).apply()
        _state.update { it.copy(consented = true) }
    }

    fun acknowledgePlanWelcome() {
        prefs.edit().putBoolean(WELCOME, true).apply()
        _state.update { it.copy(planWelcomeSeen = true) }
    }

    fun choose(provider: CoachProvider) {
        prefs.edit().putString(PROVIDER, provider.name).apply()
        _state.update { it.copy(storedProvider = provider) }
    }

    @VisibleForTesting internal var statusForTest: (suspend () -> NanoStatus)? = null
    @VisibleForTesting internal var downloadForTest: (() -> Flow<Float>)? = null
    private var nanoDownload: Job? = null

    /** Re-reads whether Gemini Nano can run on this phone, off the caller's thread; launch and each return call it. */
    fun refreshNano(): Job? {
        val read = statusForTest ?: nano?.let { it::status } ?: return null
        return scope.launch {
            val status = read()
            if (onDeviceForTest == null) _state.update { it.copy(nano = status) }
        }
    }

    /** Downloads Gemini Nano in the app's scope, so leaving a screen does not stop it; one at a time, then re-reads its status. */
    fun startNanoDownload(): Job? = synchronized(lock) {
        nanoDownload?.takeIf { it.isActive }?.let { return it }
        val download = downloadForTest?.invoke() ?: nano?.download() ?: return null
        _state.update { it.copy(nanoProgress = 0f, nanoFailed = false) }
        scope.launch {
            try {
                download.collect { progress -> _state.update { it.copy(nanoProgress = progress) } }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _state.update { it.copy(nanoFailed = true) }
            } finally {
                _state.update { it.copy(nanoProgress = null) }
            }
            refreshNano()
        }.also { nanoDownload = it }
    }

    /** Starts a sign-in that [open]s the authorization URL in a browser; does nothing without consent or while busy. */
    fun connect(open: (String) -> Unit): Job = synchronized(lock) {
        val s = _state.value
        if (!s.consented || s.isConnecting || s.isDisconnecting) return Job().apply { complete() }
        val revision = ++generation
        _state.update { it.copy(isConnecting = true, notice = null) }
        scope.launch { authorize(revision, open) }.also { job ->
            connecting = job
            job.invokeOnCompletion {
                ifCurrent(revision) { connecting = null; _state.update { it.copy(isConnecting = false) } }
            }
        }
    }

    private suspend fun authorize(revision: Int, open: (String) -> Unit) {
        val loop = LoopbackCallback()
        try {
            restoring.withLock {}
            val current = state.value
            val selection = current.registrationID ?: prefs.getString(SELECTED, null)
            val returning = store.registrations().firstOrNull { it.id == selection }
            val attempt = OAuthAttempt.make(store.hostID(), returning?.issuedClientID, loop.start(),
                requestPlanConsent = returning != null && current.account == AccountState.planPermissionMissing)
            if (!ifCurrent(revision) {}) return
            open(attempt.authorizationUrl)
            val code = attempt.consumeCallback(withTimeout(5 * 60_000L) { loop.await() })
            val session = auth.establish(code, attempt.verifier, attempt.nonce, returning?.id)
            val applied = ifCurrent(revision) {
                prefs.edit().putString(SELECTED, session.registration.id).apply()
                _state.update { it.copy(savedRegistration = true) }
                if (prefs.getString(PAUSED, null) == session.registration.id) prefs.edit().remove(PAUSED).apply()
                _state.update { it.copy(models = emptyList(), selectedModel = "") }
                apply(auth.snapshot())
            }
            if (applied && state.value.account == AccountState.connected) loadModels(revision)
        } catch (e: Exception) {
            val notice = when (e) {
                is CancellationException -> ConnectionNotice.cancelled // includes the five-minute timeout
                OAuthError.Denied -> ConnectionNotice.denied
                SessionError.NetworkUnavailable -> ConnectionNotice.offline
                else -> ConnectionNotice.unavailable
            }
            ifCurrent(revision) { _state.update { it.copy(notice = notice) } }
        } finally {
            loop.close()
        }
    }

    fun cancelConnection(): Unit = synchronized(lock) {
        val wasConnecting = _state.value.isConnecting
        generation++
        connecting?.cancel()
        connecting = null
        _state.update { it.copy(isConnecting = false, notice = if (wasConnecting) ConnectionNotice.cancelled else it.notice) }
    }

    fun selectModel(slug: String) = _state.update { s -> if (s.models.any { it.slug == slug }) s.copy(selectedModel = slug) else s }

    /** iOS `disconnect`: state clears first, then the session is deleted and revoked. */
    suspend fun disconnect() {
        val (revision, previous) = synchronized(lock) {
            if (_state.value.isDisconnecting) return
            val previous = _state.value
            cancelConnection()
            _state.update {
                it.copy(isDisconnecting = true, account = AccountState.disconnected, registrationID = null,
                    models = emptyList(), selectedModel = "")
            }
            generation to previous
        }
        try {
            val outcome = try { auth.disconnect() } catch (e: CancellationException) { throw e } catch (e: Exception) { null }
            ifCurrent(revision) {
                if (outcome != null) {
                    if (prefs.getString(SELECTED, null) == previous.registrationID) prefs.edit().remove(SELECTED).apply()
                    _state.update { it.copy(savedRegistration = prefs.getString(SELECTED, null) != null) }
                    val notice = if (outcome == RevocationOutcome.Confirmed) ConnectionNotice.disconnected else ConnectionNotice.unconfirmed
                    _state.update { it.copy(notice = notice) }
                } else {
                    // The store refused the delete; the session is still active.
                    val retained = auth.snapshot()
                    apply(retained)
                    if (retained != null && retained.registrationID == previous.registrationID) {
                        prefs.edit().putString(SELECTED, retained.registrationID).apply()
                        _state.update { it.copy(savedRegistration = true) }
                        _state.update { it.copy(models = previous.models, selectedModel = previous.selectedModel) }
                    }
                    _state.update { it.copy(notice = ConnectionNotice.storageFailed) }
                }
            }
        } finally {
            _state.update { it.copy(isDisconnecting = false) }
        }
    }

    private data class Binding(val generation: Int, val owner: String?, val model: String)

    /**
     * iOS `inference()`: binds one Coach turn to the session, account and model current now. Every round and retry of
     * that turn goes through the returned function and ends with [SessionError.SessionChanged] once any of them changes.
     */
    fun inference(): suspend (List<CoachInferenceInput>, JsonObject?) -> CoachInferenceResult {
        val s = _state.value
        if (s.provider == CoachProvider.onDevice) {
            val model = onDeviceForTest ?: nano
            val table = table
            if (!s.canInfer || model == null || table == null) return { _, _ -> throw SessionError.NoActiveSession }
            return { input, tools -> OnDeviceInference.respond(input, tools, model, table.value) }
        }
        val binding = synchronized(lock) {
            val current = _state.value
            if (current.planAuthorized) Binding(generation, current.registrationID, current.selectedModel) else null
        } ?: return { _, _ -> throw SessionError.NoActiveSession }
        return { input, tools -> respond(binding, input, tools) }
    }

    /** iOS `respondForCoach`. */
    private suspend fun respond(binding: Binding, input: List<CoachInferenceInput>, tools: JsonObject?): CoachInferenceResult {
        val (revision, owner, model) = binding
        suspend fun validate() {
            currentCoroutineContext().ensureActive()
            synchronized(lock) {
                val s = _state.value
                if (generation != revision || s.registrationID != owner || s.selectedModel != model || !s.planAuthorized) {
                    throw SessionError.SessionChanged
                }
            }
        }
        validate()
        try {
            val token = auth.accessToken(expectedRegistrationID = owner)
            validate()
            val result = client.respond(model, input, tools, token)
            validate()
            return result
        } catch (e: Exception) {
            validate()
            if (e !is CancellationException) reflectFailure(e, revision)
            throw e
        }
    }

    private suspend fun loadModels(revision: Int) {
        val owner = state.value.registrationID ?: return
        try {
            val token = auth.accessToken(expectedRegistrationID = owner)
            if (!ifCurrent(revision) {}) return
            val catalog = client.models(token)
            ifCurrent(revision) {
                _state.update { s ->
                    s.copy(models = catalog, selectedModel = s.selectedModel.takeIf { m -> catalog.any { it.slug == m } }
                        ?: catalog.firstOrNull()?.slug.orEmpty())
                }
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            reflectFailure(e, revision)
        }
    }

    private fun reflectFailure(error: Exception, revision: Int) {
        ifCurrent(revision) {
            val snapshot = auth.snapshot()
            apply(snapshot)
            val notice = when {
                error == ResponsesClient.Failure.QuotaReached -> ConnectionNotice.quota
                error == ResponsesClient.Failure.Forbidden -> { pause(snapshot); ConnectionNotice.permission }
                error == ResponsesClient.Failure.Unauthorized -> { pause(snapshot); ConnectionNotice.revoked }
                error == SessionError.InvalidRefresh || snapshot == null -> {
                    _state.update { it.copy(account = AccountState.disconnected, models = emptyList(), selectedModel = "") }
                    ConnectionNotice.revoked
                }
                error == SessionError.PlanPermissionMissing -> {
                    _state.update { it.copy(account = AccountState.planPermissionMissing) }
                    ConnectionNotice.permission
                }
                error == SessionError.NetworkUnavailable -> ConnectionNotice.offline
                else -> ConnectionNotice.unavailable
            }
            _state.update { it.copy(notice = notice) }
        }
    }

    private fun pause(snapshot: SessionSnapshot?) {
        if (snapshot != null) prefs.edit().putString(PAUSED, snapshot.registrationID).apply()
        _state.update {
            it.copy(account = if (snapshot == null) AccountState.disconnected else AccountState.planPermissionMissing,
                models = emptyList(), selectedModel = "")
        }
    }

    private fun apply(snapshot: SessionSnapshot?) = _state.update { s ->
        val account = when {
            snapshot == null -> AccountState.disconnected
            snapshot.planPermissionGranted && prefs.getString(PAUSED, null) != snapshot.registrationID -> AccountState.connected
            else -> AccountState.planPermissionMissing
        }
        val cleared = if (account == AccountState.connected) s else s.copy(models = emptyList(), selectedModel = "")
        cleared.copy(account = account, registrationID = snapshot?.registrationID)
    }

    /** Runs [block] under the lock only while [revision] is current; returns whether it ran. */
    private inline fun ifCurrent(revision: Int, block: () -> Unit): Boolean = synchronized(lock) {
        if (generation != revision) return false
        block()
        true
    }

    private companion object {
        const val CONSENT = "openAISharingConsent"
        const val WELCOME = "chatGPTPlanWelcomeSeen"
        const val PAUSED = "pausedRegistrationID"
        const val SELECTED = "selectedRegistrationID"
        const val PROVIDER = "aiProvider"
    }
}
