package com.yakov103.mivu.ui.settings

import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.storage.StorageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts.CreateDocument
import androidx.activity.result.contract.ActivityResultContracts.OpenDocument
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.DateRangePicker
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuAnchorType
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberDateRangePickerState
import androidx.compose.foundation.layout.Row
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import com.yakov103.mivu.R
import com.yakov103.mivu.diary.DiaryArchive
import com.yakov103.mivu.diary.DiaryError
import com.yakov103.mivu.diary.DiaryRepository
import com.yakov103.mivu.diary.DiarySnapshot
import com.yakov103.mivu.diary.PhotoSpool
import com.yakov103.mivu.diary.exportArchive
import com.yakov103.mivu.diary.restore
import com.yakov103.mivu.report.DiaryReport
import com.yakov103.mivu.report.write
import com.yakov103.mivu.ui.today.WhiteCard
import java.io.File
import java.time.Instant
import java.time.ZoneOffset
import java.util.UUID
import kotlin.concurrent.thread
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

// Port of ios/Mivu/Diary/DiaryReportSettings.swift (mockup frame 12) and the archive part of DiaryBackupSettings.swift
// (milestone 8 mockup, "Backup & export: diary archive"). Folder backup is not ported yet.

private enum class ReportRange(val label: String) { Week("Last 7 days"), Month("Last 30 days"), All("All time"), Custom("Custom") }

/** Where the last prepared report waits for the target app; cleared when the next report is made. */
internal fun reportsDirectory(context: Context) = File(context.cacheDir, "reports")

/** Where a prepared archive waits for the Create document picker; deleted after the copy and on the next screen open. */
internal fun exportsDirectory(context: Context) = File(context.cacheDir, "exports")

fun archiveFileName(): String = "Mivu-private-diary.json"

private const val COULD_NOT_READ = "Could not read this diary archive. Your local diary is preserved."
// iOS DiaryError.staleArchive (DiaryModels.swift).
private const val STALE_ARCHIVE = "This backup conflicts with the diary or contains deleted meals. Keep both copies and choose how to recover."

/** A decoded archive waiting for "Restore diary"; [spool] holds its photo bytes until it is applied or cancelled. */
private class PendingRestore(val incoming: DiarySnapshot, val spool: PhotoSpool, val currentName: String)

/**
 * "Backup & export": the diary archive, then "Share a report". [repository] holds the diary of [profileID];
 * [onImported] selects a diary made from an archive of another profile. [snapshot] reads the diary of [profileID]; [currentProfile] is checked
 * after preparation, so a report for a diary that is no longer open is dropped rather than shared.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BackupExportScreen(
    profileID: UUID,
    repository: DiaryRepository,
    snapshot: suspend () -> DiarySnapshot,
    currentProfile: () -> UUID?,
    onBack: () -> Unit,
    onImported: (UUID) -> Unit = {},
    /** Runs a confirmed restore; the app passes a scope that outlives this screen so leaving never drops the result. */
    workScope: CoroutineScope = rememberCoroutineScope(),
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var range by rememberSaveable { mutableStateOf(ReportRange.Month) }
    var format by rememberSaveable { mutableStateOf(DiaryReport.Format.PDF) }
    var custom by rememberSaveable { mutableStateOf<Pair<Long, Long>?>(null) }
    var pickingDates by rememberSaveable { mutableStateOf(false) }
    var preparing by remember { mutableStateOf(false) }
    var failed by rememberSaveable { mutableStateOf(false) }
    val folder = remember { reportsDirectory(context) }
    val exports = remember { exportsDirectory(context) }
    var working by remember { mutableStateOf<String?>(null) }
    var exported by remember { mutableStateOf(false) }
    var archiveError by remember { mutableStateOf<String?>(null) }
    var pendingExport by rememberSaveable { mutableStateOf<String?>(null) }
    var pending by remember { mutableStateOf<PendingRestore?>(null) }

    // A file left by a picker that never returned (the process died) goes when the screen next opens.
    LaunchedEffect(Unit) { if (pendingExport == null) withContext(Dispatchers.IO) { exports.deleteRecursively() } }
    DisposableEffect(Unit) { onDispose { pending?.spool?.let { thread { it.close() } } } }

    val save = rememberLauncherForActivityResult(CreateDocument("application/json")) { uri ->
        val file = pendingExport?.let(::File)
        pendingExport = null
        scope.launch {
            try {
                if (uri != null && file != null) {
                    working = "Saving export"
                    withContext(Dispatchers.IO) {
                        context.contentResolver.openOutputStream(uri, "wt")!!.use { out -> file.inputStream().use { it.copyTo(out) } }
                    }
                    exported = true
                }
            } catch (error: Exception) {
                if (error is CancellationException) throw error
                archiveError = "Export was not saved. Your local diary is preserved."
            } finally {
                withContext(NonCancellable + Dispatchers.IO) { exports.deleteRecursively() }
                working = null
            }
        }
    }

    fun export() {
        working = "Preparing…"
        exported = false
        archiveError = null
        scope.launch {
            try {
                val file = withContext(Dispatchers.IO) {
                    val db = repository.database(profileID)
                    val dir = File(exports, UUID.randomUUID().toString()).apply { mkdirs() }
                    // iOS checkCapacity (available for important usage): the diary file five times over, plus journal room.
                    val storage = context.getSystemService(StorageManager::class.java)
                    if (storage.getAllocatableBytes(storage.getUuidForPath(dir)) < db.file.length() * 5 + 65_536) throw DiaryError.QuotaExceeded
                    val file = File(dir, "archive.json")
                    // A photo that changed during the encode (StaleRevision) restarts the export once.
                    try {
                        file.outputStream().buffered().use { db.exportArchive(it) }
                    } catch (_: DiaryError.StaleRevision) {
                        file.outputStream().buffered().use { db.exportArchive(it) }
                    }
                    file
                }
                if (currentProfile() != profileID) {
                    withContext(Dispatchers.IO) { exports.deleteRecursively() }
                    return@launch
                }
                pendingExport = file.path
                save.launch(archiveFileName())
            } catch (error: Exception) {
                if (error is CancellationException) throw error
                withContext(NonCancellable + Dispatchers.IO) { exports.deleteRecursively() }
                archiveError = "Could not prepare an export. Your local diary is preserved."
            } finally {
                working = null
            }
        }
    }

    val open = rememberLauncherForActivityResult(OpenDocument()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        working = "Reading archive"
        exported = false
        archiveError = null
        scope.launch {
            val spool = PhotoSpool(File(context.cacheDir, "archive-${UUID.randomUUID()}"))
            var kept = false
            try {
                val (incoming, otherLocal, currentName) = withContext(Dispatchers.IO) {
                    val incoming = context.contentResolver.openInputStream(uri)!!.buffered().use { DiaryArchive.decode(it, spool) }
                    Triple(incoming, incoming.profile.id != profileID && repository.hasDiary(incoming.profile.id),
                        repository.database(profileID).head().profile.name)
                }
                when {
                    currentProfile() != profileID -> Unit
                    otherLocal -> archiveError = "This archive belongs to another local profile. Select that profile before restoring."
                    else -> { pending = PendingRestore(incoming, spool, currentName); kept = true }
                }
            } catch (error: Exception) {
                if (error is CancellationException) throw error
                archiveError = COULD_NOT_READ
            } finally {
                if (!kept) withContext(NonCancellable + Dispatchers.IO) { spool.close() }
                working = null
            }
        }
    }

    fun restore(chosen: PendingRestore) {
        pending = null
        working = "Restoring diary"
        workScope.launch {
            try {
                // As iOS: a diary selected meanwhile is never the one replaced.
                if (currentProfile() != profileID) return@launch
                val imported = withContext(Dispatchers.IO) {
                    if (chosen.incoming.profile.id == profileID) {
                        repository.database(profileID).restore(chosen.incoming, chosen.spool); null
                    } else repository.importProfile(chosen.incoming, chosen.spool)
                }
                imported?.let(onImported)
            } catch (error: Exception) {
                if (error is CancellationException) throw error
                // A stale or resurrecting archive is refused and the diary is unchanged.
                archiveError = if (error is DiaryError.StaleArchive) STALE_ARCHIVE else COULD_NOT_READ
            } finally {
                withContext(NonCancellable + Dispatchers.IO) { chosen.spool.close() }
                working = null
            }
        }
    }

    fun share() {
        preparing = true
        failed = false
        val chosenRange = range
        val chosenFormat = format
        val picked = custom
        scope.launch {
            try {
                val files = withContext(Dispatchers.IO) {
                    val diary = snapshot()
                    val zone = diary.profile.timeZoneID
                    val (from, through) = when (chosenRange) {
                        ReportRange.Week -> DiaryReport.lastDays(7, Instant.now(), zone)
                        ReportRange.Month -> DiaryReport.lastDays(30, Instant.now(), zone)
                        ReportRange.All -> null to null
                        // The picker returns UTC midnights of calendar days, already date labels.
                        ReportRange.Custom -> picked?.let { (start, end) -> utcDate(start) to utcDate(end) } ?: (null to null)
                    }
                    // The target app reads the last report after Mivu resumes (iOS deletes on share completion), so it goes only now.
                    folder.deleteRecursively()
                    DiaryReport(diary, from, through).write(chosenFormat, File(folder, UUID.randomUUID().toString()))
                }
                val directory = files.first().parentFile!!
                if (currentProfile() != profileID) {
                    withContext(Dispatchers.IO) { directory.deleteRecursively() }
                    return@launch
                }
                context.startActivity(shareIntent(context, files, chosenFormat))
            } catch (error: Exception) {
                if (error is kotlinx.coroutines.CancellationException) throw error
                failed = true
            } finally {
                preparing = false
            }
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Backup & export", Modifier.semantics { heading() }) },
                navigationIcon = {
                    IconButton(onBack) { Icon(painterResource(R.drawable.ic_arrow_back), contentDescription = "Navigate up") }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background),
            )
        },
        containerColor = MaterialTheme.colorScheme.background,
    ) { padding ->
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(padding).padding(horizontal = 16.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            GroupHeader("Diary archive")
            WhiteCard {
                Column {
                    val busy = working != null
                    SettingsRow("Export diary and photos", R.drawable.ic_arrow_upward, onClick = (::export).takeUnless { busy },
                        trailing = { if (working == "Preparing…" || working == "Saving export") Progress(working!!) })
                    SettingsRow("Restore from diary archive", R.drawable.ic_history,
                        onClick = { open.launch(arrayOf("application/json", "application/octet-stream")) }.takeUnless { busy },
                        trailing = { if (working == "Reading archive" || working == "Restoring diary") Progress(working!!) })
                }
            }
            if (exported) {
                Row(Modifier.padding(horizontal = 4.dp).semantics(mergeDescendants = true) { liveRegion = LiveRegionMode.Polite },
                    verticalAlignment = Alignment.CenterVertically) {
                    Icon(painterResource(R.drawable.ic_check_circle), contentDescription = null, Modifier.size(18.dp),
                        tint = MaterialTheme.colorScheme.primary)
                    Text("Export saved", Modifier.padding(start = 8.dp), style = MaterialTheme.typography.bodyMedium)
                }
            }
            archiveError?.let {
                Text(it, Modifier.padding(horizontal = 4.dp).semantics { liveRegion = LiveRegionMode.Polite },
                    style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.error)
            }
            Footnote("One file with this diary and its photos. It can be restored in Mivu on iPhone or Android.")
            GroupHeader("Share a report")
            RangeMenu(range, custom) { if (it == ReportRange.Custom) pickingDates = true else range = it }
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().semantics { contentDescription = "Report format" }) {
                DiaryReport.Format.entries.forEachIndexed { index, option ->
                    SegmentedButton(format == option, { format = option }, SegmentedButtonDefaults.itemShape(index, 2),
                        Modifier.heightIn(min = 48.dp)) { Text(option.name) }
                }
            }
            Footnote(if (format == DiaryReport.Format.PDF) "A summary page with daily totals and weight, then every saved meal. Made for a doctor or dietitian."
                else "Three spreadsheet files: meals, daily totals against targets, and weigh-ins.")
            FilledTonalButton(::share, Modifier.fillMaxWidth().heightIn(min = 48.dp), enabled = !preparing) {
                if (preparing) {
                    CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                    Text("Preparing report", Modifier.padding(start = 8.dp))
                } else {
                    Icon(painterResource(R.drawable.ic_ios_share), contentDescription = null, Modifier.size(18.dp))
                    Text("Share report", Modifier.padding(start = 8.dp))
                }
            }
            if (failed) {
                Text("Could not prepare this report. Your local diary is preserved.", Modifier.semantics { liveRegion = LiveRegionMode.Polite },
                    style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.error)
            }
        }
    }

    pending?.let { p ->
        val name = p.incoming.profile.name
        val meals = p.incoming.meals.size
        AlertDialog(
            onDismissRequest = { pending = null; scope.launch(Dispatchers.IO) { p.spool.close() } },
            title = { Text("Restore $name?") },
            text = {
                Text(if (p.incoming.profile.id == profileID) "Replace ${p.currentName} with $name ($meals meals). Older or deleted records cannot overwrite newer changes."
                    else "Import $name ($meals meals) as a separate private local diary. The selected profile is preserved.")
            },
            confirmButton = {
                TextButton({ restore(p) }, Modifier.heightIn(min = 48.dp)) { Text("Restore diary", color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = {
                TextButton({ pending = null; scope.launch(Dispatchers.IO) { p.spool.close() } }, Modifier.heightIn(min = 48.dp)) { Text("Cancel") }
            },
        )
    }

    if (pickingDates) {
        val state = rememberDateRangePickerState(custom?.first, custom?.second)
        DatePickerDialog(
            onDismissRequest = { pickingDates = false },
            confirmButton = {
                TextButton({
                    pickingDates = false
                    custom = state.selectedStartDateMillis!! to (state.selectedEndDateMillis ?: state.selectedStartDateMillis!!)
                    range = ReportRange.Custom
                }, Modifier.heightIn(min = 48.dp), enabled = state.selectedStartDateMillis != null) { Text("OK") }
            },
            dismissButton = { TextButton({ pickingDates = false }, Modifier.heightIn(min = 48.dp)) { Text("Cancel") } },
        ) { DateRangePicker(state, Modifier.weight(1f)) }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun RangeMenu(range: ReportRange, custom: Pair<Long, Long>?, onSelect: (ReportRange) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    ExposedDropdownMenuBox(expanded, onExpandedChange = { expanded = it }) {
        OutlinedTextField(
            value = if (range == ReportRange.Custom && custom != null) "${utcDate(custom.first)} to ${utcDate(custom.second)}" else range.label,
            onValueChange = {},
            readOnly = true,
            singleLine = true,
            label = { Text("Range") },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded) },
            modifier = Modifier.fillMaxWidth().menuAnchor(ExposedDropdownMenuAnchorType.PrimaryNotEditable),
        )
        ExposedDropdownMenu(expanded, onDismissRequest = { expanded = false }) {
            ReportRange.entries.forEach { option ->
                DropdownMenuItem(text = { Text(option.label) }, onClick = { expanded = false; onSelect(option) },
                    contentPadding = ExposedDropdownMenuDefaults.ItemContentPadding)
            }
        }
    }
}

@Composable
private fun Progress(label: String) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
        Text(label, Modifier.padding(start = 8.dp), style = MaterialTheme.typography.bodyMedium)
    }
}

private fun utcDate(millis: Long): String = Instant.ofEpochMilli(millis).atZone(ZoneOffset.UTC).toLocalDate().toString()

private fun shareIntent(context: Context, files: List<File>, format: DiaryReport.Format): Intent {
    val uris = files.map { FileProvider.getUriForFile(context, "${context.packageName}.reports", it) }
    val target = if (uris.size == 1) Intent(Intent.ACTION_SEND).putExtra(Intent.EXTRA_STREAM, uris[0])
    else Intent(Intent.ACTION_SEND_MULTIPLE).putParcelableArrayListExtra(Intent.EXTRA_STREAM, ArrayList<Uri>(uris))
    target.type = if (format == DiaryReport.Format.PDF) "application/pdf" else "text/csv"
    target.clipData = ClipData.newRawUri(null, uris[0]).apply { uris.drop(1).forEach { addItem(ClipData.Item(it)) } }
    target.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    return Intent.createChooser(target, null).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
}
