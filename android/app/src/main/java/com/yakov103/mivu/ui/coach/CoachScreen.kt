package com.yakov103.mivu.ui.coach

import com.yakov103.mivu.connection.ConnectionState
import com.yakov103.mivu.diary.CoachDestination
import android.animation.ValueAnimator
import android.content.pm.PackageManager
import androidx.compose.foundation.layout.imePadding
import androidx.compose.runtime.DisposableEffect
import androidx.compose.ui.focus.FocusRequester
import com.yakov103.mivu.pip.MotionPolicy.Playback
import com.yakov103.mivu.pip.rememberMotionPlayback
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.ScrollableDefaults
import androidx.compose.foundation.gestures.scrollable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.isTraversalGroup
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.traversalIndex
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.yakov103.mivu.R
import com.yakov103.mivu.ui.coach.CoachHistoryWindow.Direction
import com.yakov103.mivu.ui.coach.CoachHistoryWindow.EdgeState
import com.yakov103.mivu.diary.CoachReply
import com.yakov103.mivu.ui.today.MorningCheckInCard
import com.yakov103.mivu.ui.today.TodayViewModel
import java.util.UUID
import kotlinx.coroutines.launch

// Port of the iOS Coach tab's timeline (ios/Mivu/Coach/CoachView.swift and CoachTimelineView.swift) as a reversed
// LazyColumn: index 0 is the newest exchange, at the bottom. The composer and Pip dock below the timeline box.

private data class Viewport(val visible: Set<UUID>, val first: Int, val last: Int, val atLatest: Boolean)

@Composable
fun CoachScreen(
    model: CoachViewModel,
    onOpenMeal: (UUID) -> Unit,
    onSeeToday: () -> Unit,
    onSeeProgress: () -> Unit,
    /** Focus the field once, as after "Log with Pip" or an Ask Pip quote; [onFocusConsumed] clears the request. */
    focusRequested: Boolean = false,
    onFocusConsumed: () -> Unit = {},
    /** The field's camera: opens the in-app camera, which also offers the Photo Picker; a path retakes that draft photo. */
    onOpenCamera: (String?) -> Unit = {},
    hasCamera: Boolean = LocalContext.current.packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY),
    /** The footnote's "Connect ChatGPT for replies": sharing consent first ([onAgree]), then sign-in ([onConnect]). */
    connection: ConnectionState = ConnectionState(),
    onAgree: () -> Unit = {},
    onConnect: () -> Unit = {},
    /** A receipt's handoff links: the Coach AI screen and Settings. */
    onOpenConnection: () -> Unit = {},
    onOpenSettings: () -> Unit = {},
    /** Today's model, for the morning weigh-in bubble; dismissal and skip are shared with Today. */
    checkIn: TodayViewModel? = null,
) {
    val state by model.timeline.collectAsStateWithLifecycle()
    val activity by model.activity.collectAsStateWithLifecycle()
    val undoing by model.undoing.collectAsStateWithLifecycle()
    val listState = rememberLazyListState()
    val twoDp = with(LocalDensity.current) { 2.dp.toPx() }
    fun LazyListState.atLatest() = firstVisibleItemIndex == 0 && firstVisibleItemScrollOffset < twoDp
    val atLatest by remember { derivedStateOf { listState.atLatest() } }
    val rows = state.exchanges.asReversed()
    val focusRequester = remember { FocusRequester() }
    val actions = remember(model, onOpenMeal, onSeeToday, onSeeProgress, onOpenConnection, onOpenSettings) {
        CoachRowActions(model::undo, onOpenMeal, { model.retry(it) }, { id, previous -> model.chooseDay(id, previous) }, model::answer,
            model::finishRest, onSeeToday, onSeeProgress, model::turnPhoto, model::mealPhoto,
            // As iOS reply(to:), typing follows the quote.
            reply = { turn, fromPip -> model.replyTo(turn, fromPip); focusRequester.requestFocus() },
            openQuote = { reply -> openQuote(reply, model, onOpenMeal) },
            openDestination = { if (it == CoachDestination.connection) onOpenConnection() else onOpenSettings() },
        )
    }

    // A new newest row is followed only when the reader sat at the newest one before it arrived (read before layout).
    val newest = state.exchanges.lastOrNull()?.turn?.id
    val following = remember(newest) { listState.atLatest() }
    LaunchedEffect(newest) { if (following && state.highlighted == null) listState.scrollToItem(0) }

    // A seek lands on its highlighted exchange.
    LaunchedEffect(state.highlighted, rows.firstOrNull()?.turn?.id) {
        val index = rows.indexOfFirst { it.turn.id == state.highlighted }
        if (index >= 0) listState.scrollToItem(index)
    }

    // Report what is visible, and page when the reader nears an edge that can grow.
    LaunchedEffect(listState, state.earlier, state.later, rows.size) {
        snapshotFlow {
            val info = listState.layoutInfo.visibleItemsInfo
            Viewport(info.mapNotNull { it.key as? UUID }.toSet(), listState.firstVisibleItemIndex, info.lastOrNull()?.index ?: -1, listState.atLatest())
        }.collect { v ->
            model.viewport(v.visible, v.atLatest)
            if (rows.isEmpty() || model.awaitingHighlight) return@collect // a seek scrolls to its row before paging
            if (state.earlier == EdgeState.Available && v.last >= rows.lastIndex - 3) model.loadEarlier(v.visible)
            if (state.later == EdgeState.Available && v.first <= 3) model.loadLater(v.visible)
        }
    }
    val visible = { listState.layoutInfo.visibleItemsInfo.mapNotNull { it.key as? UUID }.toSet() }

    // Pip goes still off screen; the camera is a dialog destination, so Coach is no longer resumed and Pip hides.
    val playback = rememberMotionPlayback()
    LaunchedEffect(playback) { model.reportPlayback(playback) }
    DisposableEffect(model) { onDispose { model.reportPlayback(Playback.Hidden) } } // the model outlives the tab
    LaunchedEffect(focusRequested) {
        if (focusRequested) { focusRequester.requestFocus(); onFocusConsumed() }
    }

    Column(Modifier.fillMaxSize()) {
        Box(Modifier.weight(1f).fillMaxWidth().semantics { isTraversalGroup = true }) {
            LazyColumn(
                Modifier.fillMaxSize().testTag("coachTimeline").semantics { traversalIndex = 0f },
                state = listState, reverseLayout = true, contentPadding = PaddingValues(vertical = 8.dp),
            ) {
                items(rows, key = { it.turn.id }) { exchange ->
                    CoachExchangeRow(exchange, isLatest = exchange.turn.id == state.latestID,
                        activity = activity?.takeIf { it.first == exchange.turn.id }?.second, days = state.days, actions = actions, undoing = undoing,
                        highlighted = exchange.turn.id == state.highlighted)
                }
            }
            when {
                !state.loaded -> Loading(Modifier.align(Alignment.Center))
                state.error != null -> Column(Modifier.align(Alignment.Center).padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(state.error!!, color = MaterialTheme.colorScheme.error, textAlign = TextAlign.Center)
                    TextButton({ model.jumpToLatest() }, Modifier.heightIn(min = 48.dp)) { Text("Try again") }
                }
                rows.isEmpty() -> EmptyState(Modifier.align(Alignment.Center))
            }
            Edge(Direction.earlier, state.earlier, Modifier.align(Alignment.TopCenter)) { model.loadEarlier(visible()) }
            Edge(Direction.later, state.later, Modifier.align(Alignment.BottomCenter)) { model.loadLater(visible()) }
            if (rows.isNotEmpty() && (!atLatest || state.later != EdgeState.Exhausted)) JumpToLatest(listState) {
                if (state.later != EdgeState.Exhausted) model.jumpToLatest().join()
                if (ValueAnimator.areAnimatorsEnabled()) listState.animateScrollToItem(0) else listState.scrollToItem(0)
            }
        }
        // Failures show in the composer caption beside Pip.
        CoachComposer(model, showStarters = state.loaded && state.error == null && rows.isEmpty(), focusRequester,
            onOpenCamera = onOpenCamera, hasCamera = hasCamera, modifier = Modifier.imePadding(),
            connection = connection, onAgree = onAgree, onConnect = onConnect,
            bubble = checkIn?.let { today -> { WeighInBubble(today) { model.updateText("My weight this morning is "); focusRequester.requestFocus() } } })
    }
}

/** iOS CoachView's compact MorningCheckInCard: asked only while today has no weight and was not skipped. */
@Composable
private fun WeighInBubble(today: TodayViewModel, onTellCoach: () -> Unit) {
    val morning = today.state.collectAsStateWithLifecycle().value?.morning ?: return
    val unit by today.weightUnit.collectAsStateWithLifecycle()
    MorningCheckInCard(morning, unit, today::setWeightUnit, today::saveMorningWeight, today::skipMorningWeight, today::dismissMorning,
        compact = true, onTellCoach = onTellCoach)
}

/** iOS openQuote: a message or day seeks the conversation; a meal or food opens the meal. */
private fun openQuote(reply: CoachReply, model: CoachViewModel, onOpenMeal: (UUID) -> Unit) {
    when (val target = reply.target) {
        is CoachReply.Target.Message -> model.seek(CoachSeekTarget.Turn(target.turnID))
        is CoachReply.Target.Day -> model.seek(CoachSeekTarget.Day(target.dayID))
        is CoachReply.Target.Meal -> onOpenMeal(target.mealID)
        is CoachReply.Target.Item -> onOpenMeal(target.mealID)
        // shortcut: Android has no workout detail yet, so a workout quote does nothing; open it once that screen exists.
        is CoachReply.Target.Workout -> Unit
        is CoachReply.Target.Weight -> Unit // rendered without an action
    }
}

/**
 * AGENTS.md Jump to latest: a 48 dp circle with the spoken label, read after the timeline, never taking focus. A drag that
 * starts on it scrolls the timeline, in the list's own direction.
 */
@Composable
private fun BoxScope.JumpToLatest(listState: LazyListState, jump: suspend () -> Unit) {
    val scope = rememberCoroutineScope()
    // The list's own gesture direction, so the content follows the finger as it does on the list.
    val reverse = ScrollableDefaults.reverseDirection(LocalLayoutDirection.current, Orientation.Vertical, reverseScrolling = true)
    FilledTonalIconButton(
        onClick = { scope.launch { jump() } },
        modifier = Modifier.align(Alignment.BottomEnd).padding(16.dp).size(48.dp)
            .scrollable(listState, Orientation.Vertical, reverseDirection = reverse)
            .semantics { traversalIndex = 1f },
        shape = CircleShape,
    ) {
        Icon(painterResource(R.drawable.ic_arrow_downward), contentDescription = "Jump to latest")
    }
}

@Composable
private fun Edge(direction: Direction, edge: EdgeState, modifier: Modifier, retry: () -> Unit) {
    val earlier = direction == Direction.earlier
    when (edge) {
        EdgeState.Loading -> Surface(modifier.padding(8.dp), shape = CircleShape, color = MaterialTheme.colorScheme.surfaceContainerHigh) {
            Row(Modifier.padding(horizontal = 12.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                Text(if (earlier) "Loading earlier messages" else "Loading later messages", style = MaterialTheme.typography.bodyMedium)
            }
        }
        is EdgeState.Failed -> FilledTonalButton(retry, modifier.padding(8.dp).heightIn(min = 48.dp)) {
            Text(if (earlier) "Retry earlier messages" else "Retry later messages")
        }
        EdgeState.Available, EdgeState.Exhausted -> Unit
    }
}

@Composable
private fun Loading(modifier: Modifier) = CircularProgressIndicator(modifier)

/** iOS ContentUnavailableView for an empty conversation. */
@Composable
private fun EmptyState(modifier: Modifier) {
    Column(modifier.padding(horizontal = 32.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Icon(painterResource(R.drawable.ic_coach), null, Modifier.size(56.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Text("What would you like to record?", Modifier.semantics { heading() }, style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.Bold, textAlign = TextAlign.Center)
        Text("Describe a meal, add a photo, or record a weigh-in or workout. You can review and correct every estimate. Coach gives " +
            "estimates, not medical advice.", style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center)
    }
}
