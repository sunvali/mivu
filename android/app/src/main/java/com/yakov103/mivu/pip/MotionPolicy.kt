package com.yakov103.mivu.pip

import android.database.ContentObserver
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.currentStateAsState

/** When Pip may move, as iOS `MotionPolicy`: hidden off screen, still under Remove animations or severe heat; Power Saver keeps Pip moving, as iOS Low Power Mode. */
object MotionPolicy {
    enum class Playback { Hidden, StaticPose, Animated }

    /** [covered]: the screen's own sheet, picker or camera is over the surface (iOS `covered`). */
    fun playback(removeAnimations: Boolean, thermalStatus: Int, resumed: Boolean, covered: Boolean = false): Playback = when {
        !resumed || covered -> Playback.Hidden
        removeAnimations || thermalStatus >= PowerManager.THERMAL_STATUS_SEVERE -> Playback.StaticPose
        else -> Playback.Animated
    }
}

/** The live [MotionPolicy] for this screen: "Remove animations", thermal status, the lifecycle and [covered]. */
@Composable
fun rememberMotionPlayback(covered: Boolean = false): MotionPolicy.Playback {
    val context = LocalContext.current
    val power = remember(context) { context.getSystemService(PowerManager::class.java) }
    var removeAnimations by remember { mutableStateOf(!android.animation.ValueAnimator.areAnimatorsEnabled()) }
    var thermal by remember { mutableIntStateOf(power.currentThermalStatus) }
    val resumed = LocalLifecycleOwner.current.lifecycle.currentStateAsState().value.isAtLeast(Lifecycle.State.RESUMED)
    DisposableEffect(context) {
        val main = Handler(Looper.getMainLooper())
        val scale = Settings.Global.getUriFor(Settings.Global.ANIMATOR_DURATION_SCALE)
        // The setting itself, not ValueAnimator: the process copy of the scale can update after this callback.
        val observer = object : ContentObserver(main) {
            override fun onChange(selfChange: Boolean) {
                removeAnimations = Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
            }
        }
        val heat = PowerManager.OnThermalStatusChangedListener { thermal = it }
        context.contentResolver.registerContentObserver(scale, false, observer)
        power.addThermalStatusListener(context.mainExecutor, heat)
        // Read again now that the listeners are live, so a change between the first read and registration is not lost.
        removeAnimations = Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
        thermal = power.currentThermalStatus
        onDispose {
            context.contentResolver.unregisterContentObserver(observer)
            power.removeThermalStatusListener(heat)
        }
    }
    return MotionPolicy.playback(removeAnimations, thermal, resumed, covered)
}
