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
import kotlinx.coroutines.withContext

/** Port of iOS `processPending`: drains pending meal submissions through prepare, analyze and apply. */
class MealAnalysisWorker(
    private val repository: DiaryRepository,
    private val analyzer: (AnalysisInput) -> AnalysisOutput,
) {
    /**
     * Runs until nothing is pending. As in iOS, a failure marks that submission `needsRetry` (a later drain retries it,
     * rebased by prepare) and is rethrown, so one bad submission cannot loop forever.
     */
    suspend fun drain(profileID: UUID) = withContext(Dispatchers.IO) {
        val db = repository.database(profileID)
        while (true) {
            val (mealID, submissionID) = db.nextPendingMealSubmission() ?: return@withContext
            try {
                db.prepareAnalysis(mealID, submissionID)
                db.applyAnalysis(analyzer(db.analysisInput(mealID, submissionID)))
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                // A deleted or cancelled submission has nothing to mark.
                runCatching { db.setSubmissionState(mealID, submissionID, SubmissionState.needsRetry) }
                throw e
            }
        }
    }
}
