package com.yakov103.mivu.ui.settings

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.text.format.DateFormat
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts.RequestPermission
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.selection.toggleable
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuAnchorType
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimePicker
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.edit
import com.yakov103.mivu.R
import com.yakov103.mivu.day.MorningReminder
import com.yakov103.mivu.diary.DayCutoff
import com.yakov103.mivu.diary.DiaryRepository
import com.yakov103.mivu.ui.today.WhiteCard
import java.util.Calendar
import java.util.Locale

// Port of ios/Mivu/Diary/DaySettingsSection.swift without the Live Activity rows (mockup frame 11).

/** "Your day": when a waking day starts, and the optional morning reminder (off until the person turns it on). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun DaySettings() {
    val context = LocalContext.current
    val prefs = remember { DiaryRepository.preferences(context) }
    var cutoff by remember { mutableIntStateOf(DayCutoff.hour) }
    var reminder by remember { mutableStateOf(prefs.getBoolean(MorningReminder.ENABLED, false)) }
    var minutes by remember { mutableIntStateOf(prefs.getInt(MorningReminder.MINUTES, 8 * 60)) }
    var denied by rememberSaveable { mutableStateOf(false) }
    var picking by rememberSaveable { mutableStateOf(false) }
    var choosingHour by remember { mutableStateOf(false) }
    val is24Hour = DateFormat.is24HourFormat(context)
    val hourLabel = { hour: Int ->
        val pattern = DateFormat.getBestDateTimePattern(Locale.getDefault(), if (is24Hour) "HH" else "ha")
        DateFormat.format(pattern, Calendar.getInstance().apply { set(Calendar.HOUR_OF_DAY, hour); set(Calendar.MINUTE, 0) }).toString()
    }

    fun setReminder(on: Boolean) {
        denied = on && !NotificationManagerCompat.from(context).areNotificationsEnabled()
        reminder = on && !denied
        prefs.edit { putBoolean(MorningReminder.ENABLED, reminder) }
        if (reminder) MorningReminder.schedule(context) else MorningReminder.cancel(context)
    }
    // Permission is asked only here, when the person turns the reminder on.
    val permission = rememberLauncherForActivityResult(RequestPermission()) { setReminder(it) }
    val turnOn = {
        if (Build.VERSION.SDK_INT >= 33 &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) permission.launch(Manifest.permission.POST_NOTIFICATIONS)
        else setReminder(true)
    }

    GroupHeader("Your day")
    WhiteCard {
        Column {
            ExposedDropdownMenuBox(choosingHour, onExpandedChange = { choosingHour = it }) {
                SettingsRow("Day starts at", R.drawable.ic_wb_twilight,
                    modifier = Modifier.menuAnchor(ExposedDropdownMenuAnchorType.PrimaryNotEditable).testTag("dayStartHour")) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(hourLabel(cutoff), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        ExposedDropdownMenuDefaults.TrailingIcon(choosingHour)
                    }
                }
                ExposedDropdownMenu(choosingHour, onDismissRequest = { choosingHour = false }) {
                    (0..8).forEach { hour ->
                        DropdownMenuItem({ Text(hourLabel(hour)) }, {
                            choosingHour = false
                            cutoff = hour
                            DayCutoff.set(prefs, hour)
                        }, contentPadding = ExposedDropdownMenuDefaults.ItemContentPadding)
                    }
                }
            }
            SettingsRow("Morning check-in", R.drawable.ic_notifications,
                modifier = Modifier.toggleable(reminder, role = Role.Switch) { if (it) turnOn() else setReminder(false) }
                    .testTag("morningReminder")) {
                Switch(reminder, onCheckedChange = null)
            }
            if (reminder) {
                SettingsRow("Reminder time", R.drawable.ic_schedule, onClick = { picking = true }) {
                    val time = Calendar.getInstance().apply { set(Calendar.HOUR_OF_DAY, minutes / 60); set(Calendar.MINUTE, minutes % 60) }
                    Text(DateFormat.getTimeFormat(context).format(time.time), style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.primary)
                }
            }
        }
    }
    Footnote(if (denied) "Notifications are off for Mivu. You can allow them in Android Settings."
        else "Food before ${hourLabel(cutoff)} still counts for the day before. A new day starts the first time you open Mivu after that.")

    if (picking) {
        val time = rememberTimePickerState(minutes / 60, minutes % 60, is24Hour)
        AlertDialog(
            onDismissRequest = { picking = false },
            title = { Text("Reminder time") },
            text = { TimePicker(time) },
            confirmButton = {
                TextButton({
                    picking = false
                    minutes = time.hour * 60 + time.minute
                    prefs.edit { putInt(MorningReminder.MINUTES, minutes) }
                    MorningReminder.schedule(context)
                }, Modifier.heightIn(min = 48.dp)) { Text("OK") }
            },
            dismissButton = { TextButton({ picking = false }, Modifier.heightIn(min = 48.dp)) { Text("Cancel") } },
        )
    }
}
