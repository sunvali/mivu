package com.yakov103.mivu.ui.coach

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

// Port of ios/Mivu/Coach/CoachVoiceInput.swift on the platform SpeechRecognizer.

/**
 * Fills the Coach draft from speech. Audio is never stored or sent by the app, and transcripts are never logged; only text
 * the user sends leaves the draft. Call everything on the main thread, as SpeechRecognizer requires.
 * [listen] starts a recognizer and returns its release; tests pass a fake and drive [listener] themselves.
 */
class CoachVoiceInput(
    private val context: Context,
    val available: Boolean = SpeechRecognizer.isRecognitionAvailable(context),
    private val listen: (Intent, RecognitionListener) -> () -> Unit = { intent, listener -> platform(context, intent, listener) },
) {
    enum class Phase { Idle, Preparing, Listening }

    private val _phase = MutableStateFlow(Phase.Idle)
    val phase: StateFlow<Phase> = _phase.asStateFlow()
    /** Recent microphone levels, oldest first, each 0...1, for the live wave. */
    private val _levels = MutableStateFlow(SILENT)
    val levels: StateFlow<List<Float>> = _levels.asStateFlow()
    private val _note = MutableStateFlow(if (available) null else UNAVAILABLE)
    val note: StateFlow<String?> = _note.asStateFlow()

    private var release: (() -> Unit)? = null
    private var draft = ""
    private var update: (String) -> Unit = {}

    /** Streams the transcript appended to [draft] into [update] until [stop] or the end of the utterance. */
    fun start(draft: String, update: (String) -> Unit) {
        if (_phase.value != Phase.Idle) return
        if (!available) { _note.value = UNAVAILABLE; return }
        if (context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            _note.value = PERMISSION; return
        }
        _note.value = null
        this.draft = draft
        this.update = update
        _phase.value = Phase.Preparing
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
            .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            .putExtra(RecognizerIntent.EXTRA_LANGUAGE, "en-US")
            .putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
        try {
            release = listen(intent, listener)
        } catch (_: RuntimeException) {
            stop()
            _note.value = UNAVAILABLE
        }
    }

    /** Releases the microphone; the words already in the draft stay. */
    fun stop() {
        if (_phase.value == Phase.Idle) return
        _phase.value = Phase.Idle
        release?.invoke()
        release = null
        update = {}
        _levels.value = SILENT
    }

    val listener = object : RecognitionListener {
        override fun onReadyForSpeech(params: Bundle?) { if (_phase.value == Phase.Preparing) _phase.value = Phase.Listening }
        override fun onRmsChanged(rmsdB: Float) { if (_phase.value == Phase.Listening) _levels.value = _levels.value.drop(1) + level(rmsdB) }
        override fun onPartialResults(partialResults: Bundle?) = deliver(partialResults)
        override fun onResults(results: Bundle?) {
            deliver(results)
            stop() // one utterance per start: tapping the mic again appends to the draft
        }
        override fun onError(error: Int) {
            if (_phase.value == Phase.Idle) return // late errors from a released recognizer
            stop()
            _note.value = when (error) {
                SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> PERMISSION
                SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED, SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE -> UNAVAILABLE
                // Includes no match, speech timeout and a busy recognizer: nothing typed or heard is lost.
                else -> STOPPED
            }
        }
        override fun onBeginningOfSpeech() = Unit
        override fun onBufferReceived(buffer: ByteArray?) = Unit
        override fun onEndOfSpeech() = Unit
        override fun onEvent(eventType: Int, params: Bundle?) = Unit
    }

    private fun deliver(results: Bundle?) {
        if (_phase.value == Phase.Idle) return
        val spoken = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull() ?: return
        update(merged(draft, spoken))
    }

    companion object {
        const val PERMISSION = "Allow microphone access in Settings to log by voice."
        const val UNAVAILABLE = "Voice input isn't available on this phone. Type, or use the keyboard microphone."
        const val STOPPED = "Voice input stopped. Your text is kept."
        const val WAVE_BARS = 3
        private val SILENT = List(WAVE_BARS) { 0f }

        fun merged(draft: String, spoken: String): String {
            val spoken = spoken.trim()
            if (spoken.isEmpty()) return draft
            if (draft.isEmpty()) return spoken
            return if (draft.last().isWhitespace()) draft + spoken else "$draft $spoken"
        }

        /** Maps onRmsChanged, about -2...10 dB, onto 0...1. */
        fun level(rmsDb: Float): Float = ((rmsDb + 2f) / 12f).coerceIn(0f, 1f)

        private fun platform(context: Context, intent: Intent, listener: RecognitionListener): () -> Unit {
            val recognizer = if (SpeechRecognizer.isOnDeviceRecognitionAvailable(context)) SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
            else SpeechRecognizer.createSpeechRecognizer(context)
            recognizer.setRecognitionListener(listener)
            recognizer.startListening(intent)
            return recognizer::destroy
        }
    }
}
