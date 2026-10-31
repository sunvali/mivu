package com.yakov103.mivu.report

import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.pdf.PdfDocument
import android.text.TextPaint
import android.text.TextUtils
import android.text.format.DateFormat
import java.io.ByteArrayOutputStream
import java.text.NumberFormat
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.abs
import kotlin.math.roundToLong

// Port of ios/Mivu/Diary/DiaryReportPDF.swift, without the Pip preview in the header until the app-icon row adds Pip art.

private const val PAGE_WIDTH = 595f
private const val PAGE_HEIGHT = 842f
private const val MARGIN = 40f
private const val WIDTH = PAGE_WIDTH - 2 * MARGIN

// Print colors stay light-mode regardless of the device appearance.
private const val INK = 0xFF142023.toInt()
private const val SECONDARY = 0xFF53646B.toInt()
private const val ACCENT = 0xFF006D75.toInt()
private const val OVER = 0xFFB33143.toInt()
private const val RULE = 0xFFD5DFE1.toInt()
private const val TILE = 0xFFEAF5F3.toInt()

/** Layout B: a one-page summary for a clinician, then every saved meal grouped by day, on A4. */
fun DiaryReport.pdf(): ByteArray {
    // Footers say "Page n of N", so a first pass counts the pages.
    val (_, pages) = render(0)
    return render(pages).first
}

private fun DiaryReport.render(total: Int): Pair<ByteArray, Int> {
    val document = PdfDocument()
    var page: PdfDocument.Page? = null
    var pages = 0
    var y = MARGIN
    val fill = Paint(Paint.ANTI_ALIAS_FLAG)
    fun canvas(): Canvas = page!!.canvas

    fun draw(text: String, size: Float, weight: Int, color: Int, x: Float, top: Float, width: Float, alignRight: Boolean = false) {
        val paint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            textSize = size; this.color = color; typeface = Typeface.create(Typeface.DEFAULT, weight, false)
        }
        // drawText has no line breaks; a pasted multi-line meal name reads as one line.
        val shown = TextUtils.ellipsize(text.lines().joinToString(" "), paint, width, TextUtils.TruncateAt.END).toString()
        val left = if (alignRight) x + width - paint.measureText(shown) else x
        canvas().drawText(shown, left, top - paint.ascent(), paint)
    }
    fun rect(color: Int, left: Float, top: Float, width: Float, height: Float, radius: Float = 0f) {
        fill.color = color; fill.style = Paint.Style.FILL
        canvas().drawRoundRect(RectF(left, top, left + width, top + height), radius, radius, fill)
    }
    fun newPage() {
        page?.let(document::finishPage)
        pages += 1
        page = document.startPage(PdfDocument.PageInfo.Builder(PAGE_WIDTH.toInt(), PAGE_HEIGHT.toInt(), pages).create())
        y = MARGIN
        rect(RULE, MARGIN, PAGE_HEIGHT - 28, WIDTH, 0.5f)
        draw("Made with Mivu · values are logged estimates", 8f, 400, SECONDARY, MARGIN, PAGE_HEIGHT - 24, WIDTH / 2)
        draw("Page $pages of $total", 8f, 400, SECONDARY, MARGIN + WIDTH / 2, PAGE_HEIGHT - 24, WIDTH / 2, alignRight = true)
    }
    fun ensure(height: Float) { if (y + height > PAGE_HEIGHT - MARGIN) newPage() }
    /** Columns after the first are right-aligned numbers of equal width. */
    fun row(cells: List<String>, first: Float, colors: Map<Int, Int> = emptyMap(), header: Boolean = false) {
        ensure(16f)
        val rest = (WIDTH - first) / (cells.size - 1)
        cells.forEachIndexed { index, cell ->
            val x = if (index == 0) MARGIN else MARGIN + first + rest * (index - 1)
            draw(cell, if (header) 8.5f else 9.5f, if (header) 600 else 400, colors[index] ?: if (header) SECONDARY else INK,
                x, y, if (index == 0) first - 6 else rest, alignRight = index != 0)
        }
        y += 16
        rect(RULE, MARGIN, y - 3, WIDTH, 0.5f)
    }

    // Summary page
    newPage()
    draw("MIVU", 9f, 900, ACCENT, MARGIN, 44f, WIDTH - 90)
    draw("Food log", 22f, 700, INK, MARGIN, 58f, WIDTH - 90)
    draw("$profileName · $rangeTitle · prepared for your clinician", 10f, 400, SECONDARY, MARGIN, 90f, WIDTH - 90)
    rect(RULE, MARGIN, 116f, WIDTH, 0.75f)
    y = 136f

    val tileWidth = (WIDTH - 18) / 4
    summaryTiles.forEachIndexed { index, (title, value, detail) ->
        val left = MARGIN + index * (tileWidth + 6)
        rect(TILE, left, y, tileWidth, 58f, 8f)
        draw(title, 8.5f, 600, SECONDARY, left + 8, y + 7, tileWidth - 16)
        draw(value, 15f, 700, INK, left + 8, y + 20, tileWidth - 16)
        draw(detail, 8.5f, 400, SECONDARY, left + 8, y + 40, tileWidth - 16)
    }
    y += 70

    val trend = weights.filter { it.entry.unit == weights.first().entry.unit }
    if (trend.size > 1) {
        val low = trend.minOf { it.entry.value }
        val high = trend.maxOf { it.entry.value }
        draw("Weight trend (${trend[0].entry.unit})", 8.5f, 600, SECONDARY, MARGIN, y, WIDTH); y += 14
        rect(TILE, MARGIN, y, WIDTH, 56f, 8f)
        val plot = RectF(MARGIN + 10, y + 8, MARGIN + WIDTH - 10, y + 48)
        val start = trend[0].entry.measuredAt.toEpochMilli()
        val span = maxOf(trend.last().entry.measuredAt.toEpochMilli() - start, 1000L).toFloat()
        val path = Path()
        trend.forEachIndexed { index, weight ->
            val x = plot.left + plot.width() * (weight.entry.measuredAt.toEpochMilli() - start) / span
            val py = plot.bottom - plot.height() * (if (high == low) 0.5f else ((weight.entry.value - low) / (high - low)).toFloat())
            if (index == 0) path.moveTo(x, py) else path.lineTo(x, py)
        }
        fill.color = ACCENT; fill.style = Paint.Style.STROKE; fill.strokeWidth = 1.5f; fill.strokeJoin = Paint.Join.ROUND
        canvas().drawPath(path, fill)
        y += 68
    }

    draw("Daily totals", 12f, 600, INK, MARGIN, y, WIDTH); y += 20
    row(listOf("Day", "kcal", "Target", "Protein g", "Carbs g", "Fat g", "Weight"), 120f, header = true)
    for (day in days) {
        row(listOf(dayTitle(day.localDate), whole(day.totals.kcal), whole(day.target?.kcal), whole(day.totals.protein), whole(day.totals.carbs),
            whole(day.totals.fat), day.weight?.let { "${number(it.value)} ${it.unit}" } ?: "—"), 120f, if (day.isOver) mapOf(1 to OVER) else emptyMap())
    }
    y += 8
    draw("Red calories are above that day’s target. “—” means unknown.", 8f, 400, SECONDARY, MARGIN, y, WIDTH)

    // Meal pages
    newPage()
    draw("Meals", 16f, 700, INK, MARGIN, y, WIDTH); y += 28
    for (day in days.filter { it.meals.isNotEmpty() }) {
        ensure(40f); y += 6
        draw(dayTitle(day.localDate), 11f, 600, INK, MARGIN, y, WIDTH / 2)
        draw("${whole(day.totals.kcal)} kcal", 10f, 600, if (day.isOver) OVER else ACCENT, MARGIN + WIDTH / 2, y, WIDTH / 2, alignRight = true)
        y += 20
        row(listOf("Meal", "kcal", "Protein g", "Carbs g", "Fat g"), 275f, header = true)
        for (meal in day.meals) {
            row(listOf(listOf(meal.time, meal.name).filter { it.isNotEmpty() }.joinToString("  "), whole(meal.totals.kcal),
                whole(meal.totals.protein), whole(meal.totals.carbs), whole(meal.totals.fat)), 275f)
        }
    }
    if (days.all { it.meals.isEmpty() }) draw("No saved meals in this range.", 10f, 400, SECONDARY, MARGIN, y, WIDTH)

    page?.let(document::finishPage)
    val out = ByteArrayOutputStream()
    document.writeTo(out)
    document.close()
    return out.toByteArray() to pages
}

private val DiaryReport.Day.isOver get() = (totals.kcal ?: 0.0) > (target?.kcal ?: Double.POSITIVE_INFINITY)

private val DiaryReport.summaryTiles: List<Triple<String, String, String>>
    get() {
        fun average(values: List<Double>) = if (values.isEmpty()) null else values.average()
        val logged = days.filter { it.meals.isNotEmpty() }
        val target = days.lastOrNull()?.target
        val first = weights.firstOrNull()?.entry
        val last = weights.lastOrNull()?.entry
        val change = if (first != null && last != null && weights.size > 1 && first.unit == last.unit)
            "${if (last.value < first.value) "−" else "+"}${number(abs(last.value - first.value))} ${last.unit}" else "—"
        return listOf(
            Triple("Avg calories", whole(average(logged.mapNotNull { it.totals.kcal })), target?.kcal?.let { "target ${whole(it)}" } ?: "no target"),
            Triple("Avg protein", average(logged.mapNotNull { it.totals.protein })?.let { "${whole(it)} g" } ?: "—",
                target?.protein?.let { "target ${whole(it)} g" } ?: "no target"),
            Triple("Days logged", "${logged.size} / $calendarDayCount", "days with saved meals"),
            Triple("Weight change", change, if (first != null && last != null) "${number(first.value)} → ${number(last.value)}" else "no weigh-ins"),
        )
    }

private val DiaryReport.rangeTitle: String
    get() {
        val first = from ?: return "No days in range"
        val last = through ?: return "No days in range"
        return if (first == last) dayTitle(first) else "${dayTitle(first)} – ${dayTitle(last)}"
    }

private fun whole(value: Double?) = value?.let { NumberFormat.getIntegerInstance().format(it.roundToLong()) } ?: "—"

private fun dayTitle(localDate: String): String {
    val date = DiaryReport.date(localDate) ?: return localDate
    return DateTimeFormatter.ofPattern(DateFormat.getBestDateTimePattern(Locale.getDefault(), "EEEMMMdyyyy")).format(date)
}
