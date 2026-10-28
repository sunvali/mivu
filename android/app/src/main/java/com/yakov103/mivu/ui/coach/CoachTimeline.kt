package com.yakov103.mivu.ui.coach

import android.animation.ValueAnimator
import android.util.LruCache
import android.content.ClipData
import android.os.Build
import android.widget.Toast
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.spring
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.drag
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.systemGestures
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.platform.ClipEntry
import androidx.compose.ui.platform.LocalClipboard
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.unit.IntOffset
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlinx.coroutines.launch
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AssistChip
import androidx.compose.material3.AssistChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Alignment
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.yakov103.mivu.R
import com.yakov103.mivu.coach.CoachActivity
import com.yakov103.mivu.coach.CoachReplyLines
import com.yakov103.mivu.connection.CoachProvider
import com.yakov103.mivu.diary.CoachExchange
import com.yakov103.mivu.diary.CoachDestination
import com.yakov103.mivu.diary.CoachReceiptTarget
import com.yakov103.mivu.diary.CoachTurn
import com.yakov103.mivu.diary.CoachTurnState
import com.yakov103.mivu.diary.diaryDateLabel
import com.yakov103.mivu.ui.theme.MivuTheme
import com.yakov103.mivu.ui.today.decode
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withContext

// Port of the iOS Coach exchange row: CoachView.inputBubble and turnActions (ios/Mivu/Coach/CoachView.swift:596-704) and
// CoachActivityView. Every string is the iOS one, with "iPhone" as "phone".

/** What an exchange row can do; the screen binds these to the view model and navigation. */
class CoachRowActions(
    val undo: (String) -> Unit,
    val openMeal: (UUID) -> Unit,
    val retry: (UUID) -> Unit,
    val chooseDay: (UUID, Boolean) -> Unit,
    val answer: (com.yakov103.mivu.diary.CoachReply.Target, String, String) -> Unit,
    val finishRest: (UUID) -> Unit,
    val seeToday: () -> Unit,
    val seeProgress: () -> Unit,
    val turnPhoto: suspend (UUID, UUID) -> ByteArray?,
    val mealPhoto: suspend (UUID, UUID) -> ByteArray?,
    /** Quotes the person's message, or Pip's reply when true, in the composer. */
    val reply: (CoachTurn, Boolean) -> Unit = { _, _ -> },
    /** A sent quote's target: the original message, day or record. */
    val openQuote: (com.yakov103.mivu.diary.CoachReply) -> Unit = {},
    /** A receipt's handoff link: only Settings and the ChatGPT connection exist on Android. */
    val openDestination: (CoachDestination) -> Unit = {},
)

/** One exchange: the person's message on the right, then Pip's reply, status, receipts and the latest exchange's choices. */
@Composable
fun CoachExchangeRow(
    exchange: CoachExchange,
    isLatest: Boolean,
    activity: CoachActivity?,
    days: Map<UUID, String>,
    actions: CoachRowActions,
    undoing: Set<String> = emptySet(),
    highlighted: Boolean = false,
    provider: CoachProvider = CoachProvider.chatGPT,
    modifier: Modifier = Modifier,
) {
    val turn = exchange.turn
    // iOS isHighlighted: an accent ring around the exchange a seek opened at, announced as the selected source.
    val ring = if (highlighted) Modifier.padding(horizontal = 8.dp, vertical = 4.dp)
        .border(2.dp, MaterialTheme.colorScheme.primary, RoundedCornerShape(12.dp))
        .semantics { stateDescription = "Selected source message" } else Modifier
    SwipeToReply({ actions.reply(turn, !turn.assistantText.isNullOrBlank()) }, modifier) { swipe ->
        Column(swipe.fillMaxWidth().then(ring).padding(horizontal = if (highlighted) 8.dp else 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)) {
            InputBubble(turn, actions.turnPhoto, actions.openQuote) { actions.reply(turn, false) }
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                turn.assistantText?.let { reply ->
                    val text = coachReplyText(reply)
                    var reporting by rememberSaveable { mutableStateOf(false) }
                    MessageActions(text.text, { actions.reply(turn, true) }, onReport = { reporting = true }) {
                        Text(text, it, style = MaterialTheme.typography.bodyLarge)
                    }
                    if (reporting) ReportReplyDialog(turn.id, text.text) { reporting = false }
                }
                val question = turn.question
                if (isLatest && question != null && question.candidates.isNotEmpty()) {
                    CoachQuestionChips(question, exchange.questionMeals, enabled = true, loadPhoto = actions.mealPhoto, onPick = actions.answer)
                }
                if (turn.state != CoachTurnState.completed) {
                    if (activity != null && turn.receipts.isEmpty()) ActivityRow(activity) else Status(turn, provider)
                    TurnChoices(turn, days, actions)
                }
                exchange.receipts.filter { it.mealID != null || it.workoutID != null }.forEach { receipt ->
                    CoachReceiptCard(receipt, exchange.targets[receipt.operationKey] ?: CoachReceiptTarget.Loading, exchange.undo[receipt.operationKey],
                        undoing = receipt.operationKey in undoing, onUndo = { actions.undo(receipt.operationKey) }, onOpen = { receipt.mealID?.let(actions.openMeal) })
                }
                exchange.receipts.filter { it.weightID != null }.forEach { receipt ->
                    CoachReceiptPresentation(receipt, CoachReceiptTarget.Loading).weightLabel?.let { WeightChip(it) }
                }
                // iOS turnActions: one link per handoff destination, in CoachDestination order.
                LINKS.filterKeys { d -> exchange.receipts.any { it.destination == d } }.forEach { (destination, title) ->
                    TextButton({ actions.openDestination(destination) }, Modifier.heightIn(min = 48.dp)) { Text(title) }
                }
                if (isLatest) {
                    val followUps = CoachReplyLines.followUps(turn)
                    if (followUps.isNotEmpty()) Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        followUps.forEach { followUp ->
                            val today = followUp == CoachReplyLines.FollowUp.today
                            AssistChip(onClick = if (today) actions.seeToday else actions.seeProgress,
                                label = { Text(if (today) "See today" else "See progress") },
                                leadingIcon = { Icon(painterResource(if (today) R.drawable.ic_today else R.drawable.ic_progress), null,
                                    Modifier.size(AssistChipDefaults.IconSize)) })
                        }
                    }
                }
                if (turn.incomplete == true) {
                    Text("Couldn't finish the rest", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    TextButton({ actions.finishRest(turn.id) }, Modifier.heightIn(min = 48.dp)) { Text("Retry") }
                }
            }
        }
    }
}

private val REPLY_THRESHOLD = 64.dp

/**
 * iOS replyPan: a rightward drag on the row follows the finger up to 64 dp, then at 0.15× past it; the reply arrow fades in,
 * crossing the threshold ticks once, and a release past it replies. Only a mostly horizontal drag (x > 2|y|) is claimed, so
 * the list keeps vertical scrolling, and a drag from the system back-gesture edge is left to the system.
 */
@Composable
private fun SwipeToReply(onReply: () -> Unit, modifier: Modifier, content: @Composable (Modifier) -> Unit) {
    val offset = remember { Animatable(0f) }
    var arrowY by remember { mutableFloatStateOf(0f) }
    val scope = rememberCoroutineScope()
    val haptic = LocalHapticFeedback.current
    val reply by rememberUpdatedState(onReply)
    val edge = WindowInsets.systemGestures.getLeft(LocalDensity.current, LocalLayoutDirection.current)
    Box(modifier.fillMaxWidth().pointerInput(edge) {
        val threshold = REPLY_THRESHOLD.toPx()
        awaitEachGesture {
            val down = awaitFirstDown(requireUnconsumed = false)
            if (down.position.x < edge) return@awaitEachGesture
            var total = Offset.Zero
            while (total.getDistance() <= viewConfiguration.touchSlop) {
                val change = awaitPointerEvent().changes.firstOrNull { it.id == down.id }
                if (change == null || !change.pressed || change.isConsumed) return@awaitEachGesture
                total += change.positionChange()
            }
            if (total.x <= 0 || total.x <= abs(total.y) * 2) return@awaitEachGesture
            arrowY = down.position.y
            var x = total.x
            var armed = false
            val ended = drag(down.id) { change ->
                x = max(0f, x + change.positionChange().x)
                change.consume()
                scope.launch { offset.snapTo(min(x, threshold) + max(0f, x - threshold) * 0.15f) }
                if ((x >= threshold) != armed) {
                    armed = !armed
                    if (armed) haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                }
            }
            if (ended && armed) reply()
            scope.launch { if (ValueAnimator.areAnimatorsEnabled()) offset.animateTo(0f, spring(dampingRatio = 0.6f)) else offset.snapTo(0f) }
        }
    }) {
        Icon(painterResource(R.drawable.ic_reply), null, Modifier
            .offset { IntOffset(16.dp.roundToPx(), (arrowY - 12.dp.toPx()).roundToInt()) }
            .graphicsLayer { alpha = (offset.value / REPLY_THRESHOLD.toPx()).coerceIn(0f, 1f) },
            tint = MaterialTheme.colorScheme.onSurfaceVariant)
        content(Modifier.offset { IntOffset(offset.value.roundToInt(), 0) })
    }
}

/**
 * iOS messageActions: a long press opens Reply and Copy (Copy only when there is text), and Report reply when [onReport]
 * is given (Pip's replies only); TalkBack gets the same custom actions. Copy goes to the clipboard; Android 13+ confirms
 * it itself, so only older versions show a toast.
 */
@Composable
private fun MessageActions(text: String, onReply: () -> Unit, onReport: (() -> Unit)? = null, content: @Composable (Modifier) -> Unit) {
    var open by remember { mutableStateOf(false) }
    val clipboard = LocalClipboard.current
    val context = LocalContext.current
    val haptic = LocalHapticFeedback.current
    val scope = rememberCoroutineScope()
    val copy = {
        scope.launch { clipboard.setClipEntry(ClipEntry(ClipData.newPlainText("Coach message", text))) }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) Toast.makeText(context, "Copied", Toast.LENGTH_SHORT).show()
    }
    Box {
        content(Modifier
            .pointerInput(Unit) { detectTapGestures(onLongPress = { haptic.performHapticFeedback(HapticFeedbackType.LongPress); open = true }) }
            .semantics {
                customActions = listOfNotNull(CustomAccessibilityAction("Reply") { onReply(); true },
                    text.takeIf { it.isNotEmpty() }?.let { CustomAccessibilityAction("Copy") { copy(); true } },
                    onReport?.let { CustomAccessibilityAction("Report reply") { it(); true } })
            })
        DropdownMenu(open, { open = false }) {
            DropdownMenuItem({ Text("Reply") }, { open = false; onReply() }, leadingIcon = { Icon(painterResource(R.drawable.ic_reply), null) })
            if (text.isNotEmpty()) DropdownMenuItem({ Text("Copy") }, { open = false; copy() },
                leadingIcon = { Icon(painterResource(R.drawable.ic_copy), null) })
            if (onReport != null) DropdownMenuItem({ Text("Report reply") }, { open = false; onReport() },
                leadingIcon = { Icon(painterResource(R.drawable.ic_flag), null) })
        }
    }
}

@Composable
private fun InputBubble(turn: CoachTurn, loadPhoto: suspend (UUID, UUID) -> ByteArray?, openQuote: (com.yakov103.mivu.diary.CoachReply) -> Unit,
    onReply: () -> Unit) {
    Column(Modifier.fillMaxWidth().padding(start = 48.dp), horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        MessageActions(turn.text, onReply) { actions ->
            Surface(actions, shape = RoundedCornerShape(20.dp), color = MaterialTheme.colorScheme.primary) {
                Column(Modifier.padding(horizontal = 16.dp, vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    turn.submissionManifest?.reply?.let { reply ->
                        CoachSentQuote(reply, if (reply.target is com.yakov103.mivu.diary.CoachReply.Target.Weight) null else ({ openQuote(reply) }))
                    }
                    if (turn.photoIDs.isNotEmpty()) {
                        Text(if (turn.photoIDs.size == 1) "1 photo" else "${turn.photoIDs.size} photos", style = MaterialTheme.typography.labelMedium)
                        FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            turn.photoIDs.forEach { id -> CoachPhoto(id, 120.dp) { loadPhoto(turn.id, id) } }
                        }
                    }
                    if (turn.text.isNotEmpty()) Text(turn.text, style = MaterialTheme.typography.bodyLarge)
                }
            }
        }
        // A reply or card already shows the message landed; the save note matters only until then.
        if (turn.state != CoachTurnState.completed) Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            Icon(painterResource(R.drawable.ic_check_circle), null, Modifier.size(14.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
            Text("Saved on this phone", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun Status(turn: CoachTurn, provider: CoachProvider) {
    val color = when (turn.state) {
        CoachTurnState.needsRetry -> MaterialTheme.colorScheme.error
        CoachTurnState.analyzing -> MaterialTheme.colorScheme.primary
        else -> MivuTheme.colors.warning
    }
    Text(status(turn.state, provider, turn.failureReason), style = MaterialTheme.typography.bodyMedium, color = color)
}

/** "Log to <date>" while the turn needs its day; otherwise Try again for a turn that stopped. */
@Composable
private fun TurnChoices(turn: CoachTurn, days: Map<UUID, String>, actions: CoachRowActions) {
    @Composable fun chip(label: String, icon: Int, onClick: () -> Unit) = AssistChip(onClick = onClick, label = { Text(label) },
        leadingIcon = { Icon(painterResource(icon), null, Modifier.size(AssistChipDefaults.IconSize)) })
    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        if (turn.needsDayChoice == true) {
            turn.activeDayID?.let(days::get)?.let { previous ->
                chip("Log to " + CoachReplyLines.shortDate(previous), R.drawable.ic_event) { actions.chooseDay(turn.id, true) }
            }
            chip("Log to " + CoachReplyLines.shortDate(diaryDateLabel(turn.capturedAt, turn.captureTimeZoneID)), R.drawable.ic_event) {
                actions.chooseDay(turn.id, false)
            }
        } else if (turn.state in RETRYABLE) {
            chip("Try again", R.drawable.ic_refresh) { actions.retry(turn.id) }
        }
    }
}

// shortcut: profiles, nutrition source and backup have no Android screen yet, so their handoffs show no link; add them with those screens.
private val LINKS = mapOf(CoachDestination.settings to "Open Settings", CoachDestination.connection to "Open ChatGPT connection")

private val RETRYABLE = setOf(CoachTurnState.waitingForConnection, CoachTurnState.waitingForNetwork, CoachTurnState.needsRetry,
    CoachTurnState.needsClarification)

private fun status(state: CoachTurnState, provider: CoachProvider, failureReason: String?) = when (state) {
    CoachTurnState.captured -> "Waiting to start"
    CoachTurnState.analyzing -> "Thinking…"
    CoachTurnState.waitingForConnection -> "Connect ChatGPT in Settings to continue"
    CoachTurnState.waitingForNetwork -> if (provider == CoachProvider.onDevice) "I'll finish this when you're back in Mivu."
        else "Offline. I'll reply when you're back online."
    CoachTurnState.needsRetry -> when (failureReason) {
        "OnDevice.BatteryQuota" -> "Pip needs a break. Try later, or use ChatGPT in Settings."
        "OnDevice.ImagesUnsupported" -> "Photos need ChatGPT on this phone. Your meal is saved."
        else -> "Couldn't finish. Your message is saved."
    }
    CoachTurnState.needsClarification -> "I need a little more detail. Reply with it, or edit the record."
    CoachTurnState.completed -> "Completed"
}

/** iOS CoachActivityView: what the running turn is doing, read as one element. */
@Composable
private fun ActivityRow(activity: CoachActivity) {
    val title = when (activity) {
        CoachActivity.preparingPhotos -> "Looking at your photos…"
        CoachActivity.thinking -> "Thinking…"
        CoachActivity.reading -> "Checking your diary…"
        CoachActivity.saving -> "Saving…"
    }
    Row(
        Modifier.fillMaxWidth().heightIn(min = 48.dp).clearAndSetSemantics { contentDescription = "$title, Your message is saved." },
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // shortcut: material3 1.4.0 keeps the Expressive LoadingIndicator internal; swap it in when the BOM ships it stable.
        // "Remove animations" gets a still mark instead of a spinner.
        if (ValueAnimator.areAnimatorsEnabled()) CircularProgressIndicator(Modifier.size(24.dp), strokeWidth = 3.dp)
        else Icon(painterResource(R.drawable.ic_auto_awesome), null, Modifier.size(24.dp), tint = MaterialTheme.colorScheme.primary)
        Text(title, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium)
    }
}

@Composable
private fun WeightChip(label: String) {
    Row(
        Modifier.heightIn(min = 48.dp).clip(CircleShape).background(MaterialTheme.colorScheme.primaryContainer).padding(horizontal = 14.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Icon(painterResource(R.drawable.ic_check_circle), null, Modifier.size(18.dp), tint = MaterialTheme.colorScheme.primary)
        Text(label, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onPrimaryContainer)
    }
}

// Decoded Coach photos by photo ID, at most 16 MiB of bitmap bytes; at most two decodes run at once.
private val photos = object : LruCache<UUID, ImageBitmap>(16 * 1024 * 1024) {
    override fun sizeOf(key: UUID, value: ImageBitmap) = value.asAndroidBitmap().byteCount
}
private val decoding = Semaphore(2)

/** A square photo loaded by ID, never held in screen state; a placeholder while it loads or when it is gone, the meal icon when there is none. */
@Composable
fun CoachPhoto(id: UUID?, size: Dp, load: suspend () -> ByteArray?) {
    val px = with(LocalDensity.current) { size.roundToPx() }
    val bitmap by produceState(id?.let { photos.get(it) }, id) {
        if (id != null && value == null) {
            val bytes = load() ?: return@produceState
            value = decoding.withPermit { withContext(Dispatchers.Default) { decode(bytes, px) } }?.also { photos.put(id, it) }
        }
    }
    val shape = RoundedCornerShape(12.dp)
    bitmap?.let { Image(it, null, Modifier.size(size).clip(shape), contentScale = ContentScale.Crop) }
        ?: Box(Modifier.size(size).background(MivuTheme.colors.summarySurface, shape), contentAlignment = Alignment.Center) {
            if (id == null) Icon(painterResource(R.drawable.ic_restaurant), null, Modifier.size(22.dp).testTag("coachPhotoPlaceholder"),
                tint = MaterialTheme.colorScheme.onSurfaceVariant)
        }
}
