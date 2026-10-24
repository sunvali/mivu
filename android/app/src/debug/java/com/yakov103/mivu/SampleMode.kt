package com.yakov103.mivu

import android.content.Intent

/** Debug-only switch: launch with the intent extra `sampleMode=true` to use the synthetic analyzer. */
object SampleMode {
    @Volatile var enabled = false
        private set

    internal fun reset() { enabled = false }

    fun configure(intent: Intent?) { if (intent?.getBooleanExtra("sampleMode", false) == true) enabled = true }
}
