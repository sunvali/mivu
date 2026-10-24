package com.yakov103.mivu

import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.browser.customtabs.CustomTabsIntent
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.lifecycle.lifecycleScope
import java.io.ByteArrayOutputStream
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/** Debug-only Phase 0 screen: each button runs one ChatGPT proof step and shows a redacted pass/fail line. */
class ConnectionProofActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        ProofSession.reportInterrupted(this)
        setContent { MaterialTheme { Screen() } }
    }

    @Composable
    private fun Screen() {
        val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
            if (uri != null) lifecycleScope.launch(Dispatchers.IO) {
                // shortcut: no EXIF rotation; the model still reads the meal. Upgrade if photos arrive sideways.
                ProofSession.analyzePhoto(applicationContext, jpeg(uri))
            }
        }
        Scaffold { padding ->
            Column(
                Modifier.padding(padding).padding(horizontal = 16.dp).verticalScroll(rememberScrollState()),
            ) {
                Text("ChatGPT proof (debug)", style = MaterialTheme.typography.headlineSmall, modifier = Modifier.padding(vertical = 16.dp))
                Row(ProofSession.SIGN_IN) { ProofSession.signIn(this@ConnectionProofActivity, ::openBrowser) }
                Row(ProofSession.LIST_MODELS) { ProofSession.listModels(this@ConnectionProofActivity) }
                Row(ProofSession.ANALYZE_TEXT) { ProofSession.analyzeText(this@ConnectionProofActivity) }
                Row(ProofSession.ANALYZE_PHOTO) {
                    picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                }
                Row(ProofSession.FORCE_REFRESH) { ProofSession.forceRefresh(this@ConnectionProofActivity) }
                Row(ProofSession.DISCONNECT) { ProofSession.disconnect(this@ConnectionProofActivity) }
            }
        }
    }

    @Composable
    private fun Row(label: String, onClick: () -> Unit) {
        val result = ProofSession.results[label]
        Button(
            onClick,
            Modifier.fillMaxWidth().heightIn(min = 48.dp).semantics { contentDescription = label },
            enabled = result?.text != "Running" || label == ProofSession.SIGN_IN,
        ) { Text(label) }
        Text(
            when (result?.ok) { true -> "PASS: "; false -> "FAIL: "; null -> "" } + (result?.text ?: "Not run"),
            Modifier.padding(top = 4.dp, bottom = 12.dp),
            style = MaterialTheme.typography.bodyMedium,
        )
    }

    private fun openBrowser(uri: Uri) = CustomTabsIntent.Builder().build().launchUrl(this, uri)

    // Longest side 1600 px, JPEG 85: keeps the request under the 5 MB image limit.
    private fun jpeg(uri: Uri): ByteArray {
        val bytes = contentResolver.openInputStream(uri)!!.use { it.readBytes() }
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        val sample = Integer.highestOneBit((maxOf(bounds.outWidth, bounds.outHeight) / 1600).coerceAtLeast(1))
        val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, BitmapFactory.Options().apply { inSampleSize = sample })!!
        return ByteArrayOutputStream().also { bitmap.compress(Bitmap.CompressFormat.JPEG, 85, it) }.toByteArray()
    }
}
