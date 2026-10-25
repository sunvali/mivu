package com.yakov103.mivu.coach

import android.app.job.JobParameters
import android.app.job.JobService
import com.yakov103.mivu.MivuApplication
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

/**
 * Keeps the process running while saved Coach turns finish after the app leaves the screen (iOS `continueInBackground`).
 * It shares the app's single-flight [CoachWorker], so it never runs a second copy of a turn the app is already running.
 */
class CoachJobService : JobService() {
    private var run: Job? = null

    override fun onStartJob(params: JobParameters): Boolean {
        val app = application as MivuApplication
        run = app.scope.launch {
            if (app.readyProfile() != null) app.drainCoach(retryWaiting = true).join()
            jobFinished(params, false)
        }
        return true
    }

    /**
     * Stops waiting, not the turn: the worker saves each state as it goes, and a rescheduled job or the next launch resumes it.
     * Shared turns still running get the saved note (iOS `onExpire`).
     */
    override fun onStopJob(params: JobParameters): Boolean {
        run?.cancel()
        run = null
        (application as MivuApplication).expireFollowed()
        return true
    }
}
