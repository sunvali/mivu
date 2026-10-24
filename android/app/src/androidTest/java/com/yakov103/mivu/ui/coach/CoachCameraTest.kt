package com.yakov103.mivu.ui.coach

import android.Manifest
import android.app.Activity
import android.app.Instrumentation
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.net.Uri
import android.provider.MediaStore
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextReplacement
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModelProvider
import androidx.test.core.app.ApplicationProvider
import androidx.test.espresso.intent.Intents
import androidx.test.espresso.intent.Intents.intended
import androidx.test.espresso.intent.Intents.intending
import androidx.test.espresso.intent.matcher.IntentMatchers.hasAction
import androidx.test.platform.app.InstrumentationRegistry
import com.yakov103.mivu.coach.CoachActivity
import com.yakov103.mivu.diary.Bootstrap
import com.yakov103.mivu.diary.DiaryRepository
import com.yakov103.mivu.pip.MotionPolicy.Playback
import com.yakov103.mivu.ui.MivuApp
import com.yakov103.mivu.ui.composer.preparePhoto
import com.yakov103.mivu.ui.theme.MivuTheme
import com.yakov103.mivu.ui.today.TodayFixture
import java.io.File
import java.util.UUID
import kotlinx.coroutines.flow.MutableStateFlow
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Rule
import org.junit.Test

/** Synthetic diaries and images only. Capture runs on the emulator's virtual back camera (hw.camera.back=virtualscene). */
class CoachCameraTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private val context: Context = ApplicationProvider.getApplicationContext()
    private var repository: DiaryRepository? = null
    private val folder get() = File(context.cacheDir, "coach-camera-test")
    private lateinit var profileID: UUID

    @Before fun open() {
        TodayFixture.wipe(context)
        profileID = TodayFixture.diary(context)
        InstrumentationRegistry.getInstrumentation().uiAutomation.grantRuntimePermission(context.packageName, Manifest.permission.CAMERA)
    }

    @After fun close() {
        (repository?.bootstrapState?.value as? Bootstrap.Ready)?.let { repository!!.database(it.profileID).close() }
        folder.deleteRecursively()
        TodayFixture.wipe(context)
    }

    // Set as MainActivity does, so a recreated composition matches the saved one key for key.
    private val content = { activity: ComponentActivity -> activity.setContent { MivuTheme { MivuApp(repository!!) } } }

    private fun launchApp() {
        repository = DiaryRepository(context)
        compose.activityRule.scenario.onActivity(content)
        compose.waitUntil(10_000) { exists(hasText("Coach")) }
        compose.onNodeWithText("Coach").performClick()
        compose.waitUntil(10_000) { exists(hasTestTag("coachInput")) }
    }

    private fun exists(matcher: SemanticsMatcher) = compose.onAllNodes(matcher).fetchSemanticsNodes().isNotEmpty()

    private fun waitForText(text: String, timeout: Long = 15_000) =
        compose.waitUntil(timeout) { compose.onAllNodes(hasText(text, substring = true), useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty() }

    private fun openCamera() {
        compose.onNodeWithContentDescription("Add photos").performClick()
        compose.waitUntil(15_000) { exists(hasContentDescription("Take photo")) }
        // The virtual scene needs a moment before the shutter is ready.
        compose.waitUntil(15_000) { runCatching { compose.onNodeWithContentDescription("Take photo").assertIsEnabled() }.isSuccess }
    }

    private fun coachModel(): CoachViewModel {
        lateinit var model: CoachViewModel
        compose.activityRule.scenario.onActivity { model = ViewModelProvider(it)["coach-$profileID", CoachViewModel::class.java] }
        return model
    }

    @Test fun captureAddsPhotoAndStaysOpen() {
        launchApp()
        openCamera()
        compose.onNodeWithText("0 of 8 photos").assertIsDisplayed()
        compose.onNodeWithContentDescription("Take photo").performClick()
        waitForText("1 of 8 photos")
        compose.onNodeWithContentDescription("Take photo").assertIsDisplayed()
        compose.waitUntil(15_000) { runCatching { compose.onNodeWithContentDescription("Take photo").assertIsEnabled() }.isSuccess }
        assertEquals(1, coachModel().draft.value.photos.size)
        assert(File(coachModel().draft.value.photos.single()).length() > 0)
    }

    @Test fun closeReturnsToComposerWithDraft() {
        launchApp()
        compose.onNodeWithTag("coachInput").performTextReplacement("Synthetic snack")
        openCamera()
        // Coach is covered: Pip hides under the camera.
        compose.waitUntil(5_000) { coachModel().companion.value.playback == Playback.Hidden }
        compose.onNodeWithContentDescription("Take photo").performClick()
        waitForText("1 of 8 photos")
        compose.onNodeWithContentDescription("Close").performClick()
        compose.waitUntil(10_000) { exists(hasTestTag("coachInput")) }
        compose.onNodeWithText("Synthetic snack").assertIsDisplayed()
        compose.onNodeWithContentDescription("Attached photo 1").assertIsDisplayed()
        compose.onNodeWithContentDescription("Take photo").assertDoesNotExist()
    }

    @Test fun recreateMidCaptureKeepsDraft() {
        launchApp()
        compose.onNodeWithTag("coachInput").performTextReplacement("Synthetic supper")
        openCamera()
        compose.onNodeWithContentDescription("Take photo").performClick()
        waitForText("1 of 8 photos")
        compose.activityRule.scenario.recreate()
        compose.activityRule.scenario.onActivity(content)
        // The camera route and the draft both come back.
        waitForText("1 of 8 photos")
        compose.onNodeWithContentDescription("Take photo").assertIsDisplayed()
        assertEquals("Synthetic supper", coachModel().draft.value.text)
        assertEquals(1, coachModel().draft.value.photos.size)
    }

    @Test fun retakeModeLabelsShutterAndReturnsAfterOneShot() {
        launchApp()
        val picked = png("synthetic-retake.png")
        try {
            compose.runOnUiThread { coachModel().importPhotos(listOf(Uri.fromFile(picked))) }
            waitForText("1 of 8 photos")
        } finally {
            picked.delete()
        }
        val old = coachModel().draft.value.photos.single()
        compose.onNodeWithContentDescription("Retake photo 1").performClick()
        compose.waitUntil(15_000) { exists(hasContentDescription("Retake photo")) }
        compose.onNodeWithContentDescription("Take photo").assertDoesNotExist()
        compose.waitUntil(15_000) { runCatching { compose.onNodeWithContentDescription("Retake photo").assertIsEnabled() }.isSuccess }
        compose.onNodeWithContentDescription("Retake photo").performClick()
        // One shot replaces the photo and returns to the composer.
        compose.waitUntil(15_000) { coachModel().draft.value.photos.singleOrNull()?.let { it != old } == true }
        compose.waitUntil(10_000) { !exists(hasContentDescription("Retake photo")) && exists(hasTestTag("coachInput")) }
        assert(!File(old).exists())
    }

    private fun png(name: String) = File(context.cacheDir, name).apply {
        val bitmap = Bitmap.createBitmap(64, 64, Bitmap.Config.ARGB_8888)
        Canvas(bitmap).drawColor(Color.rgb(60, 140, 70))
        outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }

    private fun pick(count: Int, action: () -> Unit) {
        val picked = (1..count).map { png("synthetic-camera-$it.png") }
        Intents.init()
        try {
            val clip = ClipData.newRawUri(null, Uri.fromFile(picked[0])).apply { picked.drop(1).forEach { addItem(ClipData.Item(Uri.fromFile(it))) } }
            intending(hasAction(MediaStore.ACTION_PICK_IMAGES))
                .respondWith(Instrumentation.ActivityResult(Activity.RESULT_OK, Intent().apply { clipData = clip }))
            action()
            waitForText("$count of 8 photos")
            intended(hasAction(MediaStore.ACTION_PICK_IMAGES))
        } finally {
            Intents.release()
            picked.forEach { it.delete() }
        }
    }

    @Test fun fullDraftDisablesShutter() {
        launchApp()
        openCamera()
        pick(8) { compose.onNodeWithText("Choose photos").performClick() }
        compose.onNodeWithContentDescription("Take photo").assertIsNotEnabled()
        compose.onNodeWithText("Choose photos").assertIsNotEnabled()
    }

    @Test fun deniedKeepsDraftAndOffersChoosePhotos() {
        val repository = DiaryRepository(context).also { repository = it }
        val model = CoachViewModel(repository, profileID, drain = {}, isConnected = { false },
            activity = MutableStateFlow<Pair<UUID, CoachActivity>?>(null), saved = SavedStateHandle(),
            prepare = { preparePhoto(context.contentResolver, it, folder) })
        compose.runOnUiThread { model.updateText("Synthetic salad") }
        var closed = false
        compose.setContent { MivuTheme { CoachCameraScreen(model, permission = CameraPermission.PermanentlyDenied, onClose = { closed = true }) } }
        compose.onNodeWithText("Allow camera access in Settings, or choose photos.").assertIsDisplayed()
        compose.onNodeWithContentDescription("Take photo").assertDoesNotExist()
        Intents.init()
        try {
            intending(hasAction(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)).respondWith(Instrumentation.ActivityResult(Activity.RESULT_CANCELED, null))
            compose.onNodeWithText("Open Settings").performClick()
            intended(hasAction(Settings.ACTION_APPLICATION_DETAILS_SETTINGS))
        } finally {
            Intents.release()
        }
        pick(2) { compose.onNodeWithText("Choose photos").performClick() }
        assertEquals("Synthetic salad", model.draft.value.text)
        assertEquals(2, model.draft.value.photos.size)
        compose.onNodeWithContentDescription("Close").performClick()
        assert(closed)
    }
}
