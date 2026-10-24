package com.yakov103.mivu.ui.meal

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.RadioButton
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
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
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import com.yakov103.mivu.diary.TrackingDay
import com.yakov103.mivu.ui.manual.SectionTitle
import com.yakov103.mivu.ui.manual.dayDate
import java.util.UUID

/** One page of waking days to move a meal to, newest first, and whether earlier ones exist. */
data class DestinationPage(val days: List<TrackingDay>, val hasEarlier: Boolean)

/** iOS `MoveMealSheet`: pick another waking day; nothing changes until Move. Failures show in [snackbar] inside the sheet. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun MoveMealSheet(
    currentDayID: UUID, saving: Boolean, snackbar: SnackbarHostState, load: suspend (Int) -> DestinationPage?, onDismiss: () -> Unit,
    onMove: (UUID) -> Unit,
) {
    var limit by rememberSaveable { mutableIntStateOf(30) }
    var destination by rememberSaveable { mutableStateOf(currentDayID.toString()) }
    var page by remember { mutableStateOf<DestinationPage?>(null) }
    LaunchedEffect(limit) { load(limit)?.let { page = it } }
    ModalBottomSheet(onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        SheetColumn {
            SheetTitle("Move meal")
            SectionTitle("Destination waking day")
            Surface(shape = MaterialTheme.shapes.large, color = MaterialTheme.colorScheme.surface) {
                Column(Modifier.fillMaxWidth().selectableGroup().testTag("moveMealDestination")) {
                    page?.days.orEmpty().sortedByDescending { it.startAt }.forEach { day ->
                        val selected = destination == day.id.toString()
                        Row(
                            Modifier.fillMaxWidth().heightIn(min = 56.dp)
                                .selectable(selected, role = Role.RadioButton) { destination = day.id.toString() }
                                .testTag("moveDay:${day.localDate}").padding(horizontal = 16.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                        ) {
                            RadioButton(selected, onClick = null)
                            val date = dayDate(day.localDate)
                            Text(if (day.id == currentDayID) "$date · Current day" else date, style = MaterialTheme.typography.bodyLarge)
                        }
                    }
                }
            }
            if (page?.hasEarlier == true) TextButton({ limit += 30 }, Modifier.heightIn(min = 48.dp).testTag("earlierDays")) { Text("Earlier days") }
            Text("Only this meal will move. The destination changes when you tap Move.", Modifier.padding(horizontal = 4.dp),
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            SheetActions(onDismiss) {
                Button({ onMove(UUID.fromString(destination)) }, Modifier.heightIn(min = 48.dp).testTag("confirmMoveMeal"),
                    enabled = destination != currentDayID.toString() && !saving) { Text("Move") }
            }
            SnackbarHost(snackbar)
        }
    }
}
