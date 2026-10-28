package com.yakov103.mivu.connection

import com.yakov103.mivu.analysis.AvailableModel
import com.yakov103.mivu.analysis.LocalTurn
import com.yakov103.mivu.analysis.NutritionTable
import com.yakov103.mivu.analysis.OnDeviceModel
import com.yakov103.mivu.analysis.ResponsesClient
import com.yakov103.mivu.coach.CoachTools
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

    @Test fun storedOnDeviceWithoutNanoFallsBackToConnectedChatGPT() {
        val state = chatGPT.copy(storedProvider = CoachProvider.onDevice, nano = NanoStatus.downloadable)
        assertEquals(CoachProvider.chatGPT, state.provider)
        assertTrue(state.canInfer)
    }

    @Test fun storedOnDeviceWithoutNanoOrAccountCannotInfer() {
        val state = ConnectionState(storedProvider = CoachProvider.onDevice)
        assertEquals(CoachProvider.chatGPT, state.provider)
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
