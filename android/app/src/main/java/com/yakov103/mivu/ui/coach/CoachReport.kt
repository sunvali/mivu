package com.yakov103.mivu.ui.coach

import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.annotation.VisibleForTesting
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.ClipEntry
import androidx.compose.ui.platform.LocalClipboard
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import com.yakov103.mivu.R
import com.yakov103.mivu.ui.settings.MivuLinks
import java.io.File
import java.io.FileOutputStream
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject

internal val REPORT_REASONS = listOf("Harmful or unsafe", "Wrong or misleading", "Offensive or inappropriate", "Something else")

/**
 * Coach reply reports kept on this phone, one JSON line each: turn ID, reason, note, time. Not diary data, so not in the
 * archive; filesDir moves with a device transfer and stays out of cloud backup (data_extraction_rules).
 */
object CoachReports {
    fun file(context: Context) = File(context.filesDir, "coach-reports.jsonl")

    /** Appends and syncs one report; throws when it could not be written. */
    fun save(context: Context, turnID: UUID, reason: String, note: String, at: Instant = Instant.now()) {
        val line = JSONObject().put("turnID", turnID.toString()).put("reason", reason).put("note", note).put("at", at.toString())
        FileOutputStream(file(context), true).use { it.write("$line\n".toByteArray()); it.fd.sync() }
    }
}

/** An email draft to Mivu with the reason, the person's note and only the reply's text; the person sends it. */
fun reportIntent(reply: String, reason: String, note: String): Intent = Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:"))
    .putExtra(Intent.EXTRA_EMAIL, arrayOf(MivuLinks.REPORT_EMAIL))
    .putExtra(Intent.EXTRA_SUBJECT, "Mivu Coach reply report")
    .putExtra(Intent.EXTRA_TEXT, "Reason: $reason\n" + (if (note.isBlank()) "" else "Note: ${note.trim()}\n") + "\nCoach reply:\n$reply")

@VisibleForTesting internal var startEmailForTest: ((Intent) -> Unit)? = null

/**
 * Report reply: pick a reason, optionally add a note, then Report saves the report on this phone before opening an
 * email draft. Without an email app the saved report stays and the dialog shows the address to copy.
 */
@Composable
fun ReportReplyDialog(turnID: UUID, reply: String, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val clipboard = LocalClipboard.current
    val scope = rememberCoroutineScope()
    var reason by rememberSaveable { mutableStateOf<String?>(null) }
    var note by rememberSaveable { mutableStateOf("") }
    var noEmailApp by rememberSaveable { mutableStateOf(false) }
    var failed by rememberSaveable { mutableStateOf(false) }
    var saving by rememberSaveable { mutableStateOf(false) }
    val report = report@{
        val chosen = reason ?: return@report
        saving = true
        scope.launch {
            val saved = try {
                withContext(Dispatchers.IO) { CoachReports.save(context, turnID, chosen, note.trim()) }
                true
            } catch (_: Exception) {
                false
            }
            saving = false
            failed = !saved
            if (!saved) return@launch
            val intent = reportIntent(reply, chosen, note)
            try {
                startEmailForTest?.invoke(intent) ?: context.startActivity(intent)
                onDismiss()
            } catch (_: android.content.ActivityNotFoundException) {
                noEmailApp = true
            }
        }
        Unit
    }
    if (noEmailApp) AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Report saved") },
        text = { Text("Report saved on this phone. No email app was found, so send it to ${MivuLinks.REPORT_EMAIL}.") },
        confirmButton = { TextButton(onDismiss, Modifier.heightIn(min = 48.dp)) { Text("Done") } },
        dismissButton = {
            TextButton({ scope.launch { clipboard.setClipEntry(ClipEntry(ClipData.newPlainText("Mivu address", MivuLinks.REPORT_EMAIL))) } },
                Modifier.heightIn(min = 48.dp)) { Text("Copy address") }
        },
    ) else AlertDialog(
        onDismissRequest = onDismiss,
        icon = { Icon(painterResource(R.drawable.ic_flag), contentDescription = null) },
        title = { Text("Report this reply?") },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Mivu opens your email app with this reply so you can send it to us. Nothing else from your diary is included.")
                Column(Modifier.selectableGroup()) {
                    REPORT_REASONS.forEach { option ->
                        Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).selectable(option == reason, role = Role.RadioButton) { reason = option },
                            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            RadioButton(option == reason, onClick = null)
                            Text(option, style = MaterialTheme.typography.bodyLarge)
                        }
                    }
                }
                OutlinedTextField(note, { note = it }, Modifier.fillMaxWidth().testTag("reportNote"), label = { Text("Note (optional)") })
                if (failed) Text("Couldn't save this report. Try again.", color = MaterialTheme.colorScheme.error)
            }
        },
        confirmButton = { TextButton(report, Modifier.heightIn(min = 48.dp), enabled = reason != null && !saving) { Text("Report") } },
        dismissButton = { TextButton(onDismiss, Modifier.heightIn(min = 48.dp)) { Text("Cancel") } },
    )
}
