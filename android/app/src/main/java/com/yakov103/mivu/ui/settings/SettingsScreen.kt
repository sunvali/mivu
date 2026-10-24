package com.yakov103.mivu.ui.settings

import androidx.annotation.DrawableRes
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuAnchorType
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LargeTopAppBar
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.yakov103.mivu.R
import com.yakov103.mivu.connection.AccountState
import com.yakov103.mivu.connection.ConnectionState
import com.yakov103.mivu.ui.today.WhiteCard

/** iOS `SettingsView`, reduced to the rows Android can back: the Coach AI connection and Support. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(state: ConnectionState, onOpenConnection: () -> Unit, onBack: () -> Unit) {
    val scroll = TopAppBarDefaults.exitUntilCollapsedScrollBehavior()
    val uri = LocalUriHandler.current
    Scaffold(
        Modifier.nestedScroll(scroll.nestedScrollConnection),
        topBar = {
            LargeTopAppBar(
                title = { Text("Settings", Modifier.semantics { heading() }, fontWeight = FontWeight.Bold) },
                navigationIcon = { BackButton(onBack) },
                scrollBehavior = scroll,
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background),
            )
        },
        containerColor = MaterialTheme.colorScheme.background,
    ) { padding ->
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(padding).padding(horizontal = 16.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            GroupHeader("Setup")
            WhiteCard(onClick = onOpenConnection) {
                SettingsRow("Coach AI", R.drawable.ic_auto_awesome) {
                    Text(if (state.account == AccountState.connected) "ChatGPT" else "Connect ChatGPT",
                        style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            GroupHeader("Support")
            WhiteCard(onClick = { uri.openUri(MivuLinks.PRIVACY) }) {
                SettingsRow("Privacy Policy", R.drawable.ic_shield) {
                    Icon(painterResource(R.drawable.ic_open_in_new), contentDescription = null, Modifier.size(20.dp))
                }
            }
            Footnote("Calorie and nutrition figures are estimates, not medical advice. Check with a doctor or registered dietitian " +
                "before big changes to how you eat.")
        }
    }
}

/** iOS `SettingsView` connection section, without the Apple Intelligence provider picker. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ConnectionScreen(
    state: ConnectionState,
    onAgree: () -> Unit,
    onConnect: () -> Unit,
    onCancel: () -> Unit,
    onSelectModel: (String) -> Unit,
    onDisconnect: () -> Unit,
    onBack: () -> Unit,
) {
    val uri = LocalUriHandler.current
    val connected = state.account == AccountState.connected
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Coach AI", Modifier.semantics { heading() }) },
                navigationIcon = { BackButton(onBack) },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background),
            )
        },
        containerColor = MaterialTheme.colorScheme.background,
    ) { padding ->
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(padding).padding(horizontal = 16.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            WhiteCard {
                SettingsRow(if (connected) "ChatGPT connected" else "Connect for meal analysis",
                    if (connected) R.drawable.ic_check else R.drawable.ic_person, bold = true)
            }
            Footnote("Uses your ChatGPT Plus or Pro plan. Coach messages and photos you send are shared with OpenAI.")
            Footnote("Coach analysis uses your selected ChatGPT account's plan allowance when eligible and is subject to its usage " +
                "limits. Captures save locally without a connection.")
            state.notice?.let { notice ->
                Surface(Modifier.fillMaxWidth(), shape = RoundedCornerShape(16.dp), color = MaterialTheme.colorScheme.errorContainer) {
                    Text(notice.text, Modifier.padding(16.dp).semantics { liveRegion = LiveRegionMode.Polite },
                        style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onErrorContainer)
                }
            }
            if (state.isConnecting) {
                Row(Modifier.heightIn(min = 48.dp), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                    CircularProgressIndicator(Modifier.size(24.dp), strokeWidth = 3.dp)
                    Text("Connecting", style = MaterialTheme.typography.bodyLarge)
                }
                OutlinedButton(onCancel, Modifier.fillMaxWidth().heightIn(min = 48.dp)) { Text("Cancel connection") }
            } else {
                ChatGPTConnectButton(state, onAgree, onConnect, style = if (connected) ConnectStyle.Outlined else ConnectStyle.Filled)
            }
            if (state.models.isNotEmpty()) ModelPicker(state, onSelectModel)
            if (state.registrationID != null) {
                OutlinedButton(
                    onDisconnect, Modifier.fillMaxWidth().heightIn(min = 48.dp), enabled = !state.isDisconnecting,
                    colors = ButtonDefaults.outlinedButtonColors(contentColor = MaterialTheme.colorScheme.error),
                    border = BorderStroke(1.dp, MaterialTheme.colorScheme.error.copy(alpha = 0.5f)),
                ) { Text("Disconnect ChatGPT") }
            }
            TextButton({ uri.openUri(MivuLinks.USAGE) }, Modifier.heightIn(min = 48.dp)) {
                Icon(painterResource(R.drawable.ic_open_in_new), contentDescription = null, Modifier.size(18.dp))
                Text("Manage usage", Modifier.padding(start = 8.dp))
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ModelPicker(state: ConnectionState, onSelect: (String) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    ExposedDropdownMenuBox(expanded, onExpandedChange = { expanded = it }) {
        OutlinedTextField(
            value = state.models.firstOrNull { it.slug == state.selectedModel }?.displayName.orEmpty(),
            onValueChange = {},
            readOnly = true,
            singleLine = true,
            label = { Text("Account model") },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded) },
            modifier = Modifier.fillMaxWidth().menuAnchor(ExposedDropdownMenuAnchorType.PrimaryNotEditable),
        )
        ExposedDropdownMenu(expanded, onDismissRequest = { expanded = false }) {
            state.models.forEach { model ->
                DropdownMenuItem(text = { Text(model.displayName) }, onClick = { expanded = false; onSelect(model.slug) },
                    contentPadding = ExposedDropdownMenuDefaults.ItemContentPadding)
            }
        }
    }
}

@Composable
private fun BackButton(onBack: () -> Unit) {
    IconButton(onBack) { Icon(painterResource(R.drawable.ic_arrow_back), contentDescription = "Navigate up") }
}

@Composable
private fun GroupHeader(text: String) {
    Text(text, Modifier.padding(start = 4.dp, top = 8.dp).semantics { heading() },
        style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
}

@Composable
private fun Footnote(text: String) {
    Text(text, Modifier.padding(horizontal = 4.dp), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
}

@Composable
private fun SettingsRow(title: String, @DrawableRes icon: Int, bold: Boolean = false, trailing: (@Composable () -> Unit)? = null) {
    ListItem(
        headlineContent = { Text(title, fontWeight = if (bold) FontWeight.SemiBold else null) },
        modifier = Modifier.heightIn(min = 56.dp),
        leadingContent = {
            Box(Modifier.size(40.dp).background(MaterialTheme.colorScheme.primaryContainer, CircleShape), contentAlignment = Alignment.Center) {
                Icon(painterResource(icon), contentDescription = null, Modifier.size(20.dp), tint = MaterialTheme.colorScheme.onPrimaryContainer)
            }
        },
        trailingContent = trailing,
        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
    )
}
