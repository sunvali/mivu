package com.yakov103.mivu.ui.coach

import androidx.compose.animation.Crossfade
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.material3.ProvideTextStyle
import androidx.compose.material3.Surface
import androidx.compose.ui.semantics.onClick
import com.yakov103.mivu.ui.today.tabular
import java.time.LocalTime
import com.yakov103.mivu.connection.CoachProvider
import com.yakov103.mivu.connection.ConnectionState
import com.yakov103.mivu.ui.settings.ChatGPTConnectButton
import com.yakov103.mivu.ui.settings.ConnectStyle
import com.yakov103.mivu.ui.settings.MivuLinks
import android.Manifest
import android.animation.ValueAnimator
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts.PickMultipleVisualMedia
import androidx.activity.result.contract.ActivityResultContracts.PickVisualMedia
import androidx.activity.result.contract.ActivityResultContracts.RequestPermission
import androidx.compose.foundation.Canvas
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
import androidx.compose.material3.IconButtonDefaults
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
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.yakov103.mivu.R
import com.yakov103.mivu.pip.CompanionOutput
import com.yakov103.mivu.pip.CompanionRuntime
import com.yakov103.mivu.pip.CompanionSurface
import com.yakov103.mivu.pip.PipAssets
import com.yakov103.mivu.pip.PipCompanion
import com.yakov103.mivu.pip.PipGestureLibrary
import com.yakov103.mivu.pip.PipRigScene
import com.yakov103.mivu.ui.composer.MealComposerViewModel.Companion.MAX_PHOTOS
import com.yakov103.mivu.ui.composer.MealComposerViewModel.Companion.MAX_TEXT
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

/**
 * The docked composer: suggestion chips (empty conversation only), draft photos, Pip peeking over the field with his
 * bubble and the day chip, the field with its quote and camera, one round action, and the footnote.
 */
@Composable
fun CoachComposer(
    model: CoachViewModel,
    showStarters: Boolean,
    focusRequester: FocusRequester,
    /** Opens the camera, or retakes the draft photo at the given path. */
    onOpenCamera: (String?) -> Unit,
    /** Without a camera the field offers the Photo Picker and photos have no Retake. */
    hasCamera: Boolean,
    modifier: Modifier = Modifier,
    voice: CoachVoiceInput = rememberCoachVoice(),
    connection: ConnectionState = ConnectionState(),
    onAgree: () -> Unit = {},
    onConnect: () -> Unit = {},
    /** The morning weigh-in bubble above Pip; hidden while the person types or speaks. */
    bubble: (@Composable () -> Unit)? = null,
    /** The day chip opens Today. */
    onSeeToday: () -> Unit = {},
) {
    val draft by model.draft.collectAsStateWithLifecycle()
    val sending by model.sending.collectAsStateWithLifecycle()
    val importing by model.importing.collectAsStateWithLifecycle()
    val message by model.message.collectAsStateWithLifecycle()
    val coachDay by model.coachDay.collectAsStateWithLifecycle()
    val pip by model.pip.collectAsStateWithLifecycle()
    val activity by model.activity.collectAsStateWithLifecycle()
    val companion by model.companion.collectAsStateWithLifecycle()
    val phase by voice.phase.collectAsStateWithLifecycle()
    val levels by voice.levels.collectAsStateWithLifecycle()
    val note by voice.note.collectAsStateWithLifecycle()
    var focused by remember { mutableStateOf(false) }
    val connected by model.connected.collectAsStateWithLifecycle()
    val large = isLargeText()

    val focus = LocalFocusManager.current
    val context = LocalContext.current
    val listen = { voice.start(model.draft.value.text, model::updateText) }
    // start() re-checks the grant, so a refusal shows the Settings note.
    val microphone = rememberLauncherForActivityResult(RequestPermission()) { listen() }
    // The picker needs at least two slots; the model keeps the cap and names any photo past it.
    val picker = rememberLauncherForActivityResult(PickMultipleVisualMedia(maxOf(2, MAX_PHOTOS - draft.photos.size))) { model.importPhotos(it) }
    // Leaving, backgrounding or covering Coach (the camera, a picker) pauses it: the microphone is released, the text stays.
    LifecycleResumeEffect(voice, model) { onPauseOrDispose { voice.stop() } }
    val view = LocalView.current
    var announced by remember { mutableStateOf(false) }
    LaunchedEffect(phase) {
        if (phase == CoachVoiceInput.Phase.Listening) view.announceForAccessibility("Listening")
        else if (phase == CoachVoiceInput.Phase.Idle && announced) view.announceForAccessibility("Stopped listening")
        announced = phase == CoachVoiceInput.Phase.Listening
    }
    val inset = Modifier.padding(horizontal = 16.dp)
    val background = MaterialTheme.colorScheme.background
    // As iOS: the chat fades out under a 56 dp band, then the screen's background; no pointer input, so drags reach the list.
    Column(modifier.fillMaxWidth().testTag("coachComposer").drawBehind {
        drawRect(Brush.verticalGradient(0f to background.copy(alpha = 0f), (56.dp.toPx() / size.height).coerceAtMost(1f) to background))
    }.padding(top = 4.dp, bottom = 4.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (bubble != null && !focused && phase == CoachVoiceInput.Phase.Idle) Box(inset) { bubble() }
        // Each starter fills the draft for review; nothing is sent until Send.
        if (showStarters && !draft.canSend && !focused && phase == CoachVoiceInput.Phase.Idle) Row(
            // Scrolls under the side margins, so the last chip reads as more, not as clipped.
            Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            STARTERS.forEach { (title, text) ->
                SuggestionChip({ model.updateText(text); focusRequester.requestFocus() }, { Text(title) },
                    Modifier.heightIn(min = 48.dp).testTag("coachStarter"), shape = RoundedCornerShape(12.dp))
            }
        }
        if (draft.photos.isNotEmpty()) DraftPhotos(draft.photos, enabled = !sending, onRemove = model::removePhoto,
            onRetake = onOpenCamera.takeIf { hasCamera }, inset)
        if (importing) Text("Preparing photos", inset, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        // Pip stands on the left of the field's flat top edge, never on the round button; his bubble and chip may run over
        // the button's column so short lines do not wrap (iOS #70).
        Column(inset) {
            Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                CoachPip(model, companion, if (large) 76.dp else 112.dp)
                Column(Modifier.weight(1f)) {
                    val line = PipLine.current(LocalTime.now().hour, coachDay?.mealsLogged == true, focused, connected, pip.processing,
                        pip.withPhotos, pip.recovery, message, pip.turnState, connection.provider == CoachProvider.onDevice)
                        // At large sizes the greeting would crowd the conversation; status and errors still show.
                        ?.takeUnless { large && it is PipLine.Say }
                    Crossfade(line, label = "pipLine") { shown ->
                        if (shown != null) PipBubble(shown, connection, onAgree, onConnect,
                            retry = pip.turnID?.let { id -> { model.retry(id) } }, working = activity != null)
                    }
                    coachDay?.let { DayChip(it.chip, onSeeToday) }
                }
            }
            Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                // Typing stops listening, so later speech never overwrites typed words.
                Box(Modifier.weight(1f)) {
                    Field(model, draft, sending, focusRequester, phase == CoachVoiceInput.Phase.Listening, levels,
                        onFocus = { focused = it; if (it) voice.stop() }, hasCamera = hasCamera,
                        onAddPhotos = { if (hasCamera) onOpenCamera(null) else picker.launch(PickVisualMediaRequest(PickVisualMedia.ImageOnly)) })
                }
                // One round action: Stop while voice runs, the mic while the draft is empty, Send once there is something to send.
                if (phase != CoachVoiceInput.Phase.Idle) FilledIconButton(voice::stop, Modifier.size(48.dp).semantics { contentDescription = "Stop listening" },
                    colors = IconButtonDefaults.filledIconButtonColors(MaterialTheme.colorScheme.error, MaterialTheme.colorScheme.onError)) {
                    if (phase == CoachVoiceInput.Phase.Preparing) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp, color = MaterialTheme.colorScheme.onError)
                    else Icon(painterResource(R.drawable.ic_stop), contentDescription = null)
                } else if (draft.canSend || sending) FilledIconButton({ focus.clearFocus(); model.send() },
                    Modifier.size(48.dp).semantics { contentDescription = "Send" }, enabled = !sending && !importing) {
                    if (sending) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp, color = MaterialTheme.colorScheme.onPrimary)
                    else Icon(painterResource(R.drawable.ic_arrow_upward), contentDescription = null)
                } else FilledTonalIconButton({
                    focus.clearFocus()
                    if (context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) listen()
                    else microphone.launch(Manifest.permission.RECORD_AUDIO)
                }, Modifier.size(48.dp), enabled = voice.available) {
                    Icon(painterResource(R.drawable.ic_mic), contentDescription = "Speak your meal")
                }
            }
        }
        note?.let {
            Text(it, inset.testTag("coachVoiceNote").semantics { liveRegion = LiveRegionMode.Polite },
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        if (connected) Footnote(inset)
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

/** Pip's speech (iOS pipBubble): the corner nearest Pip stays tight so the bubble reads as his. */
@Composable
private fun PipBubble(line: PipLine, connection: ConnectionState, onAgree: () -> Unit, onConnect: () -> Unit, retry: (() -> Unit)?,
    working: Boolean) {
    val shape = RoundedCornerShape(18.dp, 18.dp, 18.dp, 6.dp)
    val action = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.SemiBold)
    Surface(Modifier.testTag("coachPipLine").semantics { liveRegion = LiveRegionMode.Polite }, shape = shape,
        color = MaterialTheme.colorScheme.surface, border = BorderStroke(0.5.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f))) {
        Column(Modifier.padding(horizontal = 14.dp, vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            ProvideTextStyle(MaterialTheme.typography.bodyMedium) {
                when (line) {
                    is PipLine.Say -> Text(line.text)
                    is PipLine.Working -> Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        // Animations off: a still ring, as iOS's static circle.dotted.
                        if (ValueAnimator.areAnimatorsEnabled()) CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                        else CircularProgressIndicator({ 0.75f }, Modifier.size(16.dp).clearAndSetSemantics {}, strokeWidth = 2.dp)
                        Text(line.text)
                    }
                    is PipLine.Problem -> {
                        Text(line.text, Modifier.testTag("coachError"))
                        line.detail?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                        if (line.canRetry && retry != null) TextButton(retry, Modifier.heightIn(min = 48.dp), enabled = !working,
                            contentPadding = PaddingValues(horizontal = 4.dp)) { Text("Try again", style = action) }
                    }
                    PipLine.Connect -> {
                        Text("Connect ChatGPT so I can count for you")
                        ChatGPTConnectButton(connection, onAgree, onConnect, title = "Connect", style = ConnectStyle.Link)
                    }
                }
            }
        }
    }
}

/** "Today · 1,240 / 2,000 kcal": the logging day and its intake; opens Today. The tap area reaches 48 dp around the capsule. */
@Composable
private fun DayChip(chip: CoachDayChip, onSeeToday: () -> Unit) {
    Surface(onSeeToday, Modifier.testTag("coachDate").semantics { contentDescription = chip.spoken; onClick("Opens Today") { onSeeToday(); true } }
        .heightIn(min = 48.dp), shape = CircleShape, color = Color.Transparent) {
        Box(contentAlignment = Alignment.CenterStart) {
            Text(chip.text, Modifier.background(MivuTheme.colors.summarySurface, CircleShape).padding(horizontal = 12.dp, vertical = 6.dp),
                style = MaterialTheme.typography.labelMedium.tabular(), color = MaterialTheme.colorScheme.primary)
        }
    }
}

@Composable
private fun Field(
    model: CoachViewModel,
    draft: CoachDraft,
    sending: Boolean,
    focusRequester: FocusRequester,
    listening: Boolean,
    levels: List<Float>,
    onFocus: (Boolean) -> Unit,
    hasCamera: Boolean,
    onAddPhotos: () -> Unit,
) {
    // Local field state keeps the cursor; outside changes (a chip, a handoff, a send) put the caret at the end.
    var value by remember { mutableStateOf(TextFieldValue(draft.text, TextRange(draft.text.length))) }
    LaunchedEffect(draft.text) { if (value.text != draft.text) value = TextFieldValue(draft.text, TextRange(draft.text.length)) }
    var focused by remember { mutableStateOf(false) }
    var caret by remember { mutableStateOf(0) }
    LaunchedEffect(focused, caret, listening) { model.reportComposer(focused, listening, caret) }
    val shape = RoundedCornerShape(24.dp)
    Column(
        Modifier.fillMaxWidth().testTag("coachField").clip(shape).background(MaterialTheme.colorScheme.surfaceContainerHigh)
            .border(1.dp, if (focused) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f), shape),
    ) {
        draft.reply?.let { CoachReplyBar(it, model::cancelReply) }
        Row(verticalAlignment = Alignment.Bottom) {
            BasicTextField(
                value,
                // Clamped as the model clamps, so the field never shows text that would not be sent.
                onValueChange = { next ->
                    value = if (next.text.length <= MAX_TEXT) next else TextFieldValue(next.text.take(MAX_TEXT), TextRange(MAX_TEXT))
                    model.updateText(value.text)
                },
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
                        if (value.text.isEmpty() && !listening) Text("Describe a meal…", style = MaterialTheme.typography.bodyLarge,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                        inner()
                    }
                },
            )
            if (listening) Wave(levels, Modifier.padding(start = 4.dp, bottom = 16.dp))
            IconButton(onAddPhotos, Modifier.size(48.dp), enabled = !sending && draft.photos.size < MAX_PHOTOS) {
                Icon(painterResource(if (hasCamera) R.drawable.ic_photo_camera else R.drawable.ic_photo_library),
                    contentDescription = if (hasCamera) "Add photos" else "Choose photos", Modifier.size(22.dp),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable
private fun rememberCoachVoice(): CoachVoiceInput {
    val context = LocalContext.current.applicationContext
    return remember(context) { CoachVoiceInput(context) }
}

/** iOS waveImage: three rounded bars that follow the microphone level; still at mid height with animations off. */
@Composable
private fun Wave(levels: List<Float>, modifier: Modifier) {
    val color = MaterialTheme.colorScheme.primary
    val still = !ValueAnimator.areAnimatorsEnabled()
    Canvas(modifier.size(16.dp)) {
        val bar = 3.dp.toPx()
        levels.forEachIndexed { index, level ->
            val height = 4.dp.toPx() + (if (still) 0.5f else level) * (size.height - 4.dp.toPx())
            drawRoundRect(color, Offset(index * 6.dp.toPx(), (size.height - height) / 2), Size(bar, height), CornerRadius(bar / 2))
        }
    }
}

private val THUMB = 64.dp

/**
 * The draft's photos, each with a 48 dp remove control on its corner and Retake under it (iOS draftPhotos; none without a
 * camera), and how many of the eight are used.
 */
@Composable
internal fun DraftPhotos(photos: List<String>, enabled: Boolean, onRemove: (String) -> Unit, onRetake: ((String) -> Unit)?, modifier: Modifier,
    preparing: Int = 0) {
    Row(modifier, verticalAlignment = Alignment.CenterVertically) {
        Row(Modifier.weight(1f, fill = false).horizontalScroll(rememberScrollState()).padding(top = 8.dp, end = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            photos.forEachIndexed { index, path ->
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
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
                    onRetake?.let { retake ->
                        TextButton({ retake(path) }, Modifier.heightIn(min = 48.dp).semantics { contentDescription = "Retake photo ${index + 1}" },
                            enabled = enabled, contentPadding = PaddingValues(horizontal = 4.dp)) {
                            Text("Retake", Modifier.clearAndSetSemantics {}, style = MaterialTheme.typography.labelMedium)
                        }
                    }
                }
            }
            // Photos still being prepared off the main thread.
            repeat(preparing) {
                Box(Modifier.size(THUMB).background(MivuTheme.colors.summarySurface, RoundedCornerShape(12.dp)),
                    contentAlignment = Alignment.Center) { CircularProgressIndicator(Modifier.size(24.dp), strokeWidth = 2.dp) }
            }
        }
        Text("${photos.size} of $MAX_PHOTOS photos", Modifier.padding(start = 8.dp), style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/** iOS footnote, connected only: the plan in use with Manage usage. Without a model, Pip's bubble offers the connection. */
@Composable
private fun Footnote(modifier: Modifier) {
    val uri = LocalUriHandler.current
    FlowRow(modifier, itemVerticalAlignment = Alignment.CenterVertically) {
        Text("Using ChatGPT plan", Modifier.padding(start = 4.dp), style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
        TextButton({ uri.openUri(MivuLinks.USAGE) }, Modifier.heightIn(min = 48.dp), contentPadding = PaddingValues(horizontal = 4.dp)) {
            Text("Manage usage", style = MaterialTheme.typography.bodySmall, fontWeight = FontWeight.SemiBold)
        }
    }
}
