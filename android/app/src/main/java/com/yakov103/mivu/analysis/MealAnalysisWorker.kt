package com.yakov103.mivu.analysis

import com.yakov103.mivu.diary.AnalysisOutput
import com.yakov103.mivu.diary.DiaryDatabase
import com.yakov103.mivu.diary.DiaryError
import com.yakov103.mivu.diary.DiaryRepository
import com.yakov103.mivu.diary.SubmissionState
import com.yakov103.mivu.diary.applyAnalysis
import com.yakov103.mivu.diary.prepareAnalysis
import com.yakov103.mivu.diary.setSubmissionState
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/**
 * Port of iOS `processPending`: drains pending meal submissions through prepare, analyze and apply.
 * Sample mode only, as iOS `processPending`; live meals are analyzed by the Coach.
 */
class MealAnalysisWorker(
    private val repository: DiaryRepository,
    private val analyzer: (AnalysisInput) -> AnalysisOutput,
) {
    private val single = Mutex()

    /**
     * Runs until nothing is pending, one drain at a time (a second caller waits, then finds nothing left). As in iOS, an
     * analyze or apply failure marks that submission `needsRetry` (a later drain retries it, rebased by prepare) and is
     * rethrown, so one bad submission cannot loop forever. A StaleRevision from a concurrent write is retried first.
     */
    suspend fun drain(profileID: UUID) = single.withLock {
        withContext(Dispatchers.IO) {
            val db = repository.database(profileID)
            while (true) {
                val (mealID, submissionID) = db.nextPendingMealSubmission() ?: return@withContext
                var attempt = 0
                while (true) {
                    attempt++
                    val input = try {
                        db.prepareAnalysis(mealID, submissionID)
                        db.analysisInput(mealID, submissionID)
                    } catch (e: DiaryError.StaleRevision) {
                        if (attempt < MAX_ATTEMPTS) continue else throw e
                    }
                    try {
                        db.applyAnalysis(analyzer(input))
                        break
                    } catch (e: CancellationException) {
                        throw e
                    } catch (e: DiaryError.StaleRevision) {
                        if (attempt < MAX_ATTEMPTS) continue
                        markNeedsRetry(db, mealID, submissionID); throw e
                    } catch (e: Exception) {
                        markNeedsRetry(db, mealID, submissionID); throw e
                    }
                }
            }
        }
    }

    // Only a still-analyzable submission is downgraded; a saved or cancelled one stays as it is.
    private fun markNeedsRetry(db: DiaryDatabase, mealID: UUID, submissionID: UUID) {
        runCatching {
            val state = db.read { it.meal(mealID) }?.submissions?.firstOrNull { it.id == submissionID }?.state
            if (state in RETRYABLE) db.setSubmissionState(mealID, submissionID, SubmissionState.needsRetry)
        }
    }

    private companion object {
        const val MAX_ATTEMPTS = 3
        val RETRYABLE = setOf(SubmissionState.captured, SubmissionState.waitingForConnection, SubmissionState.analyzing)
    }
}
