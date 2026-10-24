package com.yakov103.mivu.ui.settings

import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.net.Uri
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
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
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
import com.yakov103.mivu.diary.DiarySnapshot
import com.yakov103.mivu.report.DiaryReport
import com.yakov103.mivu.report.write
import java.io.File
import java.time.Instant
import java.time.ZoneOffset
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

// Port of ios/Mivu/Diary/DiaryReportSettings.swift (mockup frame 12). The archive export and import join this screen later.

private enum class ReportRange(val label: String) { Week("Last 7 days"), Month("Last 30 days"), All("All time"), Custom("Custom") }

/** Where the last prepared report waits for the target app; cleared when the next report is made. */
internal fun reportsDirectory(context: Context) = File(context.cacheDir, "reports")

/**
 * "Backup & export", with "Share a report" for now. [snapshot] reads the diary of [profileID]; [currentProfile] is checked
 * after preparation, so a report for a diary that is no longer open is dropped rather than shared.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BackupExportScreen(
    profileID: UUID,
    snapshot: suspend () -> DiarySnapshot,
    currentProfile: () -> UUID?,
    onBack: () -> Unit,
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
