package com.yakov103.mivu.pip

import android.content.Context
import android.graphics.RectF
import androidx.compose.animation.core.withInfiniteAnimationFrameNanos
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Modifier
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.yakov103.mivu.pip.MotionPolicy.Playback
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlin.math.roundToInt

/**
 * Pip on a surface, as iOS `CompanionView`: Coach is [size] wide, Today is [size] tall, both in the rig's crop aspect.
 * Frames run only while animated; touches count only then (a long press is a pat). Decorative and hidden from
 * accessibility: native text carries every status.
 */
@Composable
fun PipCompanion(
    output: CompanionOutput,
    surface: CompanionSurface,
    size: Dp,
    runtime: CompanionRuntime,
    onTouch: (CompanionTouch) -> Unit,
    modifier: Modifier = Modifier,
) {
    val key = if (surface == CompanionSurface.Coach) "coach" else "today"
    val crop = runtime.motion.scene.asset.frames[key]
    val aspect = crop?.let { it[2] / it[3] } ?: if (surface == CompanionSurface.Coach) 281f / 288.8f else 399.8f / 455.5f
    // Whole dp on Coach, so the composer below lands on pixel boundaries.
    val frame = if (surface == CompanionSurface.Coach) Modifier.size(size, (size.value / aspect).roundToInt().dp) else Modifier.size(size * aspect, size)
    val animated = output.playback == Playback.Animated
    val time = remember { mutableLongStateOf(0L) }
    val applied = remember { mutableIntStateOf(0) }
    LaunchedEffect(runtime, output, surface) {
        runtime.apply(output, surface)
        applied.intValue++ // the still pose was written outside snapshot state: redraw once
    }
    DisposableEffect(runtime) { onDispose { runtime.stop() } }
    if (animated) LaunchedEffect(runtime) {
        while (true) withInfiniteAnimationFrameNanos { time.longValue = it; runtime.frames++ }
    }
    val haptics = LocalHapticFeedback.current
    val touch by rememberUpdatedState(onTouch)
    val input = if (!animated) Modifier else Modifier.pointerInput(Unit) {
        detectTapGestures(
            onLongPress = { haptics.performHapticFeedback(HapticFeedbackType.LongPress); touch(CompanionTouch.Pat) },
            onTap = { haptics.performHapticFeedback(HapticFeedbackType.ContextClick); touch(CompanionTouch.Tap) },
        )
    }
    PipRig(
        runtime.motion.scene,
        // A still Pip samples the settled pose: no blink or spring is caught midway.
        { applied.intValue; runtime.motion.sample(if (animated) time.longValue else Long.MAX_VALUE / 2) },
        isSystemInDarkTheme(),
        key.takeIf { crop != null },
        modifier.then(frame).then(input).testTag("pipCompanion").clearAndSetSemantics {},
    )
}

/** Pip's rig and gestures, read once per process off the main thread. */
object PipAssets {
    private val lock = Mutex()
    private var loaded: Pair<PipRigScene, PipGestureLibrary>? = null

    suspend fun load(context: Context): Pair<PipRigScene, PipGestureLibrary> = lock.withLock {
        loaded ?: withContext(Dispatchers.IO) {
            val assets = context.applicationContext.assets
            val asset = PipRigAsset.load(assets.open("pip/pip-rig.json").use { it.readBytes() })
            val library = PipGestureLibrary.load(assets.open("gestures.json").use { it.readBytes().decodeToString() })
            val rect = RectF()
            val byID = asset.parts.associateBy { it.id }
            val scene = PipRigScene(asset) { id ->
                @Suppress("DEPRECATION") // computeBounds(RectF) is API 34; minSdk is 31
                path(parsePath(byID.getValue(id).path)).computeBounds(rect, true)
                floatArrayOf(rect.left, rect.top, rect.right, rect.bottom)
            }
            scene to library
        }.also { loaded = it }
    }
}
