package com.yakov103.mivu.coach

import android.graphics.Bitmap
import android.graphics.ImageDecoder
import com.yakov103.mivu.analysis.ResponsesClient
import com.yakov103.mivu.diary.DiaryRepository
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.coroutines.cancellation.CancellationException
import kotlin.math.roundToInt
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonObject

// Port of the iOS Coach worker loop, CoachViewModel.resume (ios/Mivu/Coach/CoachViewModel.swift:408-516), and
// PhotoImport.visionCopies (ios/Mivu/Diary/PhotoCapture.swift:62).

/**
 * Runs saved Coach turns oldest first, one worker at a time. No lock is held while a turn runs: a request during a
 * pass only sets a flag, and the running worker makes one more pass for it. A failed turn ends the pass with its
 * state saved by the engine; the next request (a capture, the app starting or the network returning) resumes it.
 */
class CoachWorker(
    private val repository: DiaryRepository,
    private val infer: suspend (List<CoachInferenceInput>, JsonObject) -> CoachInferenceResult,
    private val prepareImages: suspend (List<ByteArray>) -> List<ByteArray> = ::visionCopies,
    private val sleep: suspend (Long) -> Unit = { delay(it) },
    private val scope: CoroutineScope,
) {
    private val running = AtomicBoolean(false)
    private val requested = AtomicBoolean(false)
    @Volatile private var profileID: UUID? = null
    @Volatile private var includeWaitingForConnection = false
    /**
     * iOS `capturedOnly`, kept across workers: once a pass ends on a turn the engine left pending, later passes run only new
     * captures, so a turn stuck on the network cannot hold back newer messages. A network or connection change, or a pass
     * that finds nothing pending at all, clears it.
     */
    @Volatile private var capturedOnly = false
    private val _activity = MutableStateFlow<Pair<UUID, CoachActivity>?>(null)

    /** The running turn and its phase, or null between turns. */
    val activity: StateFlow<Pair<UUID, CoachActivity>?> = _activity.asStateFlow()

    /**
     * Starts a worker, or returns null when one is running; that worker then makes one more pass. Turns waiting for a
     * connection run only when [includeWaitingForConnection] (the app can infer). [retryWaiting] marks a network or
     * connection change, which lets stuck turns run first again.
     */
    fun drain(profileID: UUID, includeWaitingForConnection: Boolean, retryWaiting: Boolean = false): Job? {
        this.profileID = profileID
        this.includeWaitingForConnection = includeWaitingForConnection
        if (retryWaiting) capturedOnly = false
        requested.set(true)
        if (!running.compareAndSet(false, true)) return null
        return scope.launch(Dispatchers.IO) {
            while (true) {
                try {
                    while (requested.getAndSet(false)) pass(this@CoachWorker.profileID ?: break)
                } catch (e: Throwable) {
                    running.set(false); throw e
                }
                running.set(false)
                // A request that arrived after the last pass found nothing is served here, unless another worker took it.
                if (!requested.get() || !running.compareAndSet(false, true)) return@launch
            }
        }
    }

    /**
     * Runs pending turns oldest first and updates [capturedOnly]. Any failure ends the pass: a turn's state is saved by the
     * engine, and a diary error waits for the next request. Nothing is logged, so no prompt, context or reply leaves the
     * diary; an escaped error would end the process.
     */
    private suspend fun pass(profileID: UUID) {
        try {
            val db = repository.database(profileID)
            var previous: UUID? = null
            while (true) {
                val turnID = db.nextPendingCoachTurn(includeWaitingForConnection, capturedOnly)
                if (turnID == null) {
                    if (db.nextPendingCoachTurn(includeWaitingForConnection) == null) capturedOnly = false
                    return
                }
                if (turnID == previous) { capturedOnly = true; return } // the engine left it pending; wait for the next request
                previous = turnID
                try {
                    CoachEngine(db, ::resilient, prepareImages) { _activity.value = turnID to it }.run(turnID)
                } catch (e: CancellationException) {
                    throw e
                } catch (_: Exception) {
                    capturedOnly = true // the engine saved its failed state; newer captures go first until the network changes
                    return
                } finally {
                    _activity.value = null
                }
            }
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
        }
    }

    /** iOS `resilient`: retries a transient inference failure after 1, 2 and 4 seconds. */
    private suspend fun resilient(input: List<CoachInferenceInput>, tools: JsonObject): CoachInferenceResult {
        for (delayMs in DELAYS) {
            try {
                return infer(input, tools)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                if (!CoachEngine.isTransient(e)) throw e
            }
            sleep(delayMs)
        }
        return infer(input, tools)
    }

    private companion object {
        val DELAYS = listOf(1_000L, 2_000L, 4_000L)
    }
}

/** iOS `PhotoImport.visionCopies`: upright JPEG copies sized so the turn's photos fit the 4 MiB request budget. */
suspend fun visionCopies(originals: List<ByteArray>): List<ByteArray> = withContext(Dispatchers.Default) {
    if (originals.size > 30) throw ResponsesClient.Failure.InvalidInput
    if (originals.isEmpty()) return@withContext emptyList()
    val budget = minOf(524_288, 4_194_304 / originals.size)
    originals.map { data -> copy(data, budget) }
}

private fun copy(data: ByteArray, budget: Int): ByteArray {
    for (pixels in listOf(1280, 960, 720, 480, 320)) {
        val bitmap = try {
            ImageDecoder.decodeBitmap(ImageDecoder.createSource(ByteBuffer.wrap(data))) { decoder, info, _ ->
                decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE // compress reads the pixels
                val (w, h) = info.size.width to info.size.height
                val scale = pixels.toDouble() / maxOf(w, h)
                if (scale < 1) decoder.setTargetSize((w * scale).roundToInt().coerceAtLeast(1), (h * scale).roundToInt().coerceAtLeast(1))
            }
        } catch (_: Exception) {
            throw ResponsesClient.Failure.InvalidInput
        }
        try {
            for (quality in listOf(70, 50, 30)) {
                val out = ByteArrayOutputStream().also { bitmap.compress(Bitmap.CompressFormat.JPEG, quality, it) }.toByteArray()
                if (out.size <= budget) return out
            }
        } finally {
            bitmap.recycle()
        }
    }
    throw ResponsesClient.Failure.LimitExceeded
}
