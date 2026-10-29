package com.yakov103.mivu.ui.settings

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.launch

/** One Gemini Nano download for a screen: its progress (null when idle) and whether the last try failed. */
internal class NanoDownload(private val scope: CoroutineScope, private val download: () -> Flow<Float>, private val onDone: () -> Unit) {
    var progress by mutableStateOf<Float?>(null)
        private set
    var failed by mutableStateOf(false)
        private set

    fun start() {
        if (progress != null) return
        progress = 0f; failed = false
        // shortcut: leaving the screen cancels this collection, so a restart resumes from the system's progress.
        scope.launch {
            try {
                download().collect { progress = it }
                onDone()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                failed = true
            } finally {
                progress = null
            }
        }
    }
}

@Composable
internal fun rememberNanoDownload(download: () -> Flow<Float>, onDone: () -> Unit = {}): NanoDownload {
    val scope = rememberCoroutineScope()
    return remember { NanoDownload(scope, download, onDone) }
}
