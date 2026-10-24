package com.yakov103.mivu.ui.progress

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.yakov103.mivu.progress.ProgressBand
import com.yakov103.mivu.progress.ProgressBucket
import com.yakov103.mivu.progress.ProgressCalendarDot
import com.yakov103.mivu.progress.ProgressRange
import com.yakov103.mivu.progress.TrendPoint
import com.yakov103.mivu.progress.kcal
import com.yakov103.mivu.ui.theme.MivuTheme
import java.text.NumberFormat
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.Locale
import kotlin.math.floor

// Compose Canvas ports of the iOS Swift Charts on Progress (ProgressCards.swift ProgressBucketChart, the weight
// sparkline and chart, ProgressCalendarRow), plus the mockup's macro donut. Each chart speaks the iOS summary.

/** iOS `ProgressBand.color`: near is the accent; null (not judged) has no band colour. */
@Composable
internal fun bandColor(band: ProgressBand?): Color? = when (band) {
    ProgressBand.Near -> MaterialTheme.colorScheme.primary
    ProgressBand.BitOff -> MivuTheme.colors.bandBitOff
    ProgressBand.Off -> MivuTheme.colors.bandOff
    ProgressBand.FarOff -> MivuTheme.colors.bandFarOff
    null -> null
}

private fun format(date: LocalDate, pattern: String) = date.format(DateTimeFormatter.ofPattern(pattern, Locale.US))

internal fun oneDecimal(value: Double): String =
    NumberFormat.getNumberInstance(Locale.US).apply { minimumFractionDigits = 1; maximumFractionDigits = 1 }.format(value)

/** iOS `ProgressSummary.buckets`: every logged bar, "Oct 21: 1,940 kcal, near". Missing days are left out, never zero. */
internal fun bucketSummary(buckets: List<ProgressBucket>): String {
    val logged = buckets.filter { it.averageKcal != null }
    if (logged.isEmpty()) return "No logged days in this range."
    return logged.joinToString("; ") { "${format(it.start, "MMM d")}: ${kcal(it.averageKcal!!)}${it.band?.let { b -> ", ${b.title.lowercase()}" }.orEmpty()}" }
}

/** iOS `ProgressSummary.weights`. */
internal fun weightSummary(trend: List<TrendPoint>): String {
    val last = trend.lastOrNull() ?: return "No weigh-ins in this range."
    return "${trend.size} weigh-ins. Trend ${oneDecimal(last.trend)} kg on ${last.localDate}."
}

/** What one bar stands for: a day (Week, Month), a week (3M) or a month (Year). */
internal fun bucketUnit(range: ProgressRange) = when (range) {
    ProgressRange.Week, ProgressRange.Month -> "day"
    ProgressRange.Quarter -> "week"
    ProgressRange.Year -> "month"
}

/** "Oct 21: 1,940 kcal" for a selected bar, or "Oct 21: no log". */
internal fun bucketValue(bucket: ProgressBucket, range: ProgressRange): String {
    val date = format(bucket.start, if (range == ProgressRange.Year) "MMMM yyyy" else "MMM d")
    return "$date: ${bucket.averageKcal?.let(::kcal) ?: "no log"}${bucket.band?.let { ", ${it.title.lowercase()}" }.orEmpty()}"
}

/**
 * Bars per bucket coloured by how far each landed from its own target, with a stepped dashed target line. A bucket with
 * no log is a dashed outline, never a zero bar; a partial or pending bucket is drawn at 45% with no band. The node speaks
 * "[label]. [bucketSummary]".
 */
@Composable
internal fun BucketChart(
    buckets: List<ProgressBucket>,
    range: ProgressRange,
    label: String,
    height: Dp,
    modifier: Modifier = Modifier,
    today: LocalDate? = null,
    selected: Int? = null,
    onSelect: ((Int) -> Unit)? = null,
) {
    val muted = MaterialTheme.colorScheme.onSurfaceVariant
    val rule = MaterialTheme.colorScheme.outline
    val targetColor = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.45f)
    val highlight = MaterialTheme.colorScheme.primary.copy(alpha = 0.12f)
    val fills = buckets.map { bandColor(it.band) ?: if (it.complete) muted else muted.copy(alpha = 0.45f) }
    val measurer = rememberTextMeasurer()
    val labelStyle = MaterialTheme.typography.labelSmall.copy(color = muted)
    val labels = axisLabels(buckets, range, today)
    val summary = "$label. ${bucketSummary(buckets)}"
    val tap = if (onSelect == null) Modifier else Modifier.pointerInput(buckets.size) {
        detectTapGestures { offset -> if (buckets.isNotEmpty()) onSelect(floor(offset.x / (size.width / buckets.size)).toInt().coerceIn(0, buckets.lastIndex)) }
    }
    Canvas(modifier.fillMaxWidth().height(height).then(tap).clearAndSetSemantics { contentDescription = summary }) {
        if (buckets.isEmpty()) return@Canvas
        val labelHeight = measurer.measure("M", labelStyle).size.height + 4.dp.toPx()
        val chart = size.height - labelHeight
        val top = (buckets.flatMap { listOfNotNull(it.averageKcal, it.averageTarget) }.maxOrNull() ?: 2000.0) * 1.08
        fun y(value: Double) = (chart * (1 - value / top)).toFloat()
        val slot = size.width / buckets.size
        val bar = slot * if (range == ProgressRange.Week) 0.56f else 0.66f
        val corner = minOf((if (range == ProgressRange.Week) 8.dp else 3.dp).toPx(), bar / 2)
        // A day with no log is a dashed ghost the height of its target (or a typical bar), so the gap reads as a gap.
        val ghost = buckets.mapNotNull { it.averageTarget }.average().takeIf { !it.isNaN() }
            ?: buckets.mapNotNull { it.averageKcal }.average().takeIf { !it.isNaN() } ?: top * 0.6
        val dash = PathEffect.dashPathEffect(floatArrayOf(4.dp.toPx(), 3.dp.toPx()))
        buckets.forEachIndexed { i, bucket ->
            val left = i * slot + (slot - bar) / 2
            if (i == selected) drawRoundRect(highlight, Offset(i * slot, 0f), Size(slot, chart), CornerRadius(corner))
            val value = bucket.averageKcal
            if (value == null) {
                val stroke = 1.dp.toPx()
                drawRoundRect(rule, Offset(left + stroke / 2, y(ghost)), Size(bar - stroke, chart - y(ghost) - stroke / 2), CornerRadius(corner),
                    style = Stroke(stroke, pathEffect = dash))
            } else {
                drawRoundRect(fills[i], Offset(left, y(value)), Size(bar, chart - y(value)), CornerRadius(corner))
            }
        }
        // The stepped target: a dash across each bar's slot, joined where the target changes.
        val targetDash = PathEffect.dashPathEffect(floatArrayOf(5.dp.toPx(), 4.dp.toPx()))
        val width = 1.5.dp.toPx()
        var previous: Float? = null
        buckets.forEachIndexed { i, bucket ->
            val target = bucket.averageTarget?.let(::y)
            if (target == null) { previous = null; return@forEachIndexed }
            previous?.let { if (it != target) drawLine(targetColor, Offset(i * slot, it), Offset(i * slot, target), width, pathEffect = targetDash) }
            drawLine(targetColor, Offset(i * slot, target), Offset((i + 1) * slot, target), width, pathEffect = targetDash)
            previous = target
        }
        labels.forEach { (i, text) ->
            val layout = measurer.measure(text, labelStyle)
            val x = (i * slot + slot / 2 - layout.size.width / 2f).coerceIn(0f, size.width - layout.size.width)
            drawText(layout, topLeft = Offset(x, chart + 4.dp.toPx()))
        }
    }
}

/** Axis labels by bar index, counted back from the newest so the latest bar is always named. */
private fun axisLabels(buckets: List<ProgressBucket>, range: ProgressRange, today: LocalDate?): List<Pair<Int, String>> {
    val stride = when (range) { ProgressRange.Week -> 1; ProgressRange.Month -> 7; ProgressRange.Quarter -> 4; ProgressRange.Year -> 3 }
    return buckets.indices.reversed().filter { (buckets.lastIndex - it) % stride == 0 }.map { i ->
        val start = buckets[i].start
        i to when (range) {
            ProgressRange.Week -> if (start == today) "Today" else format(start, "EEEEE")
            ProgressRange.Month, ProgressRange.Quarter -> format(start, "MMM d")
            ProgressRange.Year -> format(start, "MMM")
        }
    }
}

/** The band key under a bucket chart; stacked one per line at large text so no entry is cut. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun ChartLegend(modifier: Modifier = Modifier) {
    val entries = listOf(ProgressBand.Near, ProgressBand.BitOff, ProgressBand.Off, ProgressBand.FarOff, null)
    val rule = MaterialTheme.colorScheme.outline
    val item: @Composable (ProgressBand?) -> Unit = { band ->
        Row(Modifier.testTag("legendItem"), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            val color = bandColor(band)
            Canvas(Modifier.size(8.dp)) {
                if (color != null) drawCircle(color)
                else drawCircle(rule, style = Stroke(1.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(2f, 2f))))
            }
            Text(band?.title ?: "No log", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
    // The bars already speak each band; the key is decorative for TalkBack.
    val m = modifier.testTag("chartLegend").semantics(mergeDescendants = true) {}
    if (LocalDensity.current.fontScale >= 1.5f) Column(m, verticalArrangement = Arrangement.spacedBy(4.dp)) { entries.forEach { item(it) } }
    else FlowRow(m, horizontalArrangement = Arrangement.spacedBy(10.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) { entries.forEach { item(it) } }
}

/**
 * A weight line over dates: x by elapsed days, y fitted to the values (never from zero). [dots] marks each value, as the
 * iOS point marks; the sparkline draws the line only. A tap selects the nearest date.
 */
@Composable
internal fun TrendChart(
    points: List<Pair<String, Double>>,
    summary: String,
    height: Dp,
    modifier: Modifier = Modifier,
    dots: Boolean = true,
    selected: Int? = null,
    onSelect: ((Int) -> Unit)? = null,
) {
    val color = MivuTheme.colors.protein // iOS diaryWeight
    val dates = points.map { runCatching { LocalDate.parse(it.first) }.getOrNull() ?: LocalDate.MIN }
    val first = dates.firstOrNull()
    val span = if (first == null) 0L else ChronoUnit.DAYS.between(first, dates.last())
    fun fraction(i: Int) = if (span == 0L) 0.5f else ChronoUnit.DAYS.between(first, dates[i]).toFloat() / span
    val tap = if (onSelect == null || points.isEmpty()) Modifier else Modifier.pointerInput(points) {
        detectTapGestures { offset ->
            val pad = 8.dp.toPx()
            val at = (offset.x - pad) / (size.width - 2 * pad)
            onSelect(points.indices.minBy { kotlin.math.abs(fraction(it) - at) })
        }
    }
    Canvas(modifier.fillMaxWidth().height(height).then(tap).clearAndSetSemantics { contentDescription = summary }) {
        if (points.isEmpty()) return@Canvas
        val pad = 8.dp.toPx()
        val low = points.minOf { it.second }; val high = points.maxOf { it.second }
        val spread = if (high - low < 0.5) 0.5 else high - low
        val bottom = low - spread * 0.15; val top = high + spread * 0.15
        fun at(i: Int) = Offset(pad + fraction(i) * (size.width - 2 * pad), (pad + (size.height - 2 * pad) * (1 - (points[i].second - bottom) / (top - bottom))).toFloat())
        if (points.size >= 2) {
            val line = Path().apply { points.indices.forEach { if (it == 0) moveTo(at(it).x, at(it).y) else lineTo(at(it).x, at(it).y) } }
            val area = Path().apply { addPath(line); lineTo(at(points.lastIndex).x, size.height); lineTo(at(0).x, size.height); close() }
            drawPath(area, color.copy(alpha = 0.10f))
            drawPath(line, color, style = Stroke(3.dp.toPx(), cap = StrokeCap.Round))
        }
        if (dots || points.size == 1) points.indices.forEach { drawCircle(color, if (it == selected) 6.dp.toPx() else 3.5.dp.toPx(), at(it)) }
        selected?.let { drawLine(color.copy(alpha = 0.4f), Offset(at(it).x, 0f), Offset(at(it).x, size.height), 1.dp.toPx()) }
    }
}

/**
 * The average day's energy split: protein, carbs and fat as shares of their kcal (4, 4, 9 per gram) round a ring, with
 * the average kcal inside. Speaks every macro and the total.
 */
@Composable
internal fun MacroDonut(protein: Double?, carbs: Double?, fat: Double?, averageKcal: Double?, size: Dp, modifier: Modifier = Modifier) {
    val colors = MivuTheme.colors
    val track = MaterialTheme.colorScheme.outlineVariant
    val parts = listOf((protein ?: 0.0) * 4 to colors.protein, (carbs ?: 0.0) * 4 to colors.carbs, (fat ?: 0.0) * 9 to colors.fat)
    val total = parts.sumOf { it.first }
    fun grams(v: Double?) = v?.let { "${NumberFormat.getIntegerInstance(Locale.US).format(it)} g" } ?: "unknown"
    val spoken = "Average day: ${averageKcal?.let(::kcal) ?: "no complete days"}. Protein ${grams(protein)}, carbs ${grams(carbs)}, fat ${grams(fat)}."
    Box(modifier.size(size).clearAndSetSemantics { contentDescription = spoken }, contentAlignment = Alignment.Center) {
        Canvas(Modifier.size(size)) { ring(parts, total, track) }
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(averageKcal?.let { NumberFormat.getIntegerInstance(Locale.US).format(it) } ?: "—",
                style = MaterialTheme.typography.titleLarge.tabularBold())
            Text("kcal", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

private fun TextStyle.tabularBold() = copy(fontFeatureSettings = "tnum", fontWeight = androidx.compose.ui.text.font.FontWeight.Bold)

private fun DrawScope.ring(parts: List<Pair<Double, Color>>, total: Double, track: Color) {
    val width = 12.dp.toPx()
    val inset = width / 2
    val arc = Size(size.width - width, size.height - width)
    if (total <= 0) { drawArc(track, 0f, 360f, false, Offset(inset, inset), arc, style = Stroke(width)); return }
    val gap = 3f
    var start = -90f
    parts.filter { it.first > 0 }.forEach { (value, color) ->
        val sweep = (value / total * 360).toFloat()
        drawArc(color, start + gap / 2, (sweep - gap).coerceAtLeast(0.5f), false, Offset(inset, inset), arc, style = Stroke(width, cap = StrokeCap.Butt))
        start += sweep
    }
}

/** iOS `ProgressCalendarRow` dots: a dashed ring for no log, a band-coloured dot (grey at 45% when not judged) for a log. */
@Composable
internal fun CalendarDots(dots: List<ProgressCalendarDot>, modifier: Modifier = Modifier) {
    val rule = MaterialTheme.colorScheme.outline
    val muted = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.45f)
    val fills = dots.map { (it as? ProgressCalendarDot.Logged)?.let { dot -> bandColor(dot.band) ?: muted } }
    Canvas(modifier.height(18.dp).fillMaxWidth()) {
        val d = 18.dp.toPx(); val step = d + 6.dp.toPx()
        dots.forEachIndexed { i, dot ->
            val center = Offset(i * step + d / 2, d / 2)
            when (dot) {
                ProgressCalendarDot.Outside -> Unit
                ProgressCalendarDot.NoLog -> drawCircle(rule, d / 2 - 0.5.dp.toPx(), center,
                    style = Stroke(1.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(2.dp.toPx(), 2.dp.toPx()))))
                is ProgressCalendarDot.Logged -> drawCircle(fills[i]!!, d / 2, center)
            }
        }
    }
}
