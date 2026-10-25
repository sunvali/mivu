package com.yakov103.mivu.ui.today

import android.content.Context
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.ViewModelStore
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import androidx.test.core.app.ApplicationProvider
import androidx.test.platform.app.InstrumentationRegistry
import com.yakov103.mivu.diary.DiaryRepository
import com.yakov103.mivu.diary.captureProjection
import com.yakov103.mivu.diary.startDay
import com.yakov103.mivu.pip.CompanionLastActive
import com.yakov103.mivu.pip.CompanionPose
import com.yakov103.mivu.pip.MotionPolicy.Playback
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/** Today's Pip moments, resolved by [TodayViewModel] over the synthetic fixture diary. */
class TodayCompanionTest {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val repository by lazy { DiaryRepository(context) }
    private val store = ViewModelStore()
    private val scope = CoroutineScope(Dispatchers.Main.immediate)
    private val trail = mutableListOf<CompanionPose>()
    private lateinit var profileID: UUID
    private lateinit var model: TodayViewModel

    @Before fun wipe() = TodayFixture.wipe(context)

    @After fun close() {
        scope.cancel()
        main { store.clear() }
        runCatching { repository.database(profileID).close() }
        TodayFixture.wipe(context)
    }

    private fun main(block: () -> Unit) = InstrumentationRegistry.getInstrumentation().runOnMainSync(block)

    private fun waitUntil(what: String, timeoutMs: Long = 10_000, condition: () -> Boolean) {
        val end = System.currentTimeMillis() + timeoutMs
        while (!condition()) {
            check(System.currentTimeMillis() < end) { "timed out waiting for $what; trail $trail" }
            Thread.sleep(20)
        }
    }

    private fun pose() = model.companion.value.pose

    private fun start(id: UUID) {
        profileID = id
        main {
            model = ViewModelProvider(store, viewModelFactory { initializer { TodayViewModel(repository, id, sampleMode = false) } })[TodayViewModel::class.java]
            // Every resolved pose, and a subscriber so [TodayViewModel.state] reads as it does on screen.
            scope.launch { model.companion.collect { trail += it.pose } }
            scope.launch { model.state.collect {} }
        }
    }

    /** Animated, with the greeting played out. */
    private fun greeted() {
        main { model.reportPlayback(Playback.Animated) }
        waitUntil("greeting") { pose() == CompanionPose.Greeting }
        waitUntil("rest after greeting") { pose() == CompanionPose.Resting }
    }

    private fun emptyDay(): UUID {
        val id = TodayFixture.diary(context)
        repository.database(id).let { it.startDay(Instant.now(), it.head().revision) }
        return id
    }

    private fun capture(): UUID {
        val db = repository.database(profileID)
        return db.captureProjection("Toast", emptyList(), reviewFirst = false, dayID = db.head().activeDayID!!, at = Instant.now(),
            expectedRevision = db.head().revision).id
    }

    @Test fun firstMealPlaysOnceAfterTheComposerReturns() {
        start(emptyDay())
        greeted()
        val meal = capture()
        trail.clear()
        // The composer covers Today while it saves; Today keeps the moment for its return.
        main { model.reportPlayback(Playback.Hidden); model.showReceipt(meal) }
        waitUntil("the meal on Today") { model.state.value?.meals?.any { it.id == meal } == true }
        main { model.reportPlayback(Playback.Animated) }
        waitUntil("first meal") { pose() == CompanionPose.FirstMealToday }
        val deadline = model.companion.value.nextDeadline
        assertNotNull(deadline)
        waitUntil("rest after first meal") { pose() == CompanionPose.Resting }
        assertFalse("no greeting after the composer closes: $trail", CompanionPose.Greeting in trail)
    }

    @Test fun secondMealIsSavedOnly() {
        start(TodayFixture.seed(context, photo = false))
        greeted()
        val meal = capture()
        trail.clear()
        main { model.showReceipt(meal) }
        assertEquals(CompanionPose.Saved, pose())
        waitUntil("the meal on Today") { model.state.value?.meals?.any { it.id == meal } == true }
        waitUntil("rest after saved") { pose() == CompanionPose.Resting }
        assertFalse("$trail", CompanionPose.FirstMealToday in trail)
    }

    @Test fun reviewedPlaysOncePerSubmission() {
        start(TodayFixture.seed(context, photo = false))
        greeted()
        val submission = UUID.randomUUID()
        main { model.receiveReviewed(submission) }
        assertEquals(CompanionPose.Reviewed, pose())
        waitUntil("rest after reviewed") { pose() == CompanionPose.Resting }
        main { model.receiveReviewed(submission) }
        assertEquals(CompanionPose.Resting, pose())
    }

    @Test fun foregroundOnALaterDayWelcomesBack() {
        start(TodayFixture.seed(context, photo = false))
        main { model.reportPlayback(Playback.Animated) }
        val before = System.currentTimeMillis()
        main { model.enterBackground() }
        val lastActive = CompanionLastActive(repository.preferences)
        val recorded = lastActive.at(profileID)
        assertTrue("leaving records last-active now: $recorded", recorded != null && recorded >= before)
        assertEquals(Playback.Hidden, model.companion.value.playback)
        // A day away: the stored time is yesterday's when the app comes back.
        lastActive.record(profileID, recorded!! - 86_400_000)
        main { model.enterForeground() }
        assertEquals(CompanionPose.WelcomeBack, pose())
    }

    @Test fun backgroundAndBackGreetsAgain() {
        start(TodayFixture.seed(context, photo = false))
        greeted()
        main { model.enterBackground(); model.enterForeground() }
        assertEquals(CompanionPose.Greeting, pose())
    }
}
