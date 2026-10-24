package com.yakov103.mivu.analysis

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.yakov103.mivu.diary.*
import java.io.File
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test

class MealAnalysisWorkerTest {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val profile = DiaryProfile(UUID.randomUUID(), "Synthetic", "en", "UTC", "")
    private val at = Instant.parse("2026-10-24T12:00:00Z")
    private lateinit var db: DiaryDatabase
    private lateinit var repository: DiaryRepository
    private lateinit var day: TrackingDay

    @Before fun open() {
        File(context.filesDir, "profiles").deleteRecursively()
        DiaryDatabase.create(context, profile).close()
        repository = DiaryRepository(context)
        db = repository.database(profile.id)
        day = db.startDay(Instant.parse("2026-10-24T06:00:00Z"), db.head().revision)
    }

    @After fun close() {
        db.close()
        File(context.filesDir, "profiles").deleteRecursively()
    }

    private fun capture(text: String) = db.captureProjection(text, emptyList(), false, day.id, at, expectedRevision = db.head().revision)
    private fun worker() = MealAnalysisWorker(repository, SampleAnalyzer::analyze)

    @Test fun drainAppliesSampleToCapturedMeal() = runBlocking {
        val meal = capture("synthetic")
        worker().drain(profile.id)
        val saved = db.read { it.meal(meal.id) }!!
        assertEquals("Apple (sample)", saved.items.single().name)
        assertEquals(SubmissionState.saved, saved.submissions.single().state)
        assertNull(db.nextPendingMealSubmission())
    }

    @Test fun drainAfterReopenFinishesCapturedMeal() = runBlocking {
        val meal = capture("synthetic")
        db.close()
        repository = DiaryRepository(context)
        db = repository.database(profile.id)
        worker().drain(profile.id)
        assertEquals(SubmissionState.saved, db.read { it.meal(meal.id) }!!.submissions.single().state)
    }

    @Test fun drainSkipsCancelled() = runBlocking {
        val meal = capture("synthetic")
        val sub = meal.submissions.single()
        db.transaction(db.head().revision) { it.putMeal(meal.copy(submissions = listOf(sub.copy(state = SubmissionState.cancelled)))) }
        worker().drain(profile.id)
        assertEquals(emptyList<FoodItem>(), db.read { it.meal(meal.id) }!!.items)
    }
}
