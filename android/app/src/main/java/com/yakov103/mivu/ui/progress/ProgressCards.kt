package com.yakov103.mivu.ui.progress

import androidx.annotation.DrawableRes
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.yakov103.mivu.R
import com.yakov103.mivu.coach.CoachDailyProgress
import com.yakov103.mivu.progress.BurnProgress
import com.yakov103.mivu.progress.ProgressBand
import com.yakov103.mivu.progress.ProgressCalendarRow
import com.yakov103.mivu.progress.ProgressInsights
import com.yakov103.mivu.progress.ProgressSnapshot
import com.yakov103.mivu.progress.kcal
import com.yakov103.mivu.ui.theme.MivuTheme
import com.yakov103.mivu.ui.today.tabular
import java.text.NumberFormat
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.abs

// Ports of ios/Mivu/Progress/ProgressCards.swift (cards) and ProgressDetailViews.swift (rows), in the mockup's layout.

private val CardShape = RoundedCornerShape(24.dp)

/** iOS `diaryProgressCard`: a 24 dp card, white with a hairline edge or tinted; tappable when [onClick] is set. */
@Composable
internal fun ProgressCard(modifier: Modifier = Modifier, color: Color? = null, onClick: (() -> Unit)? = null, content: @Composable () -> Unit) {
    val fill = color ?: MaterialTheme.colorScheme.surface
    val m = modifier.fillMaxWidth().then(
        if (color == null) Modifier.border(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f), CardShape) else Modifier,
    )
    val inner: @Composable () -> Unit = { Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) { content() } }
    if (onClick != null) Surface(onClick, m, shape = CardShape, color = fill, content = inner) else Surface(m, shape = CardShape, color = fill, content = inner)
}

@Composable
internal fun SectionTitle(title: String, modifier: Modifier = Modifier) {
    Text(title, modifier.padding(top = 12.dp).semantics { heading() },
        style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
}

/** iOS `ProgressPlaceholder`: an accent icon and a muted line, 44 dp tall. */
@Composable
internal fun ProgressPlaceholder(@DrawableRes icon: Int, text: String) {
    Row(Modifier.fillMaxWidth().heightIn(min = 44.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Icon(painterResource(icon), contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(20.dp))
        Text(text, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/** iOS `ProgressGoalLine`: label left, gap right, one thin bar; one spoken element. */
@Composable
internal fun GoalLine(left: String, right: String, value: Double) {
    Column(Modifier.semantics(mergeDescendants = true) {}, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row {
            Text(left, Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium.tabular())
            Text(right, Modifier.padding(start = 12.dp), style = MaterialTheme.typography.bodyMedium.tabular(), color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        LinearProgressIndicator({ value.coerceIn(0.0, 1.0).toFloat() }, Modifier.fillMaxWidth(), strokeCap = StrokeCap.Round, gapSize = 0.dp,
            drawStopIndicator = {})
    }
}

private fun number(value: Double, digits: Int = 0) =
    NumberFormat.getNumberInstance(Locale.US).apply { minimumFractionDigits = digits; maximumFractionDigits = digits }.format(value)

/** The hero for a range, as iOS `ProgressHeadlineCard`: dates, Pip beside one plain verdict, then the bars and their key. */
@Composable
internal fun HeadlineCard(snapshot: ProgressSnapshot, dates: String, large: Boolean, onOpenDiary: () -> Unit, pip: @Composable () -> Unit) {
    ProgressCard(Modifier.testTag("progressHeadline"), color = MivuTheme.colors.summarySurface) {
        Text(dates, Modifier.testTag("progressDates"), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        val verdict: @Composable (Modifier) -> Unit = { m ->
            Column(m.semantics(mergeDescendants = true) {}, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(snapshot.headline.title, style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.primary)
                Text(snapshot.shortEvidence, style = MaterialTheme.typography.bodyMedium)
            }
        }
        if (large) {
            Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.CenterEnd) { pip() }
            verdict(Modifier)
        } else {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                verdict(Modifier.weight(1f))
                pip()
            }
        }
        if (snapshot.loggedDays == 0) {
            TextButton(onOpenDiary, Modifier.heightIn(min = 48.dp).testTag("openDiaryForCoverage")) {
                Icon(painterResource(R.drawable.ic_calendar), contentDescription = null)
                Text("Open Diary", Modifier.padding(start = 8.dp))
            }
        } else {
            BucketChart(snapshot.buckets, snapshot.range, "Calories by ${bucketUnit(snapshot.range)}", 112.dp,
                Modifier.testTag("nutritionChartSummary"), today = snapshot.days.lastOrNull()?.localDate?.let(LocalDate::parse))
            ChartLegend()
        }
        Text("Empty days aren't counted as zero.", Modifier.testTag("missingDayCopy"),
            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/** iOS `ProgressWeightCard`: one big trend number, a sparkline with no axes, and the distance to the goal weight. */
@Composable
internal fun WeightCard(snapshot: ProgressSnapshot, onClick: () -> Unit) {
    val trend = snapshot.trend
    ProgressCard(Modifier.testTag("openWeight"), onClick = onClick) {
        trend.lastOrNull()?.let { last ->
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Row(verticalAlignment = Alignment.Bottom) {
                    Text(oneDecimal(last.trend), style = MaterialTheme.typography.displayMedium.tabular().copy(fontSize = 40.sp, letterSpacing = (-1.5).sp),
                        fontWeight = FontWeight.Bold)
                    Text(" kg trend", Modifier.padding(bottom = 6.dp), style = MaterialTheme.typography.bodyMedium)
                }
                if (trend.size >= 2) TrendChart(trend.map { it.localDate to it.trend }, "Weight trend. ${weightSummary(trend)}", 56.dp,
                    Modifier.weight(1f).testTag("weightTrendSummary"), dots = false)
            }
            val goal = snapshot.goal?.goalWeightKg
            val start = snapshot.startKg
            if (goal != null && start != null) {
                val total = abs(start - goal); val left = abs(last.trend - goal)
                GoalLine("${oneDecimal(goal)} kg goal", if (left < 0.1) "At goal" else "${oneDecimal(left)} kg to go", if (total > 0) (total - left) / total else 1.0)
            } else {
                ProgressPlaceholder(R.drawable.ic_target, "Add a goal weight to see how far is left.")
            }
        }
        if (trend.size < 3) {
            val more = 3 - trend.size
            ProgressPlaceholder(R.drawable.ic_monitor_weight, "Weigh in on $more more ${if (more == 1) "day" else "days"} to see your trend.")
        }
    }
}

/**
 * The average day, as the mockup draws iOS `ProgressMacrosCard`: a donut of protein, carbs and fat energy with the
 * average kcal inside, each macro against its goal, then the energy goal line. Stacks at large text.
 */
@Composable
internal fun MacrosCard(snapshot: ProgressSnapshot, onClick: (() -> Unit)?, large: Boolean) {
    ProgressCard(Modifier.testTag("progressMacros"), onClick = onClick) {
        val average = snapshot.averageKcal
        if (average == null) {
            ProgressPlaceholder(R.drawable.ic_restaurant, "Log a full day to see your average day.")
        } else {
            val goal = snapshot.goal?.targets
            val rows: @Composable (Modifier) -> Unit = { m ->
                Column(m, verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    MacroRow("Protein", snapshot.averages.protein, goal?.protein, MivuTheme.colors.protein)
                    MacroRow("Carbs", snapshot.averages.carbs, goal?.carbs, MivuTheme.colors.carbs)
                    MacroRow("Fat", snapshot.averages.fat, goal?.fat, MivuTheme.colors.fat)
                }
            }
            val donut = @Composable {
                MacroDonut(snapshot.averages.protein, snapshot.averages.carbs, snapshot.averages.fat, average, 112.dp, Modifier.testTag("macroDonut"))
            }
            if (large) { donut(); rows(Modifier.fillMaxWidth()) }
            else Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(20.dp)) { donut(); rows(Modifier.weight(1f)) }
            Text("kcal on an average day · ${snapshot.judgedDays} logged ${if (snapshot.judgedDays == 1) "day" else "days"}",
                style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        val target = snapshot.target
        if (target != null && target > 0) {
            GoalLine("${kcal(target)} goal", average?.let { ProgressInsights.plainGap(it, target) } ?: "no full days yet", (average ?: 0.0) / target)
        } else {
            Text("No energy target set", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun MacroRow(title: String, grams: Double?, goal: Double?, color: Color) {
    Column(Modifier.semantics(mergeDescendants = true) {}, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(title, Modifier.weight(1f), style = MaterialTheme.typography.labelLarge, color = color, fontWeight = FontWeight.SemiBold)
            Text(listOfNotNull(grams?.let { number(it) } ?: "—", goal?.let { number(it) }).joinToString(" / ") + " g",
                style = MaterialTheme.typography.labelLarge.tabular())
        }
        if (goal != null && goal > 0) LinearProgressIndicator({ ((grams ?: 0.0) / goal).coerceIn(0.0, 1.0).toFloat() }, Modifier.fillMaxWidth(),
            color = color, trackColor = color.copy(alpha = 0.18f), strokeCap = StrokeCap.Round, gapSize = 0.dp, drawStopIndicator = {})
    }
}

/** One "More" row, 52 dp tall: icon, title, value, chevron; spoken as one button. */
@Composable
internal fun MoreRow(tag: String, @DrawableRes icon: Int, title: String, value: String, onClick: () -> Unit) {
    Surface(onClick, Modifier.fillMaxWidth().testTag(tag), color = Color.Transparent) {
        Row(Modifier.heightIn(min = 52.dp).padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Icon(painterResource(icon), contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.width(24.dp))
            Text(title, style = MaterialTheme.typography.bodyLarge)
            Text(value, Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = if (LocalDensity.current.fontScale >= 1.5f) 2 else 1, overflow = TextOverflow.Ellipsis,
                textAlign = androidx.compose.ui.text.style.TextAlign.End)
            Icon(painterResource(R.drawable.ic_chevron_right), contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
internal fun MoreDivider() = HorizontalDivider(Modifier.padding(start = 52.dp), color = MaterialTheme.colorScheme.outlineVariant)

/** iOS `ProgressCaloriesCard`, full width on its detail screen; a tap selects a bar. */
@Composable
internal fun CaloriesCard(snapshot: ProgressSnapshot, selected: Int?, onSelect: (Int) -> Unit) {
    ProgressCard {
        Row {
            Text("Calories vs target", Modifier.weight(1f), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            Text(snapshot.range.title, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Text(listOfNotNull(snapshot.averageKcal?.let { "Average ${kcal(it)}" }, snapshot.target?.let { "target ${kcal(it)}" } ?: "No energy target set")
            .joinToString(" · "), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        if (snapshot.loggedDays == 0) {
            ProgressPlaceholder(R.drawable.ic_progress, "Log a meal to see your calories against your target.")
        } else {
            BucketChart(snapshot.buckets, snapshot.range, "Calories vs target", 180.dp, Modifier.testTag("nutritionChartSummary"),
                today = snapshot.days.lastOrNull()?.localDate?.let(LocalDate::parse), selected = selected, onSelect = onSelect)
            ChartLegend()
            selected?.let { snapshot.buckets.getOrNull(it) }?.let {
                Text("Selected ${bucketValue(it, snapshot.range)}", Modifier.testTag("selectedBucket"), style = MaterialTheme.typography.bodyMedium)
            }
        }
    }
}

/** iOS `ProgressBurnCard`: the estimate with its likely band, or what is still needed. */
@Composable
internal fun BurnCard(snapshot: ProgressSnapshot) {
    val success = MivuTheme.colors.success
    ProgressCard(Modifier.semantics(mergeDescendants = true) {}, color = MivuTheme.colors.tintBurn) {
        Text("Estimated burn", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, color = success)
        when (val burn = snapshot.burn) {
            is BurnProgress.Estimate -> {
                val e = burn.estimate
                Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("~" + number(e.kcalPerDay), style = MaterialTheme.typography.displaySmall.tabular(), fontWeight = FontWeight.SemiBold, color = success)
                    Text("kcal a day", Modifier.padding(bottom = 4.dp), style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                // Band runs 100–400 kcal; wider uncertainty draws a wider band.
                val share = (0.2 + 0.7 * minOf(1.0, e.band / 400)).toFloat()
                Box(Modifier.fillMaxWidth().heightIn(min = 12.dp).clearAndSetSemantics {}, contentAlignment = Alignment.Center) {
                    Surface(Modifier.fillMaxWidth().heightIn(min = 12.dp), shape = RoundedCornerShape(6.dp), color = success.copy(alpha = 0.15f)) {}
                    Surface(Modifier.fillMaxWidth(share).heightIn(min = 12.dp), shape = RoundedCornerShape(6.dp), color = success.copy(alpha = 0.35f)) {}
                    Surface(Modifier.size(12.dp), shape = RoundedCornerShape(6.dp), color = success) {}
                }
                Text("Likely between ${kcal(e.kcalPerDay - e.band)} and ${kcal(e.kcalPerDay + e.band)}. From your intake and weight trend; it firms up as you log.",
                    style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            is BurnProgress.Needs -> ProgressPlaceholder(R.drawable.ic_whatshot, listOfNotNull(
                if (burn.days > 0) "Log ${burn.days} more complete ${if (burn.days == 1) "day" else "days"}" else null,
                if (burn.weighIns > 0) "weigh in ${burn.weighIns} more ${if (burn.weighIns == 1) "time" else "times"}" else null,
            ).joinToString(" and ") + " to see your burn.")
        }
    }
}

/** iOS `ProgressDayRow`: a band swatch, the title and its value; the band is spoken after them. */
@Composable
internal fun DayRow(title: String, value: String, band: ProgressBand? = null) {
    val swatch = bandColor(band) ?: MaterialTheme.colorScheme.outlineVariant
    Row(
        Modifier.fillMaxWidth().heightIn(min = 48.dp).testTag("progressDayRow").semantics(mergeDescendants = true) {
            band?.let { stateDescription = it.title }
        },
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Surface(Modifier.size(10.dp), shape = RoundedCornerShape(3.dp), color = swatch) {}
        Text(title, Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
        Text(value, style = MaterialTheme.typography.bodyMedium.tabular(), color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

internal fun dayTitle(day: CoachDailyProgress): String =
    runCatching { LocalDate.parse(day.localDate).format(DateTimeFormatter.ofPattern("EEE d MMM", Locale.US)) }.getOrDefault(day.localDate)

/** iOS `ProgressCalendarRow`: a week of seven dots (Week, Month) or a month's logged share (3M, Year); one spoken line. */
@Composable
internal fun CalendarRowView(row: ProgressCalendarRow) {
    Column(
        Modifier.fillMaxWidth().padding(vertical = 6.dp).testTag("progressCalendarRow")
            .clearAndSetSemantics { contentDescription = "${row.title}, ${row.logged} of ${row.total} logged" },
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Row {
            Text(row.title, Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
            Text("${row.logged} of ${row.total} logged", style = MaterialTheme.typography.bodyMedium.tabular(), color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        val dots = row.dots
        if (dots != null) CalendarDots(dots)
        else LinearProgressIndicator({ row.logged.toFloat() / maxOf(row.total, 1) }, Modifier.fillMaxWidth(), strokeCap = StrokeCap.Round,
            gapSize = 0.dp, drawStopIndicator = {})
    }
}
