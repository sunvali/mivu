package com.yakov103.mivu

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.yakov103.mivu.ui.CoachHooks
import com.yakov103.mivu.ui.MivuApp
import com.yakov103.mivu.ui.theme.MivuTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        SampleMode.configure(intent)
        val app = application as MivuApplication
        app.drainSampleAnalysis()
        app.watchNetworkForCoach()
        enableEdgeToEdge()
        val coach = CoachHooks(
            drain = { app.drainCoach() },
            isConnected = { runCatching { app.credentials.registrations().isNotEmpty() }.getOrDefault(false) },
            activity = app.coachWorker.activity,
        )
        setContent { MivuTheme { MivuApp(app.repository, onMealCaptured = { app.drainSampleAnalysis() }, coach = coach) } }
    }
}
