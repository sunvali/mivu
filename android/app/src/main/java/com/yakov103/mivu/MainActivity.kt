package com.yakov103.mivu

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.lifecycle.lifecycleScope
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
        app.drainSampleAnalysis()
        app.watchNetworkForCoach()
        enableEdgeToEdge()
        val coach = CoachHooks(
            drain = { app.drainCoach(retryWaiting = it) },
            connected = app.chatGPT.state.map { it.canInfer }.stateIn(lifecycleScope, SharingStarted.Eagerly, app.chatGPT.state.value.canInfer),
            activity = app.coachWorker.activity,
        )
        setContent { MivuTheme { MivuApp(app.repository, onMealCaptured = { app.drainSampleAnalysis() }, coach = coach, connection = app.chatGPT, appScope = app.scope) } }
    }

    override fun onStop() {
        super.onStop()
        val app = application as MivuApplication
        if (isChangingConfigurations) return // a rotation, not leaving the app
        // The process scope, so the check outlives an activity that is finishing.
        app.scope.launch { if (app.hasPendingWork()) app.scheduleBackgroundDrain() }
    }
}
