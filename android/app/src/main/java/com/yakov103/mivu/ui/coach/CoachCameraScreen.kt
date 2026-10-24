package com.yakov103.mivu.ui.coach

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import androidx.activity.compose.LocalActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts.PickMultipleVisualMedia
import androidx.activity.result.contract.ActivityResultContracts.PickVisualMedia
import androidx.activity.result.contract.ActivityResultContracts.RequestPermission
import androidx.camera.compose.CameraXViewfinder
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.Preview
import androidx.camera.core.SurfaceRequest
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.lifecycle.awaitInstance
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.yakov103.mivu.R
import com.yakov103.mivu.ui.composer.MealComposerViewModel.Companion.MAX_PHOTOS
import java.io.File
import java.util.UUID

// Port of iOS ios/Mivu/Coach/CoachCameraView.swift (status :156, controls :75) and CoachCameraSession.swift (phases :12),
// in the mockup's "Camera capture" frame. iOS words verbatim.

private const val DENIED = "Allow camera access in Settings, or choose photos."
private const val UNAVAILABLE = "Camera is unavailable. Choose photos instead."
private const val INTERRUPTED = "Camera was interrupted. Your input is kept."
private const val PREPARING = "Preparing camera…"
internal const val PHOTO_NOT_TAKEN = "Could not take photo. Your note and other photos are kept."

enum class CameraPermission { Granted, Denied, PermanentlyDenied, Unknown }

/**
 * CAMERA as the system holds it, re-read on every resume (after the system prompt or Settings). Unknown asks once; a
 * refusal the system will still ask about again is Denied, one it no longer asks about is PermanentlyDenied.
 */
@Composable
fun rememberCameraPermission(): CameraPermission {
    val context = LocalContext.current
    val activity = LocalActivity.current
    var asked by rememberSaveable { mutableStateOf(false) }
    var reads by remember { mutableIntStateOf(0) }
    LifecycleResumeEffect(Unit) { reads++; onPauseOrDispose {} }
    val prompt = rememberLauncherForActivityResult(RequestPermission()) { asked = true; reads++ }
    val permission = remember(asked, reads) {
        when {
            ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED -> CameraPermission.Granted
            activity?.shouldShowRequestPermissionRationale(Manifest.permission.CAMERA) == true -> CameraPermission.Denied
            asked -> CameraPermission.PermanentlyDenied
            else -> CameraPermission.Unknown
        }
    }
    LaunchedEffect(permission) { if (permission == CameraPermission.Unknown) prompt.launch(Manifest.permission.CAMERA) }
    return permission
}

/**
 * Full-screen CameraX for Coach: ✕, "n of 8 photos", the shutter and Choose photos. Each shot joins the draft and the
 * camera stays open until ✕; it never sends. Denied offers Settings and the Photo Picker; the draft is never touched.
 * With [retaking] (a draft photo path), one shot or one chosen photo replaces it and the camera closes (iOS `retaking`).
 */
@Composable
fun CoachCameraScreen(
    model: CoachViewModel,
    retaking: String? = null,
    permission: CameraPermission = rememberCameraPermission(),
    onClose: () -> Unit,
) {
    val context = LocalContext.current
    val owner = LocalLifecycleOwner.current
    val draft by model.draft.collectAsStateWithLifecycle()
    val importing by model.importing.collectAsStateWithLifecycle()
    val message by model.message.collectAsStateWithLifecycle()
    val earlier = remember { model.message.value } // a failure from before the camera opened stays in the composer
    val full = retaking == null && draft.photos.size >= MAX_PHOTOS
    // The picker needs at least two slots; the model keeps the cap and names any photo past it.
    val picker = rememberLauncherForActivityResult(PickMultipleVisualMedia(maxOf(2, MAX_PHOTOS - draft.photos.size))) { model.importPhotos(it) }
    val replacement = rememberLauncherForActivityResult(PickVisualMedia()) { uri ->
        if (uri != null && retaking != null) { model.retakePhoto(retaking, uri); onClose() }
    }
    val capture = remember { ImageCapture.Builder().build() }
    var request by remember { mutableStateOf<SurfaceRequest?>(null) }
    var unavailable by remember { mutableStateOf(false) }
    var interrupted by remember { mutableStateOf(false) }
    var capturing by remember { mutableStateOf(false) }
    var failed by remember { mutableStateOf(false) }

    LaunchedEffect(permission, owner) {
        if (permission != CameraPermission.Granted) return@LaunchedEffect
        val preview = Preview.Builder().build().apply { setSurfaceProvider { request = it } }
        val provider = ProcessCameraProvider.awaitInstance(context)
        val camera = try {
            provider.bindToLifecycle(owner, CameraSelector.DEFAULT_BACK_CAMERA, preview, capture)
        } catch (_: Exception) {
            unavailable = true
            return@LaunchedEffect
        }
        // Both end with the destination: CameraX unbinds and LiveData stops observing when [owner] is destroyed.
        camera.cameraInfo.cameraState.observe(owner) { interrupted = it.error != null }
    }

    val status = when {
        permission == CameraPermission.Denied || permission == CameraPermission.PermanentlyDenied -> DENIED
        unavailable -> UNAVAILABLE
        interrupted -> INTERRUPTED
        request == null -> PREPARING
        else -> null
    }
    val shutter = {
        capturing = true
        failed = false
        // Raw shots wait in the cache only until `addCapturedPhoto` prepares them into the draft folder.
        val file = File(context.cacheDir, "coach-capture").apply { mkdirs() }.resolve("${UUID.randomUUID()}.jpg")
        capture.takePicture(ImageCapture.OutputFileOptions.Builder(file).build(), ContextCompat.getMainExecutor(context),
            object : ImageCapture.OnImageSavedCallback {
                override fun onImageSaved(output: ImageCapture.OutputFileResults) {
                    capturing = false
                    if (retaking == null) model.addCapturedPhoto(file) else { model.retakePhoto(retaking, file); onClose() }
                }
                override fun onError(exception: ImageCaptureException) { capturing = false; failed = true; file.delete() }
            })
    }

    Box(Modifier.fillMaxSize().background(Color.Black)) {
        request?.takeIf { status == null }?.let { CameraXViewfinder(it, Modifier.fillMaxSize()) }
        status?.let { text ->
            Column(Modifier.align(Alignment.Center).padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(16.dp)) {
                Icon(painterResource(R.drawable.ic_photo_camera), contentDescription = null, Modifier.size(40.dp), tint = Color.White)
                Text(text, Modifier.semantics { liveRegion = LiveRegionMode.Polite }, color = Color.White,
                    style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center)
                if (text == DENIED) TextButton({
                    context.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null)))
                }, Modifier.heightIn(min = 48.dp)) { Text("Open Settings", color = Color.White) }
            }
        }
        Column(Modifier.fillMaxSize().safeDrawingPadding().padding(16.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClose, Modifier.size(48.dp).background(Scrim, CircleShape)) {
                    Icon(painterResource(R.drawable.ic_close), contentDescription = "Close", tint = Color.White)
                }
                Row(Modifier.weight(1f), horizontalArrangement = Arrangement.End) {
                    Row(Modifier.background(Scrim, RoundedCornerShape(50)).padding(horizontal = 14.dp, vertical = 8.dp),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Icon(painterResource(R.drawable.ic_photo_library), contentDescription = null, Modifier.size(18.dp), tint = Color.White)
                        Text("${draft.photos.size} of $MAX_PHOTOS photos", color = Color.White, style = MaterialTheme.typography.labelLarge)
                    }
                }
            }
            Box(Modifier.weight(1f))
            val notice = if (failed) PHOTO_NOT_TAKEN else message.takeIf { it != earlier }
            notice?.let {
                Text(it, Modifier.align(Alignment.CenterHorizontally).background(Scrim, RoundedCornerShape(12.dp)).padding(12.dp)
                    .semantics { liveRegion = LiveRegionMode.Polite }, color = Color.White, textAlign = TextAlign.Center)
            }
            Box(Modifier.fillMaxWidth().padding(top = 16.dp, bottom = 8.dp)) {
                val choose = !importing && !capturing && !full
                TextButton({ (if (retaking == null) picker else replacement).launch(PickVisualMediaRequest(PickVisualMedia.ImageOnly)) }, Modifier.align(Alignment.CenterStart).heightIn(min = 48.dp),
                    enabled = choose) {
                    Column(Modifier.alpha(if (choose) 1f else 0.4f), horizontalAlignment = Alignment.CenterHorizontally) {
                        Icon(painterResource(R.drawable.ic_photo_library), contentDescription = null,
                            Modifier.size(44.dp).background(Scrim, RoundedCornerShape(12.dp)).padding(10.dp), tint = Color.White)
                        Text("Choose photos", color = Color.White, style = MaterialTheme.typography.labelMedium)
                    }
                }
                if (status == null) {
                    val ready = !capturing && !importing && !full
                    IconButton(shutter, Modifier.align(Alignment.Center).size(72.dp).semantics { contentDescription = if (retaking == null) "Take photo" else "Retake photo" }, enabled = ready) {
                        Box(Modifier.size(72.dp).alpha(if (ready) 1f else 0.4f).border(4.dp, Color.White, CircleShape).padding(8.dp)
                            .background(Color.White, CircleShape))
                    }
                }
            }
        }
    }
}

private val Scrim = Color.Black.copy(alpha = 0.55f)
