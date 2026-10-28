package com.yakov103.mivu.coach

import androidx.annotation.VisibleForTesting
import com.yakov103.mivu.MivuApplication
import com.yakov103.mivu.diary.CoachCaptureContext
import com.yakov103.mivu.diary.CoachSubmissionPayload
import com.yakov103.mivu.diary.DiaryDatabase
import com.yakov103.mivu.diary.DiaryError
import com.yakov103.mivu.diary.MealPhoto
import com.yakov103.mivu.diary.PhotoRole
import com.yakov103.mivu.diary.Reconciliation
import com.yakov103.mivu.diary.captureCoachSubmission
import com.yakov103.mivu.diary.reconcileCoachCapture
import java.io.File
import java.time.Instant
import java.time.temporal.ChronoUnit
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** iOS `TellCoachOutcome.dialog`, verbatim; `savedLocked` is not ported (the share sheet runs only on an unlocked phone). */
enum class TellCoachOutcome(val line: String) {
    Sent("Sent to the Coach."),
    SavedNeedsConnection("Saved. Open Mivu to connect the Coach."),
    SavedOpenToFinish("Saved. Pip will finish when you open Mivu."),
    NeedsSetup("Open Mivu to finish setup first."),
    Failed("I couldn't save that. Please try again."),
    ;

    val saved get() = this != Failed && this != NeedsSetup
}

/** iOS `TellCoach.run`: saves a message from outside the app into Coach history, without opening the app. */
object TellCoach {
    @VisibleForTesting internal var beforeCaptureForTest: (() -> Unit)? = null
    @VisibleForTesting internal var afterCaptureForTest: (() -> Unit)? = null
    /** Stands in for a connected ChatGPT account; tests cannot sign in. */
    @VisibleForTesting internal var canInferForTest: Boolean? = null

    /**
     * Saves [text] and [photos] (prepared JPEGs named by their photo ID) as one Coach turn with the ID [submissionID]. A retry
     * with the same ID never saves twice: a stored turn with that ID is this message, as its accepted identity is immutable.
     */
    suspend fun run(app: MivuApplication, text: String, photos: List<File>, submissionID: UUID, now: Instant = Instant.now()): TellCoachOutcome {
        if (text.isBlank() && photos.isEmpty()) return TellCoachOutcome.Failed
        val profileID = app.existingProfile() ?: return TellCoachOutcome.NeedsSetup
        try {
            withContext(Dispatchers.IO) { app.repository.database(profileID).save(text, photos, submissionID, now.truncatedTo(ChronoUnit.SECONDS)) }
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            return TellCoachOutcome.Failed
        }
        // On-device turns never run in the background or notify: they finish when Mivu opens.
        val onDevice = app.onDevice
        if (!onDevice) app.followReply(submissionID)
        app.restored.join() // as iOS `start` before reading canInfer: a cold start must not say "connect" to a connected account
        return when {
            !(canInferForTest ?: app.chatGPT.state.value.canInfer) -> TellCoachOutcome.SavedNeedsConnection
            onDevice -> TellCoachOutcome.SavedOpenToFinish
            else -> TellCoachOutcome.Sent
        }
    }

    private fun DiaryDatabase.save(text: String, photos: List<File>, id: UUID, at: Instant) {
        if (read { it.coachTurnWithoutPhotos(id) } != null) return // an earlier attempt committed
        // As CoachAttempt.payload: each photo's ID is its file name, created at the capture instant.
        val attachments = photos.map { MealPhoto(UUID.fromString(it.nameWithoutExtension), it.readBytes(), at, PhotoRole.unspecified) }
        for (round in 0..1) {
            val h = head()
            val payload = CoachSubmissionPayload(id, text, attachments,
                CoachCaptureContext(at, h.profile.timeZoneID, h.activeDayID, h.previousDayConfirmedAt, h.activeConversationSegmentID))
            try {
                beforeCaptureForTest?.invoke()
                captureCoachSubmission(payload, h.revision)
                afterCaptureForTest?.invoke()
                return
            } catch (e: DiaryError.StaleRevision) {
                if (round == 1) throw e // refused before writing: rebuild the context once
            } catch (e: Exception) {
                // The write may have committed before the throw: the same payload tells.
                if (runCatching { reconcileCoachCapture(payload) }.getOrNull() is Reconciliation.Accepted) return
                throw e
            }
        }
    }
}
