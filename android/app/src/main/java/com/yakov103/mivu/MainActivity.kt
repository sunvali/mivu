package com.yakov103.mivu

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.yakov103.mivu.ui.MivuApp
import com.yakov103.mivu.ui.theme.MivuTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        SampleMode.configure(intent)
        (application as MivuApplication).drainSampleAnalysis()
        enableEdgeToEdge()
        setContent { MivuTheme { MivuApp((application as MivuApplication).repository) } }
    }
}
