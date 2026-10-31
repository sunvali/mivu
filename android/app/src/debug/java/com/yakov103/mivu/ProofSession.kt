package com.yakov103.mivu

import android.content.Context
import android.net.Uri
import androidx.compose.runtime.mutableStateMapOf
import com.yakov103.mivu.analysis.ResponsesClient
import com.yakov103.mivu.connection.AccountState
import com.yakov103.mivu.coach.CoachEngine
import com.yakov103.mivu.diary.CoachCaptureContext
import com.yakov103.mivu.diary.CoachSubmissionPayload
import com.yakov103.mivu.diary.CoachTurnState
import com.yakov103.mivu.diary.DiaryDatabase
import com.yakov103.mivu.diary.DiaryProfile
import com.yakov103.mivu.diary.captureCoachSubmission
import com.yakov103.mivu.diary.startDay
import java.io.File
import java.time.Instant
import java.time.ZoneId
import java.util.UUID
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.launch

/** One outcome line per button. Text is fixed wording or an error class name, never a token, code or callback URL. */
data class ProofResult(val ok: Boolean?, val text: String)

/** Process-wide owner of every proof action; the AuthSession is the app's own, so refresh rotation has one owner. */
object ProofSession {
    val results = mutableStateMapOf<String, ProofResult>()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val client = ResponsesClient()
    private var signInJob: Job? = null
    @Volatile private var live = false

    private fun app(context: Context) = context.applicationContext as MivuApplication

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

    @Synchronized
    fun signIn(context: Context, open: (Uri) -> Unit) {
        signInJob = run(SIGN_IN, signInJob) { signInAttempt(context, open) }
    }

    // Goes through the app's connection, so it needs the person's OpenAI sharing consent like any other sign-in.
    private suspend fun signInAttempt(context: Context, open: (Uri) -> Unit): String {
        val chatGPT = app(context).chatGPT
        check(chatGPT.state.value.consented) { "OpenAI sharing consent needed" }
        live = true
        try {
            prefs(context).edit().putBoolean(IN_FLIGHT, true).commit()
            try {
                chatGPT.connect { open(Uri.parse(it)) }.join()
            } catch (e: kotlinx.coroutines.CancellationException) {
                chatGPT.cancelConnection()
                throw e
            }
            val state = chatGPT.state.value
            check(state.notice == null && state.account != AccountState.disconnected) { state.notice?.text ?: "Not signed in" }
            return "Signed in"
        } finally {
            live = false
            prefs(context).edit().putBoolean(IN_FLIGHT, false).apply()
        }
    }

    fun listModels(context: Context) = run(LIST_MODELS) {
        val models = app(context).chatGPT.state.value.models
        check(models.isNotEmpty()) { "No models loaded" }
        "${models.size} models; selected: ${app(context).chatGPT.state.value.selectedModel}"
    }

    fun analyzeText(context: Context) = run(ANALYZE_TEXT) {
        analyze(context, null)
    }

    fun analyzePhoto(context: Context, jpeg: () -> ByteArray) = run(ANALYZE_PHOTO) {
        analyze(context, jpeg())
    }

    fun forceRefresh(context: Context) = run(FORCE_REFRESH) {
        val auth = app(context).chatGPT.auth
        val before = auth.accessToken()
        val after = auth.accessToken(forceRefresh = true)
        check(before != after) { "token unchanged" }
        "Refreshed; the new token replaced the old one"
    }

    fun disconnect(context: Context) = run(DISCONNECT) {
        val chatGPT = app(context).chatGPT
        chatGPT.disconnect()
        chatGPT.state.value.notice?.text ?: "Disconnected"
    }

    private suspend fun analyze(context: Context, jpeg: ByteArray?): String {
        val token = token(context)
        val model = app(context).chatGPT.state.value.selectedModel
        val prompt = if (jpeg == null) "Estimate calories for: two boiled eggs and a slice of toast."
        else "Estimate calories for the meal in this photo."
        val text = client.run(model, prompt, jpeg, jpeg?.let { "image/jpeg" }, token).text
        return "Model $model: ${text.take(200)}"
    }

    /**
     * Captures one synthetic Coach turn in a fresh scratch diary (opened as CaptureProbeActivity opens its profile) and runs
     * it through CoachEngine with live inference. The app's worker and the selected diary are never touched.
     */
    fun runCoachTurn(context: Context) = run(RUN_COACH) {
        File(context.filesDir, "profiles/${SCRATCH_PROFILE.toString().uppercase()}").deleteRecursively()
        val zone = ZoneId.systemDefault().id
        DiaryDatabase.create(context, DiaryProfile(SCRATCH_PROFILE, "Proof", "en", zone, "")).use { db ->
            val now = Instant.now()
            db.startDay(now, db.head().revision)
            val h = db.head()
            val turn = db.captureCoachSubmission(CoachSubmissionPayload(UUID.randomUUID(), COACH_TEXT, emptyList(),
                CoachCaptureContext(now, zone, h.activeDayID, h.previousDayConfirmedAt, h.activeConversationSegmentID)), h.revision)
            val done = CoachEngine(db, app(context).chatGPT.inference()).run(turn.id)
            // State and receipt count only; the reply text stays in the scratch diary.
            check(done.state == CoachTurnState.completed) { "turn ${done.state.name}" }
            "Turn completed; ${done.receipts.size} saved records"
        }
    }

    private suspend fun token(context: Context) = app(context).chatGPT.auth.accessToken()

    // A previous job is cancelled and joined first, so its finally cannot clear the new attempt's state.
    private fun run(label: String, previous: Job? = null, block: suspend () -> String): Job {
        results[label] = ProofResult(null, "Running")
        return scope.launch {
            previous?.cancelAndJoin()
            results[label] = ProofResult(null, "Running")
            results[label] = try {
                ProofResult(true, block())
            } catch (e: kotlinx.coroutines.CancellationException) {
                ProofResult(false, "Cancelled")
            } catch (e: Exception) {
                ProofResult(false, describe(e))
            }
        }
    }

    // Failure and check() messages are fixed strings ("http 401"); everything else is reduced to its class name.
    private fun describe(e: Exception) =
        if (e is ResponsesClient.Failure || e is IllegalStateException) e.message.orEmpty() else e::class.simpleName.orEmpty()

    const val SIGN_IN = "Sign in"
    const val LIST_MODELS = "List models"
    const val ANALYZE_TEXT = "Analyze text"
    const val ANALYZE_PHOTO = "Analyze photo"
    const val FORCE_REFRESH = "Force refresh"
    const val DISCONNECT = "Disconnect"
    const val RUN_COACH = "Run Coach turn"
    private const val COACH_TEXT = "Synthetic proof: I had two boiled eggs and a slice of toast for breakfast."
    private const val IN_FLIGHT = "signInInFlight"
    private val SCRATCH_PROFILE: UUID = UUID.fromString("00000000-0000-4000-8000-00000000c0ac")
}
