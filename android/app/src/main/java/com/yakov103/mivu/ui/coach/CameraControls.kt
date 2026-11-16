package com.yakov103.mivu.ui.coach

import androidx.camera.core.ImageCapture
import kotlin.math.pow
import kotlin.math.roundToInt

// Port of iOS ios/Mivu/Coach/CoachCameraControls.swift and the CoachCameraSession lens/zoom statics.

/** Each doubling of zoom is this far along the lens buttons, so the dial follows the finger. */
const val DIAL_DP_PER_DOUBLING = 90f

private fun tenths(zoom: Float) = (zoom * 10).roundToInt() / 10f

/** One zoom per back lens, widest first, as the phone reports them; empty on a single-lens camera. */
fun lensZooms(intrinsicRatios: List<Float>): List<Float> =
    intrinsicRatios.map(::tenths).distinct().sorted().takeIf { it.size > 1 } ?: emptyList()

/** Past twice the longest lens the picture is too soft to read a plate or a label; never past what the camera allows. */
fun clampedZoom(zoom: Float, lenses: List<Float>, min: Float, max: Float): Float =
    zoom.coerceIn(maxOf(min, lenses.firstOrNull() ?: min), minOf(max, lenses.lastOrNull()?.times(2) ?: max))

/** The lens in use: the longest one the zoom has reached. */
fun currentLens(zoom: Float, lenses: List<Float>): Float? = lenses.lastOrNull { it <= zoom + 0.01f } ?: lenses.firstOrNull()

fun zoomText(zoom: Float): String = tenths(zoom).let { if (it % 1f == 0f) it.toInt().toString() else it.toString() }

/** Sliding right zooms out; sent as a ratio of the current zoom, like a pinch. */
fun slideZoom(zoom: Float, slidDp: Float): Float = zoom * 2f.pow(-slidDp / DIAL_DP_PER_DOUBLING)

/** Auto → On → Off → Auto, as iOS. */
fun nextFlash(mode: Int): Int = when (mode) {
    ImageCapture.FLASH_MODE_AUTO -> ImageCapture.FLASH_MODE_ON
    ImageCapture.FLASH_MODE_ON -> ImageCapture.FLASH_MODE_OFF
    else -> ImageCapture.FLASH_MODE_AUTO
}
