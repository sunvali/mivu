package com.yakov103.mivu.ui.coach

import androidx.camera.core.ImageCapture
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.yakov103.mivu.R
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.log2
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlin.math.sin

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

/** Cycles Auto, On, Off; [mode] is an `ImageCapture.FLASH_MODE_*` value. */
@Composable
fun CameraFlashButton(mode: Int, onChange: (Int) -> Unit) {
    val (icon, name) = when (mode) {
        ImageCapture.FLASH_MODE_ON -> R.drawable.ic_flash_on to "On"
        ImageCapture.FLASH_MODE_OFF -> R.drawable.ic_flash_off to "Off"
        else -> R.drawable.ic_flash_auto to "Auto"
    }
    IconButton({ onChange(nextFlash(mode)) }, Modifier.size(48.dp).background(Scrim, CircleShape)
        .semantics { contentDescription = "Flash"; stateDescription = name }) {
        Icon(painterResource(icon), contentDescription = null, tint = if (mode == ImageCapture.FLASH_MODE_ON) Color.Yellow else Color.White)
    }
}

const val LENS_BAR_TAG = "cameraLensBar"

/**
 * One button per back lens; the lens in use shows the live zoom. Sliding a finger along the buttons turns a zoom dial,
 * as in the system camera; a still finger is a tap on a lens. Hidden on a single-lens camera. [onZoomBy] takes a ratio.
 */
@Composable
fun CameraLensBar(zoom: Float, lenses: List<Float>, onZoom: (Float) -> Unit, onZoomBy: (Float) -> Unit) {
    if (lenses.size < 2) return
    val current = currentLens(zoom, lenses)
    val haptic = LocalHapticFeedback.current
    var ticked by remember { mutableStateOf(current) }
    LaunchedEffect(current) { if (current != ticked) { haptic.performHapticFeedback(HapticFeedbackType.SegmentTick); ticked = current } }
    var sliding by remember { mutableStateOf(false) }
    // System animator scale 0 (Remove animations) makes this instant.
    val dial by animateFloatAsState(if (sliding) 1f else 0f, tween(if (sliding) 150 else 300), label = "dial")
    val measurer = rememberTextMeasurer()
    Row(Modifier.testTag(LENS_BAR_TAG)
        .drawBehind { if (dial > 0f) drawZoomDial(zoom, lenses, measurer, dial) }
        .pointerInput(Unit) {
            detectHorizontalDragGestures(onDragStart = { sliding = true }, onDragEnd = { sliding = false }, onDragCancel = { sliding = false }) { change, amount ->
                change.consume()
                onZoomBy(slideZoom(1f, amount.toDp().value))
            }
        },
        horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        for (lens in lenses) {
            val active = lens == current
            Box(Modifier.sizeIn(minWidth = 48.dp, minHeight = 48.dp).clip(RoundedCornerShape(50)).background(Scrim)
                .clickable { onZoom(lens) }.padding(horizontal = 6.dp)
                .semantics { contentDescription = "${zoomText(lens)} times zoom"; selected = active },
                contentAlignment = Alignment.Center) {
                Text(if (active) "${zoomText(zoom)}×" else zoomText(lens), color = if (active) Color.Yellow else Color.White,
                    style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.SemiBold, fontFeatureSettings = "tnum"))
            }
        }
    }
}

/** The iOS arc of ticks, centred above the lens buttons. Each doubling of zoom is the same distance along it. */
private fun DrawScope.drawZoomDial(zoom: Float, lenses: List<Float>, measurer: TextMeasurer, alpha: Float) {
    val width = 280.dp.toPx(); val height = 76.dp.toPx()
    val left = (size.width - width) / 2; val top = -(height + 8.dp.toPx())
    val radius = 300.dp.toPx(); val arcTop = top + 26.dp.toPx()
    val cx = left + width / 2; val cy = arcTop + radius
    drawRoundRect(Color.Black.copy(alpha = 0.35f * alpha), Offset(left, top), Size(width, height), CornerRadius(18.dp.toPx()))
    fun label(text: String, color: Color, style: TextStyle, at: Offset) {
        val layout = measurer.measure(text, style.copy(color = color))
        drawText(layout, topLeft = at - Offset(layout.size.width / 2f, layout.size.height / 2f), alpha = alpha)
    }
    fun mark(value: Float, lens: Boolean) {
        val angle = log2(value / zoom) * DIAL_DP_PER_DOUBLING.dp.toPx() / radius
        if (abs(angle) >= 0.5f) return
        fun point(distance: Float) = Offset(cx + sin(angle) * distance, cy - cos(angle) * distance)
        drawLine(Color.White.copy(alpha = (if (lens) 1f else 0.5f) * alpha), point(radius), point(radius - (if (lens) 12 else 6).dp.toPx()),
            (if (lens) 2 else 1).dp.toPx())
        if (lens) label(zoomText(value), Color.White, TextStyle(fontSize = 11.sp, fontWeight = FontWeight.SemiBold), point(radius - 24.dp.toPx()))
    }
    val widest = lenses.first(); val longest = lenses.last()
    for (step in 0..(log2(longest * 2 / widest) * 10).toInt()) mark(widest * 2f.pow(step / 10f), lens = false)
    lenses.forEach { mark(it, lens = true) }
    drawLine(Color.Yellow.copy(alpha = alpha), Offset(cx, arcTop - 6.dp.toPx()), Offset(cx, arcTop + 16.dp.toPx()), 2.dp.toPx())
    label("${zoomText(zoom)}×", Color.Yellow, TextStyle(fontSize = 12.sp, fontWeight = FontWeight.SemiBold), Offset(cx, top + 9.dp.toPx()))
}
