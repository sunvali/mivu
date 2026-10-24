package com.yakov103.mivu.ui

import android.content.Context
import androidx.activity.ComponentActivity
import androidx.compose.ui.test.assertTouchHeightIsEqualTo
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.assertTouchWidthIsEqualTo
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isHeading
import androidx.compose.ui.test.isSelectable
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.dp
import androidx.test.core.app.ApplicationProvider
import com.yakov103.mivu.diary.Bootstrap
import com.yakov103.mivu.diary.DiaryDatabase
import com.yakov103.mivu.diary.DiaryProfile
import com.yakov103.mivu.diary.DiaryRepository
import com.yakov103.mivu.ui.theme.MivuTheme
import java.io.File
import java.io.IOException
import java.util.UUID
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Rule
import org.junit.Test

class AppShellTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private val context: Context = ApplicationProvider.getApplicationContext()
    private var repository: DiaryRepository? = null

    @Before @After fun wipe() {
        (repository?.bootstrapState?.value as? Bootstrap.Ready)?.let { repository!!.database(it.profileID).close() }
        File(context.filesDir, "profiles").deleteRecursively()
        DiaryRepository.preferences(context).edit().clear().commit()
    }

    private fun launch(repository: DiaryRepository) {
        this.repository = repository
        compose.setContent { MivuTheme { MivuApp(repository) } }
    }

    private fun title(text: String) = compose.onNode(hasText(text) and isHeading())
    private fun tab(text: String) = compose.onNode(hasText(text) and isSelectable())
    private fun waitForTitle(text: String) =
        compose.waitUntil(10_000) { compose.onAllNodes(hasText(text) and isHeading()).fetchSemanticsNodes().isNotEmpty() }

    @Test fun freshInstallCreatesMyDiaryAndShowsToday() {
        launch(DiaryRepository(context))
        waitForTitle("Today")
        title("Today").assertIsDisplayed()
        listOf("Today", "Diary", "Progress", "Coach").forEach { tab(it).assertIsDisplayed() }
        tab("Today").assertIsSelected()
        val ready = repository!!.bootstrapState.value as Bootstrap.Ready
        assertEquals("My diary", repository!!.database(ready.profileID).head().profile.name)
    }

    @Test fun profileActionIsLabelled() {
        launch(DiaryRepository(context))
        waitForTitle("Today")
        compose.onNodeWithContentDescription("Profile and settings").assertIsDisplayed()
        compose.onNodeWithTag("profileSettings").assertTouchHeightIsEqualTo(48.dp).assertTouchWidthIsEqualTo(48.dp)
    }

    @Test fun bootstrapFailureOffersRetry() {
        launch(DiaryRepository(context, create = { _, _ -> throw IOException("synthetic") }))
        compose.waitUntil(10_000) { compose.onAllNodes(hasText("Couldn't create your diary")).fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText("Try again").assertIsDisplayed()
    }

    @Test fun missingSelectedDiaryAsksToChooseInsteadOfOpeningAnother() {
        val older = DiaryProfile(UUID.randomUUID(), "Diary A", "en", "UTC", "")
        val newer = DiaryProfile(UUID.randomUUID(), "Diary B", "en", "UTC", "")
        listOf(older, newer).forEach { DiaryDatabase.create(context, it).close() }
        val gone = UUID.randomUUID().toString()
        DiaryRepository.preferences(context).edit().putString("selectedProfile", gone).commit()
        launch(DiaryRepository(context))
        compose.waitUntil(10_000) { compose.onAllNodes(hasText("Choose a diary") and isHeading()).fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText("Diary B").assertIsDisplayed()
        assertEquals(gone, DiaryRepository.preferences(context).getString("selectedProfile", null))
        compose.onNodeWithText("Diary A").performClick()
        waitForTitle("Today")
        assertEquals(Bootstrap.Ready(older.id), repository!!.bootstrapState.value)
        assertEquals(older.id.toString(), DiaryRepository.preferences(context).getString("selectedProfile", null))
        repository!!.database(newer.id).close()
    }

    @Test fun backFromDiaryReturnsToToday() {
        launch(DiaryRepository(context))
        waitForTitle("Today")
        tab("Diary").performClick()
        waitForTitle("Diary")
        compose.onNodeWithText("Arrives in a later update").assertIsDisplayed()
        compose.runOnUiThread { compose.activity.onBackPressedDispatcher.onBackPressed() }
        waitForTitle("Today")
        tab("Today").assertIsSelected()
    }
}
