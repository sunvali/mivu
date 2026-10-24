package com.yakov103.mivu.ui.coach

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SuggestionChip
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.yakov103.mivu.R
import com.yakov103.mivu.pip.CompanionOutput
import com.yakov103.mivu.pip.CompanionPose
import com.yakov103.mivu.pip.CompanionRuntime
import com.yakov103.mivu.pip.CompanionSurface
import com.yakov103.mivu.pip.PipAssets
import com.yakov103.mivu.pip.PipCompanion
import com.yakov103.mivu.pip.PipGestureLibrary
import com.yakov103.mivu.pip.PipRigScene
import com.yakov103.mivu.ui.composer.MealComposerViewModel.Companion.MAX_PHOTOS
import com.yakov103.mivu.ui.theme.MivuTheme
import com.yakov103.mivu.ui.today.decode
import com.yakov103.mivu.ui.today.isLargeText
import java.io.File
import kotlin.math.roundToInt
import kotlin.random.Random
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

// Port of the iOS Coach composer (ios/Mivu/Coach/CoachView.swift: companionStrip :311, composer :343, composerInput :411,
// starters :450, draftPhotos :529, replyBar :556) in the mockup's "Composer with drafts" layout.

private val STARTERS = listOf("Log breakfast" to "For breakfast I had ", "Log my weight" to "My weight this morning is ",
    "How am I doing today?" to "How am I doing today?")

const val CHATGPT_USAGE = "https://chatgpt.com/settings/usage"

/**
 * The docked composer: suggestion chips (empty conversation only), draft photos, Pip peeking over the field with the
 * logging caption, the field with its quote and camera, one round action, and the footnote.
 */
@Composable
fun CoachComposer(
    model: CoachViewModel,
    showStarters: Boolean,
    focusRequester: FocusRequester,
    onAddPhotos: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val draft by model.draft.collectAsStateWithLifecycle()
    val sending by model.sending.collectAsStateWithLifecycle()
    val importing by model.importing.collectAsStateWithLifecycle()
    val message by model.message.collectAsStateWithLifecycle()
    val logging by model.logging.collectAsStateWithLifecycle()
    val companion by model.companion.collectAsStateWithLifecycle()
    var focused by remember { mutableStateOf(false) }
    val connected = remember(model) { model.isConnected() }
    val large = isLargeText()

    val focus = LocalFocusManager.current
    val inset = Modifier.padding(horizontal = 16.dp)
    Column(modifier.fillMaxWidth().padding(top = 4.dp, bottom = 4.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        // Each starter fills the draft for review; nothing is sent until Send.
        if (showStarters && !draft.canSend && !focused) Row(
            // Scrolls under the side margins, so the last chip reads as more, not as clipped.
            Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            STARTERS.forEach { (title, text) ->
                SuggestionChip({ model.updateText(text); focusRequester.requestFocus() }, { Text(title) },
                    Modifier.heightIn(min = 48.dp).testTag("coachStarter"), shape = RoundedCornerShape(12.dp))
            }
        }
        if (draft.photos.isNotEmpty()) DraftPhotos(draft.photos, enabled = !sending, onRemove = model::removePhoto, inset)
        if (importing) Text("Preparing photos", inset, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Row(inset, verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Column(Modifier.weight(1f)) {
                // Pip stands on the field's flat top edge at the left, never on the round button.
                Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    CoachPip(model, companion, if (large) 76.dp else 112.dp)
                    Caption(logging, message, companion.pose == CompanionPose.Recovery, large,
                        Modifier.weight(1f).padding(bottom = 6.dp))
                }
                Field(model, draft, sending, focusRequester, onFocus = { focused = it }, onAddPhotos = onAddPhotos)
            }
            // One round action: the mic while the draft is empty, Send once there is something to send.
            if (draft.canSend || sending) FilledIconButton({ focus.clearFocus(); model.send() },
                Modifier.size(48.dp).semantics { contentDescription = "Send" }, enabled = !sending && !importing) {
                if (sending) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp, color = MaterialTheme.colorScheme.onPrimary)
                else Icon(painterResource(R.drawable.ic_arrow_upward), contentDescription = null)
            } else FilledTonalIconButton({ /* shortcut: voice input arrives in Task 8; the mic is inert until then. */ }, Modifier.size(48.dp)) {
                Icon(painterResource(R.drawable.ic_mic), contentDescription = "Speak your meal")
            }
        }
        Footnote(connected, inset)
    }
}

/** Pip in the Coach crop; the still preview space is kept while the rig loads, so the field does not jump. */
@Composable
private fun CoachPip(model: CoachViewModel, output: CompanionOutput, width: Dp) {
    val context = LocalContext.current
    val assets = produceState<Pair<PipRigScene, PipGestureLibrary>?>(null) {
        value = runCatching { PipAssets.load(context) }.getOrNull()
    }.value
    val scope = rememberCoroutineScope()
    val runtime = assets?.let { (scene, library) ->
        remember(scene) { CompanionRuntime(library, scene, scope, { System.nanoTime() / 1_000_000 }, Random.Default) }
    }
    if (runtime != null) PipCompanion(output, CompanionSurface.Coach, width, runtime, { if (!model.touchPip(it)) runtime.earTwitch() })
    else Spacer(Modifier.size(width, (width.value * 288.8f / 277.8f).roundToInt().dp)) // the rig's "coach" crop
}

/** "Logging to today · 2,100 kcal goal", and in recovery the error, or that the message is safe. */
@Composable
private fun Caption(logging: String?, message: String?, recovery: Boolean, large: Boolean, modifier: Modifier) {
    Column(modifier.semantics { liveRegion = LiveRegionMode.Polite }, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        logging?.let {
            // At large sizes the day and the goal stack instead of sharing a line.
            Text(if (large) it.replace(" · ", "\n") else it, Modifier.testTag("coachCaption"), style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        if (message != null) Text(message, Modifier.testTag("coachError"), style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.error)
        else if (recovery) Text("Your message is safe here", style = MaterialTheme.typography.bodyMedium)
    }
}

@Composable
private fun Field(
    model: CoachViewModel,
    draft: CoachDraft,
    sending: Boolean,
    focusRequester: FocusRequester,
    onFocus: (Boolean) -> Unit,
    onAddPhotos: () -> Unit,
) {
    // Local field state keeps the cursor; outside changes (a chip, a handoff, a send) put the caret at the end.
    var value by remember { mutableStateOf(TextFieldValue(draft.text, TextRange(draft.text.length))) }
    LaunchedEffect(draft.text) { if (value.text != draft.text) value = TextFieldValue(draft.text, TextRange(draft.text.length)) }
    var focused by remember { mutableStateOf(false) }
    var caret by remember { mutableStateOf(0) }
    LaunchedEffect(focused, caret) { model.reportComposer(focused, listening = false, caret = caret) }
    val shape = RoundedCornerShape(24.dp)
    Column(
        Modifier.fillMaxWidth().testTag("coachField").clip(shape).background(MaterialTheme.colorScheme.surfaceContainerHigh)
            .border(1.dp, if (focused) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f), shape),
    ) {
        draft.reply?.let { CoachReplyBar(it, model::cancelReply) }
        Row(verticalAlignment = Alignment.Bottom) {
            BasicTextField(
                value,
                onValueChange = { value = it; model.updateText(it.text) },
                modifier = Modifier.weight(1f).heightIn(min = 48.dp).padding(start = 16.dp, top = 12.dp, bottom = 12.dp)
                    .focusRequester(focusRequester).onFocusChanged { focused = it.isFocused; onFocus(it.isFocused) }.testTag("coachInput"),
                enabled = !sending,
                textStyle = MaterialTheme.typography.bodyLarge.copy(color = MaterialTheme.colorScheme.onSurface),
                keyboardOptions = KeyboardOptions(KeyboardCapitalization.Sentences),
                // Grows to four lines (three at large sizes), then scrolls inside the field.
                maxLines = if (isLargeText()) 3 else 4,
                cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
                // Pip's eyes follow where the last line ends across the field, 0...60, as iOS caretSignal.
                onTextLayout = { layout ->
                    val width = layout.size.width
                    caret = if (width == 0 || value.text.isEmpty()) 0
                    else (layout.getLineRight(layout.lineCount - 1) / width * 60).roundToInt().coerceIn(0, 60)
                },
                decorationBox = { inner ->
                    Box {
                        if (value.text.isEmpty()) Text("Describe a meal…", style = MaterialTheme.typography.bodyLarge,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                        inner()
                    }
                },
            )
            IconButton(onAddPhotos, Modifier.size(48.dp), enabled = !sending && draft.photos.size < MAX_PHOTOS) {
                Icon(painterResource(R.drawable.ic_photo_camera), contentDescription = "Add photos", Modifier.size(22.dp),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

private val THUMB = 64.dp

/** The draft's photos, each with a 48 dp remove control on its corner, and how many of the eight are used. */
@Composable
private fun DraftPhotos(photos: List<String>, enabled: Boolean, onRemove: (String) -> Unit, modifier: Modifier) {
    Row(modifier, verticalAlignment = Alignment.CenterVertically) {
        Row(Modifier.weight(1f, fill = false).horizontalScroll(rememberScrollState()).padding(top = 8.dp, end = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            photos.forEachIndexed { index, path ->
                Box(Modifier.size(THUMB)) {
                    val px = with(LocalDensity.current) { THUMB.roundToPx() }
                    val bitmap by produceState<ImageBitmap?>(null, path) {
                        value = withContext(Dispatchers.IO) { runCatching { decode(File(path).readBytes(), px) }.getOrNull() }
                    }
                    val shape = RoundedCornerShape(12.dp)
                    bitmap?.let { Image(it, contentDescription = "Attached photo ${index + 1}", Modifier.size(THUMB).clip(shape), contentScale = ContentScale.Crop) }
                        ?: Box(Modifier.size(THUMB).background(MivuTheme.colors.summarySurface, shape))
                    IconButton({ onRemove(path) }, Modifier.align(Alignment.TopEnd).offset(16.dp, (-16).dp).size(48.dp), enabled = enabled) {
                        Box(Modifier.size(24.dp).background(MaterialTheme.colorScheme.inverseSurface, CircleShape), contentAlignment = Alignment.Center) {
                            Icon(painterResource(R.drawable.ic_close), contentDescription = "Remove photo ${index + 1}", Modifier.size(16.dp),
                                tint = MaterialTheme.colorScheme.inverseOnSurface)
                        }
                    }
                }
            }
        }
        Text("${photos.size} of $MAX_PHOTOS photos", Modifier.padding(start = 8.dp), style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/** Not connected: messages still save here. Connected: the plan in use, with Manage usage. */
@Composable
private fun Footnote(connected: Boolean, modifier: Modifier) {
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
    if (!connected) {
        // shortcut: "Connect ChatGPT for replies" waits for the release sign-in screen (carried to 4c).
        Text("Messages save on this phone.", modifier.padding(start = 4.dp), style = MaterialTheme.typography.bodySmall, color = secondary)
    } else {
        val uri = LocalUriHandler.current
        Row(modifier, verticalAlignment = Alignment.CenterVertically) {
            Text("Using ChatGPT plan · ", Modifier.padding(start = 4.dp), style = MaterialTheme.typography.bodySmall, color = secondary)
            TextButton({ uri.openUri(CHATGPT_USAGE) }, Modifier.heightIn(min = 48.dp),
                contentPadding = PaddingValues(horizontal = 4.dp)) {
                Text("Manage usage", style = MaterialTheme.typography.bodySmall, fontWeight = FontWeight.SemiBold)
            }
        }
    }
}
