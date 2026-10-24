package com.yakov103.mivu.pip

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
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
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.currentStateAsState

/** When Pip may move, as iOS `MotionPolicy`: hidden off screen, still under any motion or power constraint. */
object MotionPolicy {
    enum class Playback { Hidden, StaticPose, Animated }

    fun playback(removeAnimations: Boolean, powerSave: Boolean, thermalStatus: Int, resumed: Boolean): Playback = when {
        !resumed -> Playback.Hidden
        removeAnimations || powerSave || thermalStatus >= PowerManager.THERMAL_STATUS_SEVERE -> Playback.StaticPose
        else -> Playback.Animated
    }
}

/** The live [MotionPolicy] for this screen: "Remove animations", Power Saver, thermal status and the lifecycle. */
@Composable
fun rememberMotionPlayback(): MotionPolicy.Playback {
    val context = LocalContext.current
    val power = remember(context) { context.getSystemService(PowerManager::class.java) }
    var removeAnimations by remember { mutableStateOf(!android.animation.ValueAnimator.areAnimatorsEnabled()) }
    var powerSave by remember { mutableStateOf(power.isPowerSaveMode) }
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
        val saver = object : BroadcastReceiver() {
            override fun onReceive(c: Context, intent: Intent) { powerSave = power.isPowerSaveMode }
        }
        val heat = PowerManager.OnThermalStatusChangedListener { thermal = it }
        context.contentResolver.registerContentObserver(scale, false, observer)
        ContextCompat.registerReceiver(context, saver, IntentFilter(PowerManager.ACTION_POWER_SAVE_MODE_CHANGED), ContextCompat.RECEIVER_NOT_EXPORTED)
        power.addThermalStatusListener(context.mainExecutor, heat)
        onDispose {
            context.contentResolver.unregisterContentObserver(observer)
            context.unregisterReceiver(saver)
            power.removeThermalStatusListener(heat)
        }
    }
    return MotionPolicy.playback(removeAnimations, powerSave, thermal, resumed)
}
