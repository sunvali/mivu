package com.yakov103.mivu

import android.content.Context
import android.net.Uri
import androidx.compose.runtime.mutableStateMapOf
import com.yakov103.mivu.analysis.ResponsesClient
import com.yakov103.mivu.connection.AuthSession
import com.yakov103.mivu.connection.CredentialStore
import com.yakov103.mivu.connection.LoopbackCallback
import com.yakov103.mivu.connection.OAuthAttempt
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlin.coroutines.coroutineContext
import kotlinx.coroutines.withTimeout

/** One outcome line per button. Text is fixed wording or an error class name, never a token, code or callback URL. */
data class ProofResult(val ok: Boolean?, val text: String)

/** Process-wide owner of the one AuthSession (its refresh scope is session-owned) and of every proof action. */
object ProofSession {
    val results = mutableStateMapOf<String, ProofResult>()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val client = ResponsesClient()
    private var store: CredentialStore? = null
    private var auth: AuthSession? = null
    private var restored = false
    private var signInJob: Job? = null
    @Volatile private var live = false

    private fun init(context: Context): Pair<CredentialStore, AuthSession> = synchronized(this) {
        val s = store ?: CredentialStore(context.applicationContext).also { store = it }
        s to (auth ?: AuthSession(s).also { auth = it })
    }

    private fun prefs(context: Context) = context.applicationContext.getSharedPreferences("proof", Context.MODE_PRIVATE)

    /** An attempt flagged in flight with no live listener means the process died during sign-in. */
    fun reportInterrupted(context: Context) {
        val p = prefs(context)
        if (p.getBoolean(IN_FLIGHT, false) && !live) {
            p.edit().putBoolean(IN_FLIGHT, false).apply()
            results[SIGN_IN] = ProofResult(false, "Sign-in was interrupted, try again")
        }
    }

    fun cancelSignIn() { signInJob?.cancel() }

    fun signIn(context: Context, open: (Uri) -> Unit) = run(SIGN_IN) {
        val (store, auth) = init(context)
        val loop = LoopbackCallback()
        signInJob = coroutineContext[Job]
        live = true
        try {
            val callback = loop.start()
            val returning = store.registrations().firstOrNull()
            val attempt = OAuthAttempt.make(store.hostID(), returning?.issuedClientID, callback)
            prefs(context).edit().putBoolean(IN_FLIGHT, true).commit()
            open(Uri.parse(attempt.authorizationUrl))
            val received = withTimeout(5 * 60_000L) { loop.await() }
            val code = attempt.consumeCallback(received)
            auth.establish(code, attempt.verifier, attempt.nonce, returning?.id)
            restored = true
            "Signed in"
        } finally {
            loop.close()
            live = false
            prefs(context).edit().putBoolean(IN_FLIGHT, false).apply()
        }
    }

    fun listModels(context: Context) = run(LIST_MODELS) {
        val models = client.models(token(context))
        "${models.size} models; first: ${models.first().slug}"
    }

    fun analyzeText(context: Context) = run(ANALYZE_TEXT) {
        analyze(context, null)
    }

    fun analyzePhoto(context: Context, jpeg: ByteArray) = run(ANALYZE_PHOTO) {
        analyze(context, jpeg)
    }

    fun forceRefresh(context: Context) = run(FORCE_REFRESH) {
        val auth = restored(context)
        val before = auth.accessToken()
        val after = auth.accessToken(forceRefresh = true)
        check(before != after) { "token unchanged" }
        "Refreshed; the new token replaced the old one"
    }

    fun disconnect(context: Context) = run(DISCONNECT) {
        val outcome = restored(context).disconnect()
        "Disconnected; revocation $outcome"
    }

    private suspend fun analyze(context: Context, jpeg: ByteArray?): String {
        val token = token(context)
        val model = client.models(token).first().slug
        val prompt = if (jpeg == null) "Estimate calories for: two boiled eggs and a slice of toast."
        else "Estimate calories for the meal in this photo."
        val text = client.run(model, prompt, jpeg, jpeg?.let { "image/jpeg" }, token).text
        return "Model $model: ${text.take(200)}"
    }

    private suspend fun restored(context: Context): AuthSession {
        val (store, auth) = init(context)
        if (!restored) {
            store.registrations().firstOrNull()?.let { auth.restore(it.id) }
            restored = true
        }
        return auth
    }

    private suspend fun token(context: Context) = restored(context).accessToken()

    private fun run(label: String, block: suspend () -> String) {
        results[label] = ProofResult(null, "Running")
        scope.launch {
            results[label] = try {
                ProofResult(true, block())
            } catch (e: kotlinx.coroutines.CancellationException) {
                ProofResult(false, "Cancelled")
            } catch (e: Exception) {
                ProofResult(false, describe(e))
            }
        }
    }

    // Failure messages are fixed strings ("http 401"); everything else is reduced to its class name.
    private fun describe(e: Exception) = if (e is ResponsesClient.Failure) e.message.orEmpty() else e::class.simpleName.orEmpty()

    const val SIGN_IN = "Sign in"
    const val LIST_MODELS = "List models"
    const val ANALYZE_TEXT = "Analyze text"
    const val ANALYZE_PHOTO = "Analyze photo"
    const val FORCE_REFRESH = "Force refresh"
    const val DISCONNECT = "Disconnect"
    private const val IN_FLIGHT = "signInInFlight"
}
