package com.yakov103.mivu.connection

import com.google.mlkit.genai.common.GenAiException
import com.google.mlkit.genai.common.GenAiException.ErrorCode
import com.yakov103.mivu.analysis.AvailableModel
import com.yakov103.mivu.analysis.GeminiNano
import com.yakov103.mivu.analysis.LocalTurn
import com.yakov103.mivu.analysis.NutritionTable
import com.yakov103.mivu.analysis.OnDeviceModel
import com.yakov103.mivu.analysis.ResponsesClient
import com.yakov103.mivu.coach.CoachTools
import java.time.Duration
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Port of the iOS `appleAvailable` provider cases in `CoachConnectionTests`. */
class CoachProviderTest {
    private val chatGPT = ConnectionState(AccountState.connected, "synthetic-registration",
        listOf(AvailableModel("synthetic-model", "Synthetic")), "synthetic-model")

    @Test fun noAccountWithNanoIsOnDevice() {
        val state = ConnectionState(nano = NanoStatus.available)
        assertEquals(CoachProvider.onDevice, state.provider)
        assertTrue(state.canInfer)
        assertFalse(state.planAuthorized)
    }

    @Test fun restoringAccountStaysChatGPT() {
        // Before the saved session authorizes, a captured meal waits for ChatGPT rather than going on-device.
        val state = ConnectionState(registrationID = "synthetic-registration", nano = NanoStatus.available)
        assertEquals(CoachProvider.chatGPT, state.provider)
        assertFalse(state.canInfer)
    }

    @Test fun savedAccountStaysChatGPT() {
        val state = ConnectionState(savedRegistration = true, nano = NanoStatus.available)
        assertEquals(CoachProvider.chatGPT, state.provider)
        assertFalse(state.canInfer)
    }

    @Test fun savedAccountStaysChatGPTWhenRestoreIsSkippedOrFails() {
        val prefs = MemoryPreferences()
        prefs.edit().putString("selectedRegistrationID", "synthetic-missing-registration").apply()
        val skipped = connection(prefs).apply { onDeviceForTest = Fake; runBlocking { restore() } } // no consent
        assertEquals(CoachProvider.chatGPT, skipped.state.value.provider)
        prefs.edit().putBoolean("openAISharingConsent", true).apply()
        val failed = connection(prefs).apply { onDeviceForTest = Fake; runBlocking { restore() } } // nothing in the store
        assertNull(failed.state.value.registrationID)
        assertEquals(CoachProvider.chatGPT, failed.state.value.provider)
    }

    @Test fun connectedChatGPTStaysTheDefaultWhenNanoIsAvailable() {
        val state = chatGPT.copy(nano = NanoStatus.available)
        assertEquals(CoachProvider.chatGPT, state.provider)
        assertTrue(state.canInfer && state.tunesTargets)
    }

    @Test fun storedOnDeviceWithoutNanoNeverSwitchesToChatGPT() {
        // The person chose to keep meals on the phone; only they can choose to send them to OpenAI.
        val state = chatGPT.copy(storedProvider = CoachProvider.onDevice, nano = NanoStatus.unavailable, nanoKnown = true)
        assertEquals(CoachProvider.onDevice, state.provider)
        assertFalse(state.canInfer)
        assertTrue(state.nanoMissing)
    }

    @Test fun storedOnDeviceWaitsOnDeviceUntilTheNanoCheckReports() {
        val state = chatGPT.copy(storedProvider = CoachProvider.onDevice, savedRegistration = true)
        assertEquals(CoachProvider.onDevice, state.provider)
        assertFalse(state.canInfer)
    }

    @Test fun busyNanoCheckKeepsOnDeviceOverConnectedChatGPT() = runBlocking {
        val c = connection(MemoryPreferences()).apply { choose(CoachProvider.onDevice) }
        c.statusForTest = { GeminiNano.status { throw GenAiException(null, ErrorCode.BUSY, Duration.ZERO, 0, 4) } }
        c.refreshNano()!!.join()
        val state = c.state.value.copy(account = chatGPT.account, registrationID = chatGPT.registrationID,
            models = chatGPT.models, selectedModel = chatGPT.selectedModel)
        assertTrue(state.planAuthorized)
        assertEquals(CoachProvider.onDevice, state.provider)
        assertFalse(state.canInfer)
    }

    @Test fun failedNanoCheckKeepsTheStoredOnDeviceChoice() = runBlocking {
        val c = connection(MemoryPreferences()).apply { choose(CoachProvider.onDevice) }
        c.statusForTest = { null } // the check threw: nothing is known
        c.refreshNano()!!.join()
        assertEquals(CoachProvider.onDevice, c.state.value.provider)
        assertFalse(c.state.value.canInfer)
        assertFalse(c.state.value.nanoMissing)
        c.statusForTest = { NanoStatus.unavailable }
        c.refreshNano()!!.join()
        assertEquals(CoachProvider.onDevice, c.state.value.provider)
        assertTrue(c.state.value.nanoMissing)
    }

    @Test fun storedOnDeviceWithoutNanoOrAccountCannotInfer() {
        val state = ConnectionState(storedProvider = CoachProvider.onDevice, nanoKnown = true)
        assertEquals(CoachProvider.onDevice, state.provider)
        assertFalse(state.canInfer)
    }

    @Test fun storedOnDeviceWinsOverConnectedChatGPT() {
        val state = chatGPT.copy(storedProvider = CoachProvider.onDevice, nano = NanoStatus.available)
        assertEquals(CoachProvider.onDevice, state.provider)
        assertTrue(state.canInfer && state.planAuthorized)
        // The formula estimate beats the on-device model for daily targets.
        assertFalse(state.tunesTargets)
    }

    @Test fun storedChatGPTWinsOverNano() {
        val state = ConnectionState(storedProvider = CoachProvider.chatGPT, nano = NanoStatus.available)
        assertEquals(CoachProvider.chatGPT, state.provider)
        assertFalse(state.canInfer)
    }

    @Test fun choiceIsStoredByNameAndUnknownCountsAsUnset() {
        val prefs = MemoryPreferences()
        connection(prefs).choose(CoachProvider.onDevice)
        assertEquals("onDevice", prefs.getString("aiProvider", null))
        assertEquals(CoachProvider.onDevice, connection(prefs).state.value.storedProvider)
        prefs.edit().putString("aiProvider", "apple").apply()
        assertNull(connection(prefs).state.value.storedProvider)
    }

    @Test fun onDeviceWithoutNanoHasNoSession() {
        val prefs = MemoryPreferences()
        val c = connection(prefs).apply { choose(CoachProvider.onDevice) }
        val error = runBlocking { runCatching { c.inference()(emptyList(), CoachTools.declarations()) }.exceptionOrNull() }
        assertEquals(SessionError.NoActiveSession, error)
    }

    private object Fake : OnDeviceModel {
        override suspend fun turn(text: String, images: List<ByteArray>) = LocalTurn(LocalTurn.Intent.other)
        override suspend fun pick(phrase: String, options: List<NutritionTable.Food>) = 0
    }

    private fun connection(prefs: MemoryPreferences): ChatGPTConnection {
        val store = MemoryCredentialStore()
        return ChatGPTConnection(store, AuthSession(store), ResponsesClient(), prefs, CoroutineScope(Dispatchers.Unconfined))
    }
}
