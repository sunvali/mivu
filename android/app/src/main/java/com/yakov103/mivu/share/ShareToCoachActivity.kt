package com.yakov103.mivu.share

import android.Manifest
import android.content.ContentResolver
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.annotation.VisibleForTesting
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SheetValue
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.createSavedStateHandle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.yakov103.mivu.MivuApplication
import com.yakov103.mivu.R
import com.yakov103.mivu.coach.TellCoach
import com.yakov103.mivu.coach.TellCoachOutcome
import com.yakov103.mivu.diary.DiaryRepository
import com.yakov103.mivu.quick.QuickAction
import com.yakov103.mivu.quick.quickIntent
import com.yakov103.mivu.ui.coach.DraftPhotos
import com.yakov103.mivu.ui.coach.loggingLine
import com.yakov103.mivu.ui.coach.photoImportLine
import com.yakov103.mivu.ui.composer.MealComposerViewModel.Companion.MAX_PHOTOS
import com.yakov103.mivu.ui.composer.preparePhoto
import com.yakov103.mivu.ui.theme.MivuTheme
import java.io.File
import java.io.IOException
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** What another app shared: text and up to [MAX_PHOTOS] image URIs; [dropped] counts the images past the limit. */
data class SharedContent(val text: String, val photos: List<Uri>, val dropped: Int = 0) {
    companion object {
        /** The Coach composer's limit, as `CoachSubmissionPayload` checks. */
        const val MAX_TEXT = 20_000
    }
}

private const val PACKAGE = "com.yakov103.mivu" // the applicationId: this app's own provider authorities start with it
private const val MAX_SHARED_BYTES = 50L * 1024 * 1024

/**
 * Reads an `ACTION_SEND` or `ACTION_SEND_MULTIPLE` from any app (an external trust boundary): the subject on its own line
 * above the text, cut to [SharedContent.MAX_TEXT]; and `content://` streams of other apps only, never a file path nor
 * Mivu's own providers. Null when nothing usable was shared.
 */
fun SharedContent.Companion.from(intent: Intent): SharedContent? {
    val multiple = when (intent.action) {
        Intent.ACTION_SEND -> false
        Intent.ACTION_SEND_MULTIPLE -> true
        else -> return null
    }
    // A wrong extra type or a bad parcel reads as nothing.
    val text = runCatching { listOfNotNull(intent.getCharSequenceExtra(Intent.EXTRA_SUBJECT), intent.getCharSequenceExtra(Intent.EXTRA_TEXT)) }
        .getOrDefault(emptyList()).map { it.toString().trim() }.filter { it.isNotEmpty() }.distinct().joinToString("\n")
        .let { if (it.length <= MAX_TEXT) it else it.take(MAX_TEXT).let { cut -> if (cut.last().isHighSurrogate()) cut.dropLast(1) else cut } }
    val streams = runCatching {
        if (multiple) intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java).orEmpty()
        else listOfNotNull(intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java))
    }.getOrDefault(emptyList()).filter { uri ->
        val authority = uri.authority.orEmpty()
        uri.scheme == ContentResolver.SCHEME_CONTENT && authority.isNotEmpty() && authority != PACKAGE && !authority.startsWith("$PACKAGE.")
    }
    if (text.isEmpty() && streams.isEmpty()) return null
    return SharedContent(text, streams.take(MAX_PHOTOS), (streams.size - MAX_PHOTOS).coerceAtLeast(0))
}

/** Copies one shared image into [folder] as a prepared JPEG (`preparePhoto`), checking its type and size first. */
internal fun prepareShared(resolver: ContentResolver, uri: Uri, folder: File): File {
    if (resolver.getType(uri)?.startsWith("image/") != true) throw IOException("not an image")
    val size = runCatching {
        resolver.query(uri, arrayOf(OpenableColumns.SIZE), null, null, null)?.use { if (it.moveToFirst() && !it.isNull(0)) it.getLong(0) else null }
    }.getOrNull()
    if (size != null && size > MAX_SHARED_BYTES) throw IOException("shared image too large")
    return preparePhoto(resolver, uri, folder)
}

/**
 * The share sheet's state. The submission ID lives in the saved state, so a rotation or process death sends the same
 * message; photos are copied into `cacheDir/share/<submissionID>/` while the sheet is open, as the read grant ends with it.
 */
class ShareViewModel(private val app: MivuApplication, private val content: SharedContent, private val saved: SavedStateHandle) : ViewModel() {
    val submissionID: UUID = saved.get<String>(ID)?.let(UUID::fromString) ?: UUID.randomUUID().also { saved[ID] = it.toString() }
    private val folder = File(app.cacheDir, "share/$submissionID")
    private val _text = MutableStateFlow(saved.get<String>(TEXT) ?: content.text)
    val text: StateFlow<String> = _text.asStateFlow()
    private val _photos = MutableStateFlow(saved.get<ArrayList<String>>(PHOTOS)?.filter { File(it).exists() }.orEmpty())
    val photos: StateFlow<List<String>> = _photos.asStateFlow()
    private val _preparing = MutableStateFlow(0)
    val preparing: StateFlow<Int> = _preparing.asStateFlow()
    /** The photo-limit or import line, kept until the sheet closes. */
    private val _photoLine = MutableStateFlow(saved.get<String>(PHOTO_LINE))
    val photoLine: StateFlow<String?> = _photoLine.asStateFlow()
    private val _sending = MutableStateFlow(false)
    val sending: StateFlow<Boolean> = _sending.asStateFlow()
    private val _outcome = MutableStateFlow<TellCoachOutcome?>(null)
    val outcome: StateFlow<TellCoachOutcome?> = _outcome.asStateFlow()
    private val _logging = MutableStateFlow<String?>(null)
    val logging: StateFlow<String?> = _logging.asStateFlow()

    init {
        if (!saved.contains(PHOTOS)) prepare() // otherwise restored: the prepared files are already in the folder
        viewModelScope.launch {
            _logging.value = withContext(Dispatchers.IO) {
                runCatching { app.existingProfile()?.let { app.repository.database(it).loggingLine() } }.getOrNull()
            }
        }
    }

    private fun prepare() = viewModelScope.launch {
        _preparing.value = content.photos.size
        val failed = mutableListOf<Int>()
        withContext(Dispatchers.IO) { folder.deleteRecursively() } // a process death mid-preparation starts over
        content.photos.forEachIndexed { index, uri ->
            try {
                val file = withContext(Dispatchers.IO) { prepareShared(app.contentResolver, uri, folder) }
                _photos.update { it + file.path }
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                failed += index + 1
            }
            _preparing.update { it - 1 }
        }
        _photoLine.value = photoImportLine(failed, (MAX_PHOTOS + 1..MAX_PHOTOS + content.dropped).toList())
        saved[PHOTO_LINE] = _photoLine.value
        saved[PHOTOS] = ArrayList(_photos.value)
    }

    fun setText(value: String) {
        _text.value = value
        saved[TEXT] = value
    }

    fun remove(path: String) {
        _photos.update { it - path }
        if (saved.contains(PHOTOS)) saved[PHOTOS] = ArrayList(_photos.value)
        File(path).delete()
    }

    fun send() {
        if (_sending.value || _preparing.value > 0) return
        _sending.value = true
        _outcome.value = null
        val text = _text.value
        val photos = _photos.value.map(::File)
        viewModelScope.launch {
            // The process scope: a started save finishes, and its reply is followed, even if the sheet goes away meanwhile.
            _outcome.value = app.scope.async {
                TellCoach.run(app, text, photos, submissionID).also {
                    if (it == TellCoachOutcome.Sent || it == TellCoachOutcome.SavedNeedsConnection) withContext(Dispatchers.IO) { folder.deleteRecursively() }
                }
            }.await()
            _sending.value = false
        }
    }

    /** Cancel, dismiss or leaving: the copied photos go. A running send keeps them until it has read them. */
    fun discard() {
        if (!_sending.value) app.scope.launch(Dispatchers.IO) { folder.deleteRecursively() }
    }

    private companion object {
        const val ID = "submissionID"
        const val TEXT = "text"
        const val PHOTOS = "photos"
        const val PHOTO_LINE = "photoLine"
    }
}

/**
 * Share to Mivu: the Android counterpart of Siri "Tell Coach". A translucent sheet over the sharing app saves the message to
 * Coach without opening Mivu.
 */
class ShareToCoachActivity : ComponentActivity() {
    private var content: SharedContent? = null
    @VisibleForTesting internal val model: ShareViewModel by viewModels {
        viewModelFactory { initializer { ShareViewModel(application as MivuApplication, content!!, createSavedStateHandle()) } }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        content = SharedContent.from(intent)
        if (content == null) {
            Toast.makeText(applicationContext, TellCoachOutcome.Failed.line, Toast.LENGTH_SHORT).show()
            finish()
            return
        }
        setContent {
            MivuTheme {
                ShareSheet(model, onClose = { model.discard(); finish() }, onOpenMivu = {
                    startActivity(quickIntent(this, QuickAction.Today))
                    model.discard()
                    finish()
                }, onSaved = { line ->
                    Toast.makeText(applicationContext, line, Toast.LENGTH_SHORT).show()
                    if (!askForNotifications()) finish()
                })
            }
        }
    }

    // The reply arrives as a notification: asked once, after the first saved share; a denial is never asked again.
    private val notificationPermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) { finish() }

    /** True when it launched the prompt, which finishes the sheet when answered. */
    private fun askForNotifications(): Boolean {
        val prefs = DiaryRepository.preferences(this)
        if (Build.VERSION.SDK_INT < 33 || prefs.getBoolean(NOTIFICATIONS_ASKED, false) ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) return false
        prefs.edit().putBoolean(NOTIFICATIONS_ASKED, true).apply()
        notificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
        return true
    }

    override fun onDestroy() {
        if (isFinishing && content != null) model.discard()
        super.onDestroy()
    }

    companion object {
        const val NOTIFICATIONS_ASKED = "coachNotificationsAsked"
    }
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
internal fun ShareSheet(model: ShareViewModel, onClose: () -> Unit, onOpenMivu: () -> Unit, onSaved: (String) -> Unit) {
    val text by model.text.collectAsState()
    val photos by model.photos.collectAsState()
    val preparing by model.preparing.collectAsState()
    val photoLine by model.photoLine.collectAsState()
    val sending by model.sending.collectAsState()
    val outcome by model.outcome.collectAsState()
    val logging by model.logging.collectAsState()
    LaunchedEffect(outcome) {
        outcome?.takeIf { it == TellCoachOutcome.Sent || it == TellCoachOutcome.SavedNeedsConnection }?.let { onSaved(it.line) }
    }
    // A running send cannot be swiped away; it finishes either way, in the process scope.
    val state = rememberModalBottomSheetState(skipPartiallyExpanded = true, confirmValueChange = { it != SheetValue.Hidden || !model.sending.value })
    ModalBottomSheet(onDismissRequest = onClose, sheetState = state) {
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 24.dp).padding(bottom = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Image(painterResource(R.drawable.pip_wave), contentDescription = null, Modifier.size(40.dp)) // decorative
                Column(Modifier.padding(start = 12.dp)) {
                    Text("Tell Coach", Modifier.semantics { heading() }, style = MaterialTheme.typography.titleLarge)
                    logging?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                }
            }
            if (photos.isNotEmpty() || preparing > 0) DraftPhotos(photos, enabled = !sending, onRemove = model::remove, onRetake = null,
                Modifier.fillMaxWidth(), preparing = preparing)
            photoLine?.let {
                Text(it, Modifier.semantics { liveRegion = LiveRegionMode.Polite }, style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            OutlinedTextField(text, model::setText, Modifier.fillMaxWidth().testTag("shareText"), enabled = !sending, minLines = 3, maxLines = 8,
                placeholder = { Text("Message") })
            outcome?.takeIf { it == TellCoachOutcome.Failed || it == TellCoachOutcome.NeedsSetup }?.let {
                Text(it.line, Modifier.semantics { liveRegion = LiveRegionMode.Polite }, color = MaterialTheme.colorScheme.error)
            }
            // Wraps at large font scales instead of clipping.
            FlowRow(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End),
                itemVerticalAlignment = Alignment.CenterVertically) {
                TextButton(onClose, Modifier.heightIn(min = 48.dp), enabled = !sending) { Text("Cancel") }
                if (outcome == TellCoachOutcome.NeedsSetup) Button(onOpenMivu, Modifier.heightIn(min = 48.dp)) { Text("Open Mivu") }
                else Button(model::send, Modifier.heightIn(min = 48.dp),
                    enabled = !sending && preparing == 0 && (text.isNotBlank() || photos.isNotEmpty())) { Text("Send to Coach") }
            }
        }
    }
}
