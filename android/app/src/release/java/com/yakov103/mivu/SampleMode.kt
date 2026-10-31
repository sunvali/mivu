package com.yakov103.mivu

import android.content.Intent

/** Release has no hidden modes: sample mode is a constant false. */
object SampleMode {
    const val enabled = false

    @Suppress("UNUSED_PARAMETER") fun configure(intent: Intent?) = Unit
}
