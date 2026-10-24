package com.yakov103.mivu.ui.composer

import android.app.Activity
import android.app.Instrumentation
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.net.Uri
import android.provider.MediaStore
import androidx.activity.ComponentActivity
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextReplacement
import androidx.test.core.app.ApplicationProvider
import androidx.test.espresso.intent.Intents
import androidx.test.espresso.intent.Intents.intending
import androidx.test.espresso.intent.matcher.IntentMatchers.hasAction
import com.yakov103.mivu.SampleMode
import com.yakov103.mivu.analysis.MealAnalysisWorker
import com.yakov103.mivu.analysis.SampleAnalyzer
import com.yakov103.mivu.diary.Bootstrap
import com.yakov103.mivu.diary.DiaryMeal
import com.yakov103.mivu.diary.DiaryRepository
import com.yakov103.mivu.diary.SubmissionState
import com.yakov103.mivu.ui.MivuApp
import com.yakov103.mivu.ui.theme.MivuTheme
import com.yakov103.mivu.ui.today.TodayFixture
import java.io.File
import java.util.UUID
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test

class MealComposerScreenTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private val context: Context = ApplicationProvider.getApplicationContext()
    private var repository: DiaryRepository? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    @Before fun setUp() {
        TodayFixture.wipe(context)
        SampleMode.configure(Intent().putExtra("sampleMode", true))
    }

    @After fun tearDown() {
        scope.cancel()
        SampleMode.reset()
        (repository?.bootstrapState?.value as? Bootstrap.Ready)?.let { repository!!.database(it.profileID).close() }
        TodayFixture.wipe(context)
    }

    /** Launches the app as MainActivity does, draining sample analysis after each save on a scope outside the screen. */
    private fun launch(): DiaryRepository {
        val repository = DiaryRepository(context).also { repository = it }
        val worker = MealAnalysisWorker(repository, SampleAnalyzer::analyze)
        compose.setContent { MivuTheme { MivuApp(repository, onMealCaptured = { id -> scope.launch { worker.drain(id) } }) } }
        return repository
    }

    private fun waitFor(tag: String) =
        compose.waitUntil(10_000) { compose.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty() }
    private fun waitGone(tag: String) = compose.waitUntil(10_000) { compose.onAllNodesWithTag(tag).fetchSemanticsNodes().isEmpty() }
    private fun waitForText(text: String) = compose.waitUntil(10_000) {
        compose.onAllNodes(hasText(text, substring = true), useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()
    }

    private fun openComposer() {
        waitFor("logMeal")
        compose.onNodeWithTag("logMeal").performClick()
        waitFor("mealText")
    }

    private fun meals(repository: DiaryRepository, profileID: UUID): List<DiaryMeal> =
        repository.database(profileID).read { tx -> tx.head.activeDayID?.let(tx::dayMeals).orEmpty() }

    @Test fun textOnlySaveShowsSampleAppleOnToday() {
        val id = TodayFixture.diary(context) // no day yet: saving starts one
        val repository = launch()
        openComposer()
        compose.onNodeWithTag("mealText").performTextReplacement("Synthetic apple snack")
        compose.onNodeWithTag("sendMeal").performClick()
        waitGone("mealText")
        waitForText("Apple (sample)")
        val meal = meals(repository, id).single()
        assertEquals(SubmissionState.saved, meal.submissions.single().state)
        assertEquals("Synthetic apple snack", meal.submissions.single().text)
        assertTrue(meal.photos.isEmpty())
    }

    @Test fun emptySaveDisabled() {
        TodayFixture.diary(context)
        launch()
        openComposer()
        compose.onNodeWithTag("sendMeal").assertIsNotEnabled()
        compose.onNodeWithTag("mealText").performTextReplacement("   \n ")
        compose.onNodeWithTag("sendMeal").assertIsNotEnabled()
        compose.onNodeWithTag("mealText").performTextReplacement("Tea")
        compose.onNodeWithTag("sendMeal").assertIsEnabled()
    }

    @Test fun reviewFirstShowsAwaitingReview() {
        val id = TodayFixture.diary(context)
        val repository = launch()
        openComposer()
        compose.onNodeWithTag("mealText").performTextReplacement("Synthetic review snack")
        compose.onNodeWithTag("reviewFirst").performScrollTo().performClick()
        compose.onNodeWithTag("sendMeal").performClick()
        waitGone("mealText")
        waitForText("Awaiting review")
        assertTrue(meals(repository, id).single().submissions.single().reviewFirst)
    }

    @Test fun photoPickerResultSaved() {
        val id = TodayFixture.diary(context)
        val repository = launch()
        // A drawn 3000×1500 plate in the app cache: the stubbed picker returns it, the composer must shrink it to 2048 px.
        val picked = File(context.cacheDir, "synthetic-plate.jpg").apply {
            val bitmap = Bitmap.createBitmap(3000, 1500, Bitmap.Config.ARGB_8888)
            Canvas(bitmap).drawColor(Color.rgb(196, 48, 43))
            outputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, 90, it) }
        }
        Intents.init()
        try {
            val result = Intent().apply { clipData = ClipData.newRawUri(null, Uri.fromFile(picked)) }
            intending(hasAction(MediaStore.ACTION_PICK_IMAGES)).respondWith(Instrumentation.ActivityResult(Activity.RESULT_OK, result))
            openComposer()
            compose.onNodeWithTag("pickPhotos").performScrollTo().performClick()
            compose.waitUntil(10_000) {
                compose.onAllNodesWithContentDescription("Attached meal photo 1").fetchSemanticsNodes().isNotEmpty()
            }
        } finally {
            Intents.release()
            picked.delete()
        }
        compose.onNodeWithContentDescription("Remove photo 1").assertIsDisplayed()
        compose.onNodeWithTag("sendMeal").performClick()
        waitGone("mealText")
        waitForText("Apple (sample)")
        val meal = meals(repository, id).single()
        val bytes = repository.database(id).photoBytes(meal.id, meal.photos.single().id)!!
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        assertEquals("image/jpeg", bounds.outMimeType)
        assertEquals(2048, bounds.outWidth)
        assertEquals(1024, bounds.outHeight)
        assertTrue(File(context.cacheDir, "composer").listFiles().isNullOrEmpty()) // the draft's copies are gone
    }
}
