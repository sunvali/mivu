package com.yakov103.mivu

import android.app.Activity
import android.os.Bundle
import android.util.Log
import com.yakov103.mivu.diary.CoachCaptureContext
import com.yakov103.mivu.diary.CoachSubmissionPayload
import com.yakov103.mivu.diary.DiaryDatabase
import com.yakov103.mivu.diary.DiaryProfile
import com.yakov103.mivu.diary.captureCoachSubmission
import com.yakov103.mivu.diary.pendingCoachTurns
import java.io.File
import java.time.Instant
import java.util.UUID
import kotlin.concurrent.thread

/**
 * Debug-only process-kill probe for scripts/android/kill_capture_check.sh. Saves one synthetic capture and then
 * sleeps until killed; with `verify=true` it reopens the diary and logs only whether that capture survived.
 */
class CaptureProbeActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val verify = intent.getBooleanExtra("verify", false)
        thread {
            if (verify) {
                val present = runCatching { DiaryDatabase.open(this, PROFILE).use { SUBMISSION in it.pendingCoachTurns() } }
                    .getOrDefault(false)
                Log.i(TAG, "CAPTURE_PRESENT=${if (present) 1 else 0}")
            } else {
                File(filesDir, "profiles/${PROFILE.toString().uppercase()}").deleteRecursively()
                val db = DiaryDatabase.create(this, DiaryProfile(PROFILE, "Probe", "en", "UTC", ""))
                db.captureCoachSubmission(CoachSubmissionPayload(SUBMISSION, "synthetic probe", emptyList(),
                    CoachCaptureContext(Instant.now(), "UTC")), db.head().revision)
                Log.i(TAG, "CAPTURE_SAVED")
                Thread.sleep(60_000) // the script kills the process here, with the database still open
            }
        }
    }

    private companion object {
        const val TAG = "MivuCaptureProbe"
        val PROFILE: UUID = UUID.fromString("00000000-0000-4000-8000-00000000c0de")
        val SUBMISSION: UUID = UUID.fromString("00000000-0000-4000-8000-00000000c0df")
    }
}
