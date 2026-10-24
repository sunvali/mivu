package com.yakov103.mivu.ui.meal

import android.app.Activity
import android.content.ContextWrapper
import android.util.LruCache
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.DisposableEffect
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.window.DialogWindowProvider
import androidx.core.view.WindowCompat
import androidx.compose.foundation.Image
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.rememberTransformableState
import androidx.compose.foundation.gestures.transformable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.yakov103.mivu.R
import com.yakov103.mivu.diary.MealPhoto
import com.yakov103.mivu.diary.PhotoRole
import com.yakov103.mivu.ui.today.decode
import com.yakov103.mivu.ui.today.tabular
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

// Decoded photos by ID, up to an eighth of the heap (bytes are loaded by ID, never held in screen state); a stored photo
// never changes under its ID.
private val photos = object : LruCache<UUID, ImageBitmap>((Runtime.getRuntime().maxMemory() / 8).toInt()) {
    override fun sizeOf(key: UUID, value: ImageBitmap) = value.asAndroidBitmap().byteCount
}

/**
 * Loads [photo] decoded once at screen size, shared by the hero, the attached cards and the viewer; null while loading or
 * when it cannot be shown.
 */
@Composable
internal fun rememberPhoto(photo: MealPhoto, load: suspend (UUID) -> ByteArray?): Pair<ImageBitmap?, Boolean> {
    val screen = LocalWindowInfo.current.containerSize
    var failed by remember(photo.id) { mutableStateOf(false) }
    val bitmap by produceState(photos.get(photo.id), photo.id) {
        if (value == null) {
            val bytes = load(photo.id)
            value = bytes?.let { withContext(Dispatchers.Default) { decode(it, maxOf(screen.width, screen.height)) } }?.also { photos.put(photo.id, it) }
            failed = value == null
        }
    }
    return bitmap to failed
}

private const val MAX_ZOOM = 5f

/** iOS MealPhotoViewer: full screen, pinch or double-tap zoom, zoom buttons, and delete with a confirmation. */
@Composable
internal fun MealPhotoViewer(photo: MealPhoto, busy: Boolean, load: suspend (UUID) -> ByteArray?, onDelete: () -> Unit, onClose: () -> Unit) {
    var zoom by rememberSaveable(photo.id) { mutableFloatStateOf(1f) }
    var offset by remember(photo.id) { mutableStateOf(Offset.Zero) }
    var size by remember { mutableStateOf(IntSize.Zero) }
    var confirmDelete by rememberSaveable { mutableStateOf(false) }
    val (image, failed) = rememberPhoto(photo, load)

    fun clamp(next: Offset, scale: Float): Offset {
        val maxX = size.width * (scale - 1) / 2
        val maxY = size.height * (scale - 1) / 2
        return Offset(next.x.coerceIn(-maxX, maxX), next.y.coerceIn(-maxY, maxY))
    }
    fun zoomTo(next: Float) {
        zoom = next.coerceIn(1f, MAX_ZOOM)
        offset = clamp(offset, zoom)
    }
    val transform = rememberTransformableState { change, pan, _ ->
        zoomTo(zoom * change)
        offset = clamp(offset + pan, zoom)
    }
    val percent = "${(zoom * 100).toInt()}%"
    val timing = when (photo.role) {
        PhotoRole.before -> "Before eating"
        PhotoRole.after -> "After eating"
        PhotoRole.unspecified -> "Unspecified"
    }
    val onPhoto = Color.White
    val buttonColors = IconButtonDefaults.iconButtonColors(contentColor = onPhoto, disabledContentColor = onPhoto.copy(alpha = 0.38f))

    Dialog(onClose, DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        StatusIconsOverPhoto(true)
        Surface(Modifier.fillMaxSize(), color = Color.Black, contentColor = onPhoto) {
            Column(Modifier.safeDrawingPadding()) {
                Row(Modifier.fillMaxWidth().padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                    IconButton(onClose, Modifier.testTag("closeMealPhoto"), colors = buttonColors) {
                        Icon(painterResource(R.drawable.ic_close), contentDescription = "Close")
                    }
                    Text("Meal photo", Modifier.weight(1f).semantics { heading() }, style = MaterialTheme.typography.titleLarge)
                    IconButton({ confirmDelete = true }, Modifier.testTag("deleteViewedPhoto"), enabled = !busy, colors = buttonColors) {
                        Icon(painterResource(R.drawable.ic_delete), contentDescription = "Delete photo")
                    }
                }
                Box(Modifier.weight(1f).fillMaxWidth().clipToBounds().onSizeChanged { size = it }, contentAlignment = Alignment.Center) {
                    when {
                        image != null -> Image(
                            image, contentDescription = null, contentScale = ContentScale.Fit,
                            modifier = Modifier.fillMaxSize()
                                .testTag("mealPhotoZoom")
                                .semantics { contentDescription = "Meal photo"; stateDescription = "Zoom $percent" }
                                .pointerInput(Unit) { detectTapGestures(onDoubleTap = { zoomTo(if (zoom > 1f) 1f else 2f) }) }
                                .transformable(transform)
                                .graphicsLayer { scaleX = zoom; scaleY = zoom; translationX = offset.x; translationY = offset.y },
                        )
                        failed -> Column(Modifier.padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text("Photo unavailable", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                            Text("The saved attachment could not be displayed.", style = MaterialTheme.typography.bodyMedium,
                                color = onPhoto.copy(alpha = 0.72f))
                        }
                        else -> CircularProgressIndicator(color = onPhoto)
                    }
                }
                Column(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 12.dp), horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text("Photo timing: $timing", style = MaterialTheme.typography.bodyMedium, color = onPhoto.copy(alpha = 0.72f))
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                        IconButton({ zoomTo(zoom - 1) }, Modifier.testTag("zoomOutPhoto"), enabled = zoom > 1f, colors = buttonColors) {
                            Icon(painterResource(R.drawable.ic_zoom_out), contentDescription = "Zoom out")
                        }
                        Text(percent, Modifier.widthIn(min = 56.dp).testTag("photoZoomLevel"), style = MaterialTheme.typography.titleMedium.tabular(),
                            textAlign = TextAlign.Center)
                        IconButton({ zoomTo(zoom + 1) }, Modifier.testTag("zoomInPhoto"), enabled = zoom < MAX_ZOOM, colors = buttonColors) {
                            Icon(painterResource(R.drawable.ic_zoom_in), contentDescription = "Zoom in")
                        }
                    }
                }
            }
        }
        if (confirmDelete) ConfirmDelete(
            title = "Delete this photo?",
            message = "Only this photo will be removed. The meal and its notes are kept.",
            action = "Delete photo",
            tag = "confirmDeletePhoto",
            onConfirm = { confirmDelete = false; onDelete() },
            onDismiss = { confirmDelete = false },
        )
    }
}

/** Light status-bar icons over a photo while [over] holds; the theme's own icons otherwise and when this leaves. */
@Composable
internal fun StatusIconsOverPhoto(over: Boolean) {
    val view = LocalView.current
    val dark = isSystemInDarkTheme()
    DisposableEffect(view, over, dark) {
        val window = (view.parent as? DialogWindowProvider)?.window
            ?: generateSequence(view.context) { (it as? ContextWrapper)?.baseContext }.filterIsInstance<Activity>().firstOrNull()?.window
        val controller = window?.let { WindowCompat.getInsetsController(it, view) }
        controller?.isAppearanceLightStatusBars = !dark && !over
        onDispose { controller?.isAppearanceLightStatusBars = !dark }
    }
}

/** iOS destructive alert: the action in the error colour beside Cancel. */
@Composable
internal fun ConfirmDelete(title: String, message: String, action: String, tag: String, onConfirm: () -> Unit, onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = { Text(message) },
        confirmButton = {
            TextButton(onConfirm, Modifier.testTag(tag), colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error)) {
                Text(action)
            }
        },
        dismissButton = { TextButton(onDismiss) { Text("Cancel") } },
    )
}
