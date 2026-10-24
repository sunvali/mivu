package com.yakov103.mivu.ui.diary

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.indication
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.material3.ripple
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.yakov103.mivu.diary.DayStatus
import com.yakov103.mivu.diary.DiaryDaySummary
import com.yakov103.mivu.ui.theme.MivuTheme
import com.yakov103.mivu.ui.today.tabular
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale
import java.util.UUID

/** iOS DayStatus colour: open is the accent, closed success, skipped secondary. */
internal val DayStatus.color: Color
    @Composable get() = when (this) {
        DayStatus.Open -> MaterialTheme.colorScheme.primary
        DayStatus.Closed -> MivuTheme.colors.success
        DayStatus.Skipped -> MaterialTheme.colorScheme.onSurfaceVariant
    }

/**
 * iOS DiaryWeekStrip: a pager of weeks, one pill per day. Swiping keeps the weekday and never moves past [today];
 * future days are disabled. [week] holds the selected week's summaries, null while it loads.
 */
@Composable
internal fun WeekStrip(
    selected: LocalDate,
    today: LocalDate,
    earliest: LocalDate?,
    firstDay: DayOfWeek,
    week: Map<LocalDate, DiaryDaySummary>?,
    activeDayID: UUID?,
    onSelect: (LocalDate) -> Unit,
) {
    val weeks = remember(earliest, selected, today, firstDay) { weekStarts(earliest, selected, today, firstDay) }
    val selectedWeek = weekDates(selected, firstDay).first()
    val pager = rememberPagerState(initialPage = weeks.indexOf(selectedWeek).coerceAtLeast(0)) { weeks.size }
    val current by rememberUpdatedState(Triple(weeks, selected, today))

    // A tap or the date picker moved the selection to another week: follow it. Compose skips the animation when the
    // system's animator scale is 0 ("Remove animations"), as iOS does under Reduce Motion.
    LaunchedEffect(selectedWeek, weeks) {
        val page = weeks.indexOf(selectedWeek)
        if (page >= 0 && page != pager.currentPage) pager.animateScrollToPage(page)
    }
    // A swipe settled on another week: move the selection by whole weeks. When the week list itself changes, the
    // settled index may still point into the old list until the pager re-keys it, so that emission is skipped.
    LaunchedEffect(pager) {
        var seen = current.first
        snapshotFlow { current.first to pager.settledPage }.collect { (weeks, page) ->
            if (weeks != seen) { seen = weeks; return@collect }
            val (_, selected, today) = current
            val from = weekDates(selected, firstDay).first()
            val to = weeks.getOrNull(page) ?: return@collect
            if (to != from) onSelect(shiftedSelection(selected, from, to, today))
        }
    }

    HorizontalPager(pager, Modifier.fillMaxWidth().testTag("diaryWeekStrip"), key = { weeks[it] }, verticalAlignment = Alignment.Top) { page ->
                // No gap between slots: each seventh is the touch target (48 dp at 360 dp wide); the capsule is inset inside it.
        Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp)) {
            weekDates(weeks[page], firstDay).forEach { date ->
                // Only the loaded week's summaries count: another week's dates show no dot until it loads.
                val summary = week?.takeIf { weeks[page] == selectedWeek }?.get(date)
                DayPill(date, summary, date == selected, date == today, date > today, activeDayID, { onSelect(date) }, Modifier.weight(1f))
            }
        }
    }
}

private val Capsule = RoundedCornerShape(percent = 50)
private val Letter = DateTimeFormatter.ofPattern("EEEEE", Locale.US)

@Composable
private fun DayPill(
    date: LocalDate,
    summary: DiaryDaySummary?,
    isSelected: Boolean,
    isToday: Boolean,
    isFuture: Boolean,
    activeDayID: UUID?,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val status = summary?.status(activeDayID)
    val label = pillLabel(date, summary, activeDayID)
    val content = if (isSelected) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurface
    val interaction = remember { MutableInteractionSource() }
    Box(
        modifier.alpha(if (isFuture) 0.35f else 1f)
            .clickable(interaction, indication = null, enabled = !isFuture, onClick = onClick)
            .testTag("diaryDayPill")
            .clearAndSetSemantics {
                contentDescription = label
                stateDescription = date.toString()
                selected = isSelected
                role = Role.Tab
                if (isFuture) disabled() else onClick { onClick(); true }
            }
            .padding(horizontal = 2.dp),
    ) {
        Column(
            Modifier.fillMaxWidth().clip(Capsule)
                .background(if (isSelected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surface)
                .indication(interaction, ripple())
                .heightIn(min = 64.dp).padding(vertical = 10.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(2.dp, Alignment.CenterVertically),
        ) {
            Text(date.format(Letter), style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold,
                color = if (isSelected) content else MaterialTheme.colorScheme.onSurfaceVariant)
            Text(date.dayOfMonth.toString(), style = MaterialTheme.typography.titleMedium.tabular(), fontWeight = FontWeight.SemiBold,
                color = if (!isSelected && isToday) MaterialTheme.colorScheme.primary else content)
            // The dot keeps its space so pills never change height; it is hidden on the selected pill, as iOS.
            Box(Modifier.size(6.dp).background(if (status == null || isSelected) Color.Transparent else status.color, CircleShape))
        }
    }
}
