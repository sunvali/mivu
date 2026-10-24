package com.yakov103.mivu.ui.today

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.SizeTransform
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.yakov103.mivu.R
import com.yakov103.mivu.diary.DiaryMeal
import com.yakov103.mivu.ui.theme.MivuTheme
import java.util.UUID

private val Gutter = 16.dp
private val CardShape = RoundedCornerShape(24.dp)

/** Port of iOS TodayView in Material 3 Expressive direction B. The morning check-in and weight row arrive in milestone 6. */
@Composable
fun TodayScreen(
    viewModel: TodayViewModel,
    onOpenMeal: ((UUID) -> Unit)?,
    onLogWithPip: () -> Unit,
    onAddManually: (dayID: UUID?) -> Unit,
    onLogMeal: () -> Unit,
) {
    val snackbar = remember { SnackbarHostState() }
    LaunchedEffect(viewModel) { viewModel.messages.collect { snackbar.showSnackbar(it, withDismissAction = true) } }
    val loadFailed by viewModel.loadFailed.collectAsStateWithLifecycle()
    val state = viewModel.state.collectAsStateWithLifecycle().value
        ?: return Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { if (loadFailed) LoadFailure(viewModel::retry) }
    val list = rememberLazyListState()
    // The receipt and a read failure are inserted above the summary: bring them into view.
    LaunchedEffect(state.savedReceipt != null, loadFailed) { if (state.savedReceipt != null || loadFailed) list.animateScrollToItem(0) }
    Column(Modifier.fillMaxSize()) {
        Box(Modifier.weight(1f).fillMaxWidth()) {
            LazyColumn(
                Modifier.fillMaxSize(),
                state = list,
                contentPadding = PaddingValues(start = Gutter, end = Gutter, top = 4.dp, bottom = 16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                if (loadFailed) item(key = "loadFailed") { LoadFailure(viewModel::retry) }
                if (state.sampleMode) item(key = "sample") { SampleBanner() }
                state.savedReceipt?.let { id -> item(key = "receipt") { SavedReceipt(onOpenMeal?.let { { it(id) } }) } }
                item(key = "summary") { SummaryCard(state, viewModel::startNewDay) }
                item(key = "mealsHeader") {
                    Text("Meals", Modifier.padding(top = 12.dp).semantics { heading() },
                        style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                }
                if (state.meals.isEmpty()) item(key = "empty") { FirstMealCard() }
                items(state.meals, key = { it.id }) { meal -> MealCard(meal, viewModel::photoBytes, onOpenMeal) }
            }
            SnackbarHost(snackbar, Modifier.align(Alignment.BottomCenter).padding(horizontal = Gutter))
        }
        BottomActions(state.sampleMode, onLogWithPip, { onAddManually(state.activeDayID) }, onLogMeal)
    }
}

@Composable
private fun SummaryCard(state: TodayUiState, onStartNewDay: () -> Unit) {
    val large = isLargeText()
    Surface(Modifier.fillMaxWidth().testTag("todaySummary"), shape = RoundedCornerShape(28.dp), color = MivuTheme.colors.summarySurface) {
        Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            DayActions(state.displayDate, onStartNewDay)
            if (large) {
                Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) { Pip(144.dp) }
                Intake(state)
            } else {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    // 186 dp as iOS: taller pushes the first meal under the pinned actions.
                    Pip(186.dp)
                    Intake(state, Modifier.weight(1f))
                }
            }
            val macros = listOf(Triple("Protein", state.protein, MivuTheme.colors.protein),
                Triple("Carbs", state.carbs, MivuTheme.colors.carbs), Triple("Fat", state.fat, MivuTheme.colors.fat))
            if (large) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    macros.forEach { (title, value, color) -> MacroChip(title, value, color, Modifier.fillMaxWidth(), inline = true) }
                }
            } else {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    macros.forEach { (title, value, color) -> MacroChip(title, value, color, Modifier.weight(1f)) }
                }
            }
            if (state.unknownNote) {
                Text("Some nutrients are unknown. Recorded totals may be incomplete.",
                    style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            // shortcut: iOS offers "Set a goal" / "Edit goals" here when there is no kcal target; add it with the goal editor.
            state.goal?.let { Goal(it, large) }
        }
    }
}

@Composable
private fun DayActions(date: String, onStartNewDay: () -> Unit) {
    var open by rememberSaveable { mutableStateOf(false) }
    Box {
        Surface(
            onClick = { open = true },
            // One spoken element: the date is read once, inside the action's name.
            modifier = Modifier.testTag("todayDayActions").clearAndSetSemantics {
                contentDescription = "Day actions, $date"
                role = Role.Button
                onClick { open = true; true }
            },
            shape = RoundedCornerShape(12.dp),
            color = MaterialTheme.colorScheme.surface,
        ) {
            Row(Modifier.heightIn(min = 40.dp).padding(start = 14.dp, end = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(date, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Icon(painterResource(R.drawable.ic_arrow_drop_down), contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        DropdownMenu(open, onDismissRequest = { open = false }, shape = RoundedCornerShape(16.dp)) {
            DropdownMenuItem(
                text = { Text("Start new day") },
                onClick = { open = false; onStartNewDay() },
                leadingIcon = { Icon(painterResource(R.drawable.ic_wb_twilight), contentDescription = null) },
                modifier = Modifier.testTag("startNewDay"),
            )
        }
    }
}

/** Pip on the expressive cookie backdrop. Decorative, as iOS CompanionView. */
@Composable
private fun Pip(size: Dp) {
    Box(Modifier.size(size), contentAlignment = Alignment.Center) {
        Box(Modifier.matchParentSize().padding(size * 0.04f).background(MaterialTheme.colorScheme.primary.copy(alpha = 0.10f), CookieShape))
        Image(painterResource(R.drawable.pip_preview), contentDescription = null, Modifier.size(size * 0.86f))
    }
}

@Composable
private fun Intake(state: TodayUiState, modifier: Modifier = Modifier) {
    Column(modifier) {
        // The new total rolls in; Compose skips it when the system's animator scale is 0 ("Remove animations").
        AnimatedContent(
            state.kcal ?: "—",
            transitionSpec = {
                (slideInVertically { it / 2 } + fadeIn()) togetherWith (slideOutVertically { -it / 2 } + fadeOut()) using
                    SizeTransform(clip = false)
            },
            contentAlignment = Alignment.CenterStart,
            label = "kcal",
        ) { kcal ->
            Text(
                kcal,
                style = MaterialTheme.typography.displayMedium.tabular().copy(fontSize = 52.sp, lineHeight = 58.sp, letterSpacing = (-2).sp),
                fontWeight = FontWeight.Bold,
                maxLines = 1,
                softWrap = false,
                autoSize = TextAutoSize.StepBased(minFontSize = 39.sp, maxFontSize = 52.sp),
            )
        }
        Text("kcal recorded", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
        if (!state.hasDay) {
            Text("No meals recorded", Modifier.padding(top = 2.dp), style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun Goal(goal: GoalSummary, large: Boolean) {
    Column(Modifier.fillMaxWidth().testTag("todayGoalSummary"), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        val style = MaterialTheme.typography.bodyLarge.tabular()
        val target = @Composable { Text(goal.target, style = style, fontWeight = FontWeight.Medium) }
        val left = @Composable {
            Text(goal.remaining ?: "Not estimated yet", style = style,
                color = if (goal.remaining == null) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.onSurface)
        }
        if (large) {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) { target(); left() }
        } else {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                target(); Spacer(Modifier.weight(1f)); left()
            }
        }
        goal.progress?.let { fraction ->
            LinearProgressIndicator(
                progress = { fraction },
                modifier = Modifier.fillMaxWidth().semantics {
                    contentDescription = "Recorded intake toward your goal"
                    goal.progressValue?.let { stateDescription = it }
                },
                trackColor = MaterialTheme.colorScheme.surface,
            )
        }
        goal.exerciseAdjusted?.let {
            Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun FirstMealCard() {
    WhiteCard {
        Row(Modifier.padding(20.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            Icon(painterResource(R.drawable.ic_today), contentDescription = null, tint = MaterialTheme.colorScheme.primary)
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text("Your first meal starts here", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                Text("Add photos or a note.", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable
private fun MealCard(meal: DiaryMeal, loadPhoto: suspend (UUID, UUID) -> ByteArray?, onOpenMeal: ((UUID) -> Unit)?) {
    WhiteCard(Modifier.testTag("mealRow"), onClick = onOpenMeal?.let { { it(meal.id) } }) {
        MealRow(meal, loadPhoto, Modifier.padding(16.dp))
    }
}

/** iOS diarySummaryCard on Android: a white card with a hairline edge instead of a shadow. */
@Composable
internal fun WhiteCard(modifier: Modifier = Modifier, onClick: (() -> Unit)? = null, content: @Composable () -> Unit) {
    val m = modifier.fillMaxWidth().border(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f), CardShape)
    val color = MaterialTheme.colorScheme.surface
    if (onClick != null) Surface(onClick, m, shape = CardShape, color = color, content = content)
    else Surface(m, shape = CardShape, color = color, content = content)
}

@Composable
internal fun SampleBanner() {
    var expanded by rememberSaveable { mutableStateOf(false) }
    Surface(Modifier.fillMaxWidth(), shape = RoundedCornerShape(16.dp), color = MaterialTheme.colorScheme.surfaceContainer) {
        Column(Modifier.padding(horizontal = 12.dp)) {
            Row(
                Modifier.fillMaxWidth().heightIn(min = 48.dp)
                    .clickable(role = Role.Button) { expanded = !expanded }
                    .semantics { stateDescription = if (expanded) "Expanded" else "Collapsed" },
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Icon(painterResource(R.drawable.ic_eco), contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                Text("Apple sample mode", Modifier.weight(1f), style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                Icon(painterResource(R.drawable.ic_arrow_drop_down), contentDescription = null,
                    Modifier.rotate(if (expanded) 180f else 0f), tint = MaterialTheme.colorScheme.primary)
            }
            AnimatedVisibility(expanded) {
                Text("Every capture gets a synthetic apple estimate. Photos and text are saved, but no food recognition runs.",
                    Modifier.padding(bottom = 12.dp), style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

/** Opens the saved meal once meal detail exists; until then it is a plain status line, not a button. */
@Composable
private fun SavedReceipt(onOpen: (() -> Unit)?) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = 48.dp)
            .then(if (onOpen != null) Modifier.clickable(role = Role.Button, onClick = onOpen) else Modifier)
            .testTag("savedMealReceipt"),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Icon(painterResource(R.drawable.ic_check_circle), contentDescription = null, tint = MivuTheme.colors.success)
        Text("Saved on this phone", style = MaterialTheme.typography.bodyMedium, color = MivuTheme.colors.success)
    }
}

/** A failed read, worded as iOS's load failures; the diary itself is untouched. */
@Composable
private fun LoadFailure(onRetry: () -> Unit) {
    Column(
        Modifier.fillMaxWidth().padding(vertical = 8.dp).testTag("todayLoadFailed"),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text("Could not load today. Your diary is preserved.", Modifier.semantics { liveRegion = LiveRegionMode.Polite },
            style = MaterialTheme.typography.bodyLarge, textAlign = TextAlign.Center)
        FilledTonalButton(onRetry, Modifier.heightIn(min = 48.dp)) { Text("Try again") }
    }
}

/** Pinned above the navigation bar, as iOS safeAreaInset: Log with Pip and Add manually, or Log meal in sample mode. */
@Composable
private fun BottomActions(sampleMode: Boolean, onLogWithPip: () -> Unit, onAddManually: () -> Unit, onLogMeal: () -> Unit) {
    val large = isLargeText()
    Surface(color = MaterialTheme.colorScheme.background) {
        val buttons = @Composable { fill: Modifier ->
            if (sampleMode) {
                Button(onLogMeal, fill.testTag("logMeal").heightIn(min = 56.dp)) { ActionLabel(R.drawable.ic_add_circle, "Log meal") }
            } else {
                Button(onLogWithPip, fill.testTag("logMeal").heightIn(min = 56.dp)) { ActionLabel(R.drawable.ic_auto_awesome, "Log with Pip") }
                FilledTonalButton(onAddManually, fill.testTag("addManually").heightIn(min = 56.dp)) {
                    ActionLabel(R.drawable.ic_numbers, "Add manually")
                }
            }
        }
        val padding = Modifier.fillMaxWidth().padding(horizontal = Gutter, vertical = 12.dp)
        if (large) Column(padding, verticalArrangement = Arrangement.spacedBy(12.dp)) { buttons(Modifier.fillMaxWidth()) }
        else Row(padding, horizontalArrangement = Arrangement.spacedBy(12.dp)) { buttons(Modifier.weight(1f)) }
    }
}

@Composable
private fun RowScope.ActionLabel(icon: Int, text: String) {
    Icon(painterResource(icon), contentDescription = null, Modifier.size(20.dp))
    Spacer(Modifier.width(8.dp))
    Text(text, style = MaterialTheme.typography.titleMedium, maxLines = 2, overflow = TextOverflow.Ellipsis)
}
