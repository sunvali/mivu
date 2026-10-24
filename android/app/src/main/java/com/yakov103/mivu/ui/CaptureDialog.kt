package com.yakov103.mivu.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.DialogWindowProvider
import androidx.core.view.WindowCompat
import com.yakov103.mivu.R

/**
 * An M3 full-screen dialog for a capture draft: Close and Save in the top bar, a scrolling column, and "Discard changes?"
 * on Close or back while [dirty]. Nothing can leave while [saving].
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CaptureDialog(
    title: String,
    closeTag: String,
    saveTag: String,
    canSave: Boolean,
    saving: Boolean,
    dirty: Boolean,
    discardMessage: String,
    onClose: () -> Unit,
    onSave: () -> Unit,
    content: @Composable ColumnScope.() -> Unit,
) {
    var showDiscard by rememberSaveable { mutableStateOf(false) }
    val focus = LocalFocusManager.current
    val close = { focus.clearFocus(); if (dirty) showDiscard = true else onClose() }
    BackHandler { if (!saving) close() }
    // The dialog's own window draws behind the system bars: give them the app's light or dark icons.
    val view = LocalView.current
    val lightBars = MaterialTheme.colorScheme.background.luminance() > 0.5f
    SideEffect {
        (view.parent as? DialogWindowProvider)?.window?.let {
            WindowCompat.getInsetsController(it, view).run { isAppearanceLightStatusBars = lightBars; isAppearanceLightNavigationBars = lightBars }
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(title, Modifier.semantics { heading() }) },
                navigationIcon = {
                    IconButton(close, Modifier.testTag(closeTag), enabled = !saving) {
                        Icon(painterResource(R.drawable.ic_close), contentDescription = "Cancel")
                    }
                },
                actions = {
                    Button({ focus.clearFocus(); onSave() }, Modifier.padding(end = 8.dp).testTag(saveTag), enabled = canSave && !saving) {
                        // The label keeps its space under the spinner, so the button does not change size.
                        Box(contentAlignment = Alignment.Center) {
                            Text("Save", if (saving) Modifier.alpha(0f).clearAndSetSemantics {} else Modifier)
                            if (saving) CircularProgressIndicator(Modifier.size(18.dp).semantics { contentDescription = "Saving" }, strokeWidth = 2.dp)
                        }
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background),
            )
        },
        containerColor = MaterialTheme.colorScheme.background,
    ) { padding ->
        Column(
            Modifier.fillMaxSize().padding(padding).consumeWindowInsets(padding).imePadding()
                .verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
            content = content,
        )
    }

    if (showDiscard) {
        AlertDialog(
            onDismissRequest = { showDiscard = false },
            title = { Text("Discard changes?") },
            text = { Text(discardMessage) },
            confirmButton = {
                TextButton({ showDiscard = false; onClose() }) { Text("Discard changes", color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton({ showDiscard = false }) { Text("Keep editing") } },
        )
    }
}
