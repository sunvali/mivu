package com.yakov103.mivu.ui.settings

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.browser.customtabs.CustomTabsIntent
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import com.yakov103.mivu.R
import com.yakov103.mivu.connection.ConnectionState

object MivuLinks {
    const val PRIVACY = "https://mivuapp.com/privacy"
    const val USAGE = "https://chatgpt.com/settings/usage"
}

/** Opens [url] in a Custom Tab: the system browser, as the sign-in requires. A new task, so any context (the app's) works. */
fun Context.openCustomTab(url: String) =
    CustomTabsIntent.Builder().build().apply { intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }.launchUrl(this, Uri.parse(url))

enum class ConnectStyle { Filled, Outlined, Link }

/** iOS `ChatGPTConnectButton`: the one way to start a ChatGPT connection, sharing consent first, then sign-in. */
@Composable
fun ChatGPTConnectButton(
    state: ConnectionState,
    onAgree: () -> Unit,
    onConnect: () -> Unit,
    title: String = state.buttonTitle,
    style: ConnectStyle = ConnectStyle.Filled,
) {
    var askConsent by rememberSaveable { mutableStateOf(false) }
    val onClick = { if (state.consented) onConnect() else askConsent = true }
    val enabled = !state.isConnecting && !state.isDisconnecting
    val modifier = Modifier.heightIn(min = 48.dp).testTag("connectChatGPT")
    when (style) {
        ConnectStyle.Filled -> Button(onClick, modifier.fillMaxWidth(), enabled) { Text(title) }
        ConnectStyle.Outlined -> OutlinedButton(onClick, modifier.fillMaxWidth(), enabled,
            colors = ButtonDefaults.outlinedButtonColors(contentColor = MaterialTheme.colorScheme.primary)) { Text(title) }
        ConnectStyle.Link -> TextButton(onClick, modifier, enabled) { Text(title) }
    }
    if (askConsent) OpenAIConsent(onAgree = { askConsent = false; onAgree(); onConnect() }, onDismiss = { askConsent = false })
}

/** iOS `openAIConsent` (App Review 5.1.2(i)): names OpenAI and the data before anything is shared with it. */
@Composable
private fun OpenAIConsent(onAgree: () -> Unit, onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        icon = { Icon(painterResource(R.drawable.ic_shield), contentDescription = null) },
        title = { Text("Share with OpenAI?") },
        // The iOS USDA sentence is dropped until Android has a nutrition source.
        text = {
            Text("To estimate nutrition and answer Coach, Mivu sends OpenAI, through your ChatGPT account, what you record: meals, " +
                "photos, messages, weights, workouts, goals and profile details. Your diary stays on this phone, and you can " +
                "disconnect any time in Settings.")
        },
        confirmButton = { TextButton(onAgree, Modifier.heightIn(min = 48.dp)) { Text("Agree and Continue") } },
        dismissButton = { TextButton(onDismiss, Modifier.heightIn(min = 48.dp)) { Text("Not Now") } },
    )
}
