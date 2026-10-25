package com.yakov103.mivu

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.lifecycle.lifecycleScope
import com.yakov103.mivu.quick.QuickAction
import com.yakov103.mivu.quick.receive
import com.yakov103.mivu.ui.CoachHooks
import com.yakov103.mivu.ui.MivuApp
import com.yakov103.mivu.ui.theme.MivuTheme
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        SampleMode.configure(intent)
        val app = application as MivuApplication
        // A restored activity (rotation, or a process death) already handled its intent: bring back only a request it had
        // not opened yet. Recents re-sends the original intent, which must not open the camera again.
        if (savedInstanceState != null) savedInstanceState.getString(PENDING_QUICK)?.let { name ->
            app.quickRequest.value = QuickAction.entries.firstOrNull { it.name == name }
        } else if (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY == 0) app.receive(intent)
        app.drainSampleAnalysis()
        app.watchNetworkForCoach()
        enableEdgeToEdge()
        val coach = CoachHooks(
            drain = { app.drainCoach(retryWaiting = it) },
            connected = app.chatGPT.state.map { it.canInfer }.stateIn(lifecycleScope, SharingStarted.Eagerly, app.chatGPT.state.value.canInfer),
            activity = app.coachWorker.activity,
        )
        setContent {
            MivuTheme {
                MivuApp(app.repository, onMealCaptured = { app.drainSampleAnalysis() }, coach = coach, connection = app.chatGPT,
                    appScope = app.scope, setupNewDiary = true, quickRequest = app.quickRequest)
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        (application as MivuApplication).receive(intent)
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        (application as MivuApplication).quickRequest.value?.let { outState.putString(PENDING_QUICK, it.name) }
    }

    override fun onStart() {
        super.onStart()
        val app = application as MivuApplication
        app.screenVisible = true
        app.rollOverDay()
    }

    override fun onStop() {
        super.onStop()
        val app = application as MivuApplication
        app.screenVisible = false
        if (isChangingConfigurations) return // a rotation, not leaving the app
        // The process scope, so the check outlives an activity that is finishing.
        app.scope.launch { if (app.hasPendingWork()) app.scheduleBackgroundDrain() }
    }

    private companion object {
        const val PENDING_QUICK = "pendingQuickAction"
    }
}
