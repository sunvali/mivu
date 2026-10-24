package com.yakov103.mivu

import android.app.Activity
import android.app.Instrumentation
import android.content.Intent
import android.net.Uri
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.assertWidthIsAtLeast
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.dp
import androidx.test.espresso.intent.Intents
import androidx.test.espresso.intent.matcher.IntentMatchers.hasAction
import androidx.test.espresso.intent.rule.IntentsRule
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class ConnectionProofScreenTest {
    @get:Rule(order = 0) val intents = IntentsRule()
    @get:Rule(order = 1) val compose = createAndroidComposeRule<ConnectionProofActivity>()

    private val buttons = listOf("Sign in", "List models", "Analyze text", "Analyze photo", "Force refresh", "Run Coach turn", "Disconnect")

    @After fun stop() = ProofSession.cancelSignIn()

    @Test fun buttonsAreLabelledAndTouchSized() {
        buttons.forEach {
            compose.onNodeWithContentDescription(it).assertHeightIsAtLeast(48.dp).assertWidthIsAtLeast(48.dp)
        }
    }

    private val consented get() = (compose.activity.application as MivuApplication).chatGPT.state.value.consented

    // Consent is only ever the person's tap, so the test checks whichever state the device is in.
    @Test fun signInOpensTheBrowserWithALoopbackRedirectOnlyAfterConsent() {
        if (!consented) {
            compose.onNodeWithContentDescription("Sign in").performClick()
            compose.waitUntil(10_000) { ProofSession.results["Sign in"]?.ok == false }
            assertEquals("OpenAI sharing consent needed", ProofSession.results["Sign in"]?.text)
            assertTrue(Intents.getIntents().none { it.action == Intent.ACTION_VIEW })
            return
        }
        Intents.intending(hasAction(Intent.ACTION_VIEW)).respondWith(Instrumentation.ActivityResult(Activity.RESULT_CANCELED, null))
        compose.onNodeWithContentDescription("Sign in").performClick()
        compose.waitUntil(10_000) { Intents.getIntents().any { it.action == Intent.ACTION_VIEW } }
        val uri = Intents.getIntents().first { it.action == Intent.ACTION_VIEW }.data!!
        assertEquals("auth.openai.com", uri.host)
        assertEquals("/api/accounts/authorize", uri.path)
        val redirect = Uri.parse(uri.getQueryParameter("redirect_uri"))
        assertEquals("127.0.0.1", redirect.host)
        assertTrue(redirect.port > 0)
    }
}
