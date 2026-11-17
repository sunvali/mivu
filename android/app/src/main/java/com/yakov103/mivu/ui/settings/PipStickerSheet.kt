package com.yakov103.mivu.ui.settings

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.graphics.ImageDecoder
import android.graphics.drawable.AnimatedImageDrawable
import android.net.Uri
import android.provider.Settings
import android.widget.ImageView
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.FileProvider
import com.yakov103.mivu.stickers.PipStickerItem
import com.yakov103.mivu.stickers.PipStickers
import java.io.File

fun animatorsEnabled(context: Context) =
    Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) != 0f

/** iOS `PipStickerSheet`: tap a sticker to share it, or add a pack to WhatsApp. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PipStickerSheet(onDismiss: () -> Unit, animate: Boolean = animatorsEnabled(LocalContext.current)) {
    val context = LocalContext.current
    var missing by remember { mutableStateOf(false) }
    fun add(animated: Boolean) {
        try {
            if (PipStickers.whatsAppInstalled(context)) context.startActivity(PipStickers.enableIntent(context, animated)) else missing = true
        } catch (_: ActivityNotFoundException) { missing = true }
    }
    ModalBottomSheet(onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("Pip stickers", Modifier.semantics { heading() }, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
            Text("Tap a sticker to share it.", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            LazyVerticalGrid(
                GridCells.Adaptive(72.dp), Modifier.weight(1f, fill = false),
                horizontalArrangement = Arrangement.spacedBy(12.dp), verticalArrangement = Arrangement.spacedBy(12.dp),
            ) { items(PipStickers.all, key = { it.id }) { StickerCell(it, animate) } }
            Button({ add(false) }, Modifier.fillMaxWidth().heightIn(min = 48.dp).testTag("addPipToWhatsApp")) {
                Text("Add “Pip” to WhatsApp", textAlign = TextAlign.Center)
            }
            FilledTonalButton({ add(true) }, Modifier.fillMaxWidth().heightIn(min = 48.dp).testTag("addPipMovesToWhatsApp")) {
                Text("Add “Pip moves” to WhatsApp", textAlign = TextAlign.Center)
            }
            Box(Modifier.padding(bottom = 16.dp))
        }
    }
    if (missing) AlertDialog(
        onDismissRequest = { missing = false },
        modifier = Modifier.testTag("whatsAppMissing"),
        title = { Text("WhatsApp isn't installed") },
        text = { Text("Install WhatsApp to add Pip stickers.") },
        confirmButton = { TextButton({ missing = false; getWhatsApp(context) }) { Text("Get WhatsApp") } },
        dismissButton = { TextButton({ missing = false }) { Text("Cancel") } },
    )
}

@Composable
private fun StickerCell(sticker: PipStickerItem, animate: Boolean) {
    val context = LocalContext.current
    val playing = sticker.animated && animate
    Box(
        Modifier.aspectRatio(1f).heightIn(min = 72.dp).clip(RoundedCornerShape(16.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant)
            .testTag("pipSticker-" + sticker.id)
            .semantics(mergeDescendants = true) {
                contentDescription = sticker.accessibilityText
                role = Role.Button
                if (playing) stateDescription = "animated"
            }
            .clickable { share(context, sticker) },
        contentAlignment = Alignment.Center,
    ) {
        AndroidView({ ctx ->
            ImageView(ctx).apply {
                scaleType = ImageView.ScaleType.FIT_CENTER
                (8 * resources.displayMetrics.density).toInt().let { setPadding(it, it, it, it) }
                importantForAccessibility = ImageView.IMPORTANT_FOR_ACCESSIBILITY_NO
                val drawable = ImageDecoder.decodeDrawable(ImageDecoder.createSource(ctx.assets, sticker.shareAsset))
                setImageDrawable(drawable)
                // An unstarted AnimatedImageDrawable draws its first frame, which is the still state.
                if (playing && drawable is AnimatedImageDrawable) drawable.start()
            }
        }, Modifier.fillMaxWidth().aspectRatio(1f))
    }
}

private fun share(context: Context, sticker: PipStickerItem) {
    val file = File(context.cacheDir, "stickers/" + File(sticker.shareAsset).name).apply { parentFile?.mkdirs() }
    context.assets.open(sticker.shareAsset).use { input -> file.outputStream().use { input.copyTo(it) } }
    val uri = FileProvider.getUriForFile(context, "${context.packageName}.reports", file)
    val send = Intent(Intent.ACTION_SEND).setType(if (sticker.animated) "image/gif" else "image/png")
        .putExtra(Intent.EXTRA_STREAM, uri).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    context.startActivity(Intent.createChooser(send, null))
}

private fun getWhatsApp(context: Context) {
    val market = Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=com.whatsapp")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    try { context.startActivity(market) } catch (_: ActivityNotFoundException) {
        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://play.google.com/store/apps/details?id=com.whatsapp")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }
}
