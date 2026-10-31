package com.yakov103.mivu.ui.settings

import android.app.Activity
import android.app.Instrumentation.ActivityResult
import android.content.Intent
import android.net.Uri
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.espresso.intent.Intents
import androidx.test.espresso.intent.Intents.intended
import androidx.test.espresso.intent.Intents.intending
import androidx.test.espresso.intent.matcher.IntentMatchers.hasAction
import com.yakov103.mivu.diary.Bootstrap
import com.yakov103.mivu.diary.DayCompleteness
import com.yakov103.mivu.diary.DiaryArchive
import com.yakov103.mivu.diary.DiaryMeal
import com.yakov103.mivu.diary.DiaryProfile
import com.yakov103.mivu.diary.DiaryRepository
import com.yakov103.mivu.diary.DiarySnapshot
import com.yakov103.mivu.diary.MealPhoto
import com.yakov103.mivu.diary.MealSubmission
import com.yakov103.mivu.diary.PhotoRole
import com.yakov103.mivu.diary.SubmissionState
import com.yakov103.mivu.diary.TrackingDay
import com.yakov103.mivu.diary.deleteMeal
import com.yakov103.mivu.ui.theme.MivuTheme
import java.io.File
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test

/** Synthetic diaries only; the share sheet and the system file pickers are stubbed, so nothing leaves the device. */
class BackupExportScreenTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private val at = Instant.parse("2026-10-24T12:00:00Z")
    private val profile = DiaryProfile(UUID.randomUUID(), "Sample", "en", "UTC", "")
    private val diary = DiarySnapshot(1, 1, profile, emptyList(), emptyList(), emptyList(), deletedMealIDs = emptyList())
    private val folder get() = reportsDirectory(compose.activity)
    private val cache get() = compose.activity.cacheDir
    private val profiles = mutableListOf<UUID>()
    private val repository by lazy { DiaryRepository(compose.activity) }

    @Before fun stubChooser() {
        Intents.init()
        intending(hasAction(Intent.ACTION_CHOOSER)).respondWith(ActivityResult(Activity.RESULT_OK, null))
    }

    @After fun release() {
        Intents.release()
        profiles.forEach { File(compose.activity.filesDir, "profiles/${it.toString().uppercase()}").deleteRecursively() }
        cache.listFiles()!!.filter { it.name.startsWith("picked-") }.forEach { it.delete() }
    }

    private fun reportFiles() = folder.walkBottomUp().filter { it.isFile }.toList()
    private fun leftovers() = cache.list()!!.filter { it == "exports" || it.startsWith("archive-") }
    private fun exists(text: String) = compose.onAllNodesWithText(text, substring = true).fetchSemanticsNodes().isNotEmpty()
    private fun waitFor(text: String) = compose.waitUntil(15_000) { exists(text) }

    /** A diary with one synthetic meal and photo, saved as [owner]'s. */
    private fun mealDiary(owner: DiaryProfile = profile): DiarySnapshot {
        val day = TrackingDay(UUID.randomUUID(), "2026-10-24", "UTC", at, DayCompleteness.unknown)
        return DiarySnapshot(1, 3, owner, listOf(day), listOf(meal(day.id)), emptyList(), deletedMealIDs = emptyList(),
            lineage = listOf(UUID.randomUUID()))
    }

    private fun meal(dayID: UUID): DiaryMeal {
        val photo = MealPhoto(UUID.randomUUID(), byteArrayOf(7, 8, 9), at, PhotoRole.unspecified)
        val sub = MealSubmission(UUID.randomUUID(), 0, "synthetic soup", listOf(photo.id), false, SubmissionState.captured)
        return DiaryMeal(UUID.randomUUID(), dayID, at, at, 0, items = emptyList(), photos = listOf(photo), submissions = listOf(sub))
    }

    private fun saved(snapshot: DiarySnapshot) = repository.database(snapshot.profile.id).also {
        profiles += snapshot.profile.id
        it.replaceAll(snapshot)
    }

    /** One successor of [snapshot]: its lineage moves on, as a later copy of the same diary does. */
    private fun successor(snapshot: DiarySnapshot, change: (DiarySnapshot) -> DiarySnapshot) =
        change(snapshot).copy(revision = snapshot.revision + 1, lineage = snapshot.lineage!! + UUID.randomUUID())

    private fun picked(snapshot: DiarySnapshot? = null, bytes: ByteArray? = null): Uri {
        val file = File(cache, "picked-${UUID.randomUUID()}.json")
        if (snapshot != null) file.outputStream().use { DiaryArchive.encode(snapshot, it) } else file.writeBytes(bytes!!)
        intending(hasAction(Intent.ACTION_OPEN_DOCUMENT)).respondWith(ActivityResult(Activity.RESULT_OK, Intent().setData(Uri.fromFile(file))))
        return Uri.fromFile(file)
    }

    private fun screen(fontScale: Float? = null) {
        if (profile.id !in profiles) saved(mealDiary())
        compose.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, fontScale ?: density.fontScale)) {
                MivuTheme {
                    BackupExportScreen(profile.id, repository, { diary }, { profile.id }, onBack = {},
                        onImported = { runBlocking { repository.choose(it) } })
                }
            }
        }
    }

    private fun restore() { compose.onNodeWithText("Restore from diary archive").performScrollTo().performClick() }

    @Test fun shareLaunchesAChooserWithReadableUris() {
        screen()
        compose.onNodeWithText("CSV").performClick()
        compose.onNodeWithText("Share report").performScrollTo().performClick()
        compose.waitUntil(10_000) { Intents.getIntents().isNotEmpty() }
        intended(hasAction(Intent.ACTION_CHOOSER))
        val target = Intents.getIntents().single().getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)!!
        assertEquals(Intent.ACTION_SEND_MULTIPLE, target.action)
        assertTrue(target.flags and Intent.FLAG_GRANT_READ_URI_PERMISSION != 0)
        val uris = target.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)!!
        assertEquals(3, uris.size)
        uris.forEach { assertEquals("${compose.activity.packageName}.reports", it.authority) }
    }

    @Test fun reportStaysReadableUntilTheNextOne() {
        screen()
        compose.onNodeWithText("CSV").performClick()
        compose.onNodeWithText("Share report").performScrollTo().performClick()
        compose.waitUntil(10_000) { Intents.getIntents().size == 1 }
        // The stubbed chooser has returned; the target app may still read the files after Mivu resumes.
        compose.activityRule.scenario.recreate()
        compose.activityRule.scenario.onActivity {
            it.setContent { MivuTheme { BackupExportScreen(profile.id, repository, { diary }, { profile.id }, onBack = {}) } }
        }
        compose.waitForIdle()
        val first = reportFiles()
        assertEquals(3, first.size)
        compose.onNodeWithText("CSV").performClick()
        compose.onNodeWithText("Share report").performScrollTo().performClick()
        compose.waitUntil(10_000) { Intents.getIntents().size == 2 }
        assertEquals(3, reportFiles().size)
        assertTrue(first.none { it.exists() })
    }

    @Test fun profileChangeDuringPreparationDropsTheFiles() {
        val gate = CompletableDeferred<Unit>()
        var current: UUID? = profile.id
        compose.setContent { MivuTheme { BackupExportScreen(profile.id, repository, { gate.await(); diary }, { current }, onBack = {}) } }
        compose.onNodeWithText("Share report").performScrollTo().performClick()
        compose.waitUntil(5_000) { compose.onAllNodesWithText("Preparing report").fetchSemanticsNodes().isNotEmpty() }
        current = UUID.randomUUID()
        gate.complete(Unit)
        compose.waitUntil(5_000) { compose.onAllNodesWithText("Share report").fetchSemanticsNodes().isNotEmpty() }
        assertTrue(Intents.getIntents().isEmpty())
        assertTrue(reportFiles().isEmpty())
    }

    @Test fun exportWritesAnArchiveThatDecodes() {
        val stored = saved(mealDiary()).snapshot()
        val target = File(cache, "picked-${UUID.randomUUID()}.json")
        intending(hasAction(Intent.ACTION_CREATE_DOCUMENT)).respondWith(ActivityResult(Activity.RESULT_OK, Intent().setData(Uri.fromFile(target))))
        screen()
        compose.onNodeWithText("Export diary and photos").performScrollTo().performClick()
        waitFor("Export saved")
        val request = Intents.getIntents().single { it.action == Intent.ACTION_CREATE_DOCUMENT }
        assertEquals("Mivu-private-diary.json", request.getStringExtra(Intent.EXTRA_TITLE))
        assertEquals(stored, target.inputStream().use { DiaryArchive.decode(it) })
        compose.waitUntil(5_000) { leftovers().isEmpty() }
    }

    @Test fun cancelledExportSavesNothing() {
        intending(hasAction(Intent.ACTION_CREATE_DOCUMENT)).respondWith(ActivityResult(Activity.RESULT_CANCELED, null))
        screen()
        compose.onNodeWithText("Export diary and photos").performScrollTo().performClick()
        compose.waitUntil(15_000) { Intents.getIntents().any { it.action == Intent.ACTION_CREATE_DOCUMENT } }
        compose.waitUntil(15_000) { leftovers().isEmpty() }
        compose.waitForIdle()
        assertFalse(exists("Export saved"))
        assertFalse(exists("Export was not saved"))
    }

    @Test fun restoreAsksThenReplaces() {
        val db = saved(mealDiary())
        val stored = db.snapshot()
        screen()
        picked(stored)
        restore()
        waitFor("Restore Sample?")
        compose.onNodeWithText("Replace Sample with Sample (1 meals). Older or deleted records cannot overwrite newer changes.").assertExists()
        compose.onNodeWithText("Cancel").performClick()
        compose.waitUntil(5_000) { leftovers().isEmpty() }
        assertEquals(stored, db.snapshot())

        restore()
        waitFor("Restore Sample?")
        compose.onNodeWithText("Restore diary").performClick()
        compose.waitUntil(15_000) { db.snapshot().revision == stored.revision + 1 }
        assertEquals(stored.meals, db.snapshot().meals)
        compose.waitUntil(5_000) { leftovers().isEmpty() } // the spool goes after the commit
    }

    @Test fun successorReplacesTheDiary() {
        val db = saved(mealDiary())
        val stored = db.snapshot()
        val later = successor(stored) { it.copy(meals = it.meals + meal(it.days[0].id), deletedMealIDs = listOf(UUID.randomUUID())) }
        screen()
        picked(later)
        restore()
        waitFor("(2 meals)")
        compose.onNodeWithText("Restore diary").performClick()
        compose.waitUntil(15_000) { db.snapshot().meals.size == 2 }
        val restored = db.snapshot()
        assertEquals(later.meals, restored.meals)
        assertEquals(later.revision + 1, restored.revision)
        assertEquals(later.deletedMealIDs, restored.deletedMealIDs)
    }

    @Test fun staleArchiveLeavesTheDiaryUntouched() {
        val db = saved(mealDiary())
        val older = db.snapshot()
        db.replaceAll(successor(older) { it.copy(meals = it.meals + meal(it.days[0].id)) }) // the diary moved on
        val current = db.snapshot()
        screen()
        picked(older)
        restore()
        waitFor("Restore Sample?")
        compose.onNodeWithText("Restore diary").performClick()
        waitFor("This backup conflicts with the diary or contains deleted meals. Keep both copies and choose how to recover.")
        assertEquals(current, db.snapshot())
        compose.waitUntil(5_000) { leftovers().isEmpty() }
    }

    @Test fun deletedMealIsNotResurrected() {
        val db = saved(mealDiary())
        val withMeal = db.snapshot()
        db.deleteMeal(withMeal.meals[0].id, db.head().revision)
        val afterDelete = db.snapshot()
        // A successor of the current diary that brings the deleted meal back.
        val resurrecting = successor(afterDelete) { it.copy(meals = withMeal.meals, deletedMealIDs = emptyList()) }
        screen()
        picked(resurrecting)
        restore()
        waitFor("Restore Sample?")
        compose.onNodeWithText("Restore diary").performClick()
        waitFor("This backup conflicts with the diary or contains deleted meals. Keep both copies and choose how to recover.")
        assertEquals(afterDelete, db.snapshot())
    }

    @Test fun otherLocalProfileIsRefused() {
        val other = saved(mealDiary(DiaryProfile(UUID.randomUUID(), "Other", "en", "UTC", ""))).snapshot()
        screen()
        picked(other)
        restore()
        waitFor("This archive belongs to another local profile. Select that profile before restoring.")
        assertFalse(exists("Restore Other?"))
        compose.waitUntil(5_000) { leftovers().isEmpty() }
    }

    @Test fun newProfileImportsAndSwitches() {
        val incoming = mealDiary(DiaryProfile(UUID.randomUUID(), "Travel diary", "en", "UTC", ""))
        profiles += incoming.profile.id
        screen()
        picked(incoming)
        restore()
        waitFor("Restore Travel diary?")
        compose.onNodeWithText("Import Travel diary (1 meals) as a separate private local diary. The selected profile is preserved.").assertExists()
        compose.onNodeWithText("Restore diary").performClick()
        compose.waitUntil(15_000) { repository.bootstrapState.value == Bootstrap.Ready(incoming.profile.id) }
        assertEquals(incoming, repository.database(incoming.profile.id).snapshot())
        compose.waitUntil(5_000) { leftovers().isEmpty() }
    }

    // The import and the switch run on a scope that outlives the screen, so leaving mid-restore still selects the diary.
    @Test fun leavingDuringImportStillSwitches() {
        val incoming = mealDiary(DiaryProfile(UUID.randomUUID(), "Trip diary", "en", "UTC", ""))
        profiles += incoming.profile.id
        saved(mealDiary())
        val app = CoroutineScope(SupervisorJob() + Dispatchers.Main)
        var shown by mutableStateOf(true)
        compose.setContent {
            if (shown) MivuTheme {
                BackupExportScreen(profile.id, repository, { diary }, { profile.id }, onBack = {},
                    onImported = { app.launch { repository.choose(it) } }, workScope = app)
            }
        }
        picked(incoming)
        restore()
        waitFor("Restore Trip diary?")
        compose.onNodeWithText("Restore diary").performClick()
        shown = false
        compose.waitUntil(15_000) { repository.bootstrapState.value == Bootstrap.Ready(incoming.profile.id) }
        compose.waitUntil(5_000) { leftovers().isEmpty() }
        app.cancel()
    }

    @Test fun garbageFileSaysCouldNotRead() {
        screen()
        picked(bytes = "{\"format\":\"not-a-diary\"}".toByteArray())
        restore()
        waitFor("Could not read this diary archive. Your local diary is preserved.")
        assertFalse(exists("Restore diary"))
        compose.waitUntil(5_000) { leftovers().isEmpty() }
    }

    @Test fun rowsAre48dpAtFontScale2() {
        screen(fontScale = 2f)
        listOf("Export diary and photos", "Restore from diary archive", "Share report").forEach {
            val node = compose.onNode(hasText(it) and hasClickAction()).performScrollTo().fetchSemanticsNode()
            with(compose.density) { assertTrue("$it ${node.touchBoundsInRoot}", node.touchBoundsInRoot.height >= 48.dp.toPx() - 1) }
        }
    }
}
