package com.yakov103.mivu

import android.app.Application
import com.yakov103.mivu.analysis.MealAnalysisWorker
import com.yakov103.mivu.analysis.SampleAnalyzer
import com.yakov103.mivu.diary.Bootstrap
import com.yakov103.mivu.diary.DiaryRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.filterIsInstance
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

class MivuApplication : Application() {
    val repository by lazy { DiaryRepository(this) }
    private val scope = CoroutineScope(SupervisorJob())
    val analysisWorker by lazy { MealAnalysisWorker(repository, SampleAnalyzer::analyze) }

    /** Finishes captured meals once the diary is ready; live analysis (milestone 5) replaces this. A failure stays needsRetry. */
    fun drainSampleAnalysis() {
        if (!SampleMode.enabled) return
        scope.launch {
            val ready = repository.bootstrapState.filterIsInstance<Bootstrap.Ready>().first()
            runCatching { analysisWorker.drain(ready.profileID) }
        }
    }
}
