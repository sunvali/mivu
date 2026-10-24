package com.yakov103.mivu.connection

import java.net.URI
import java.net.URLDecoder
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Test

class OAuthAttemptTest {
    private val callback = "http://127.0.0.1:1455/auth/callback"

    private fun make(client: String? = null, consent: Boolean = false) =
        OAuthAttempt.make("host", client, callback, consent)

    private fun query(a: OAuthAttempt): Map<String, String> =
        URI(a.authorizationUrl).rawQuery.split("&").associate {
            val (k, v) = it.split("=", limit = 2)
            k to URLDecoder.decode(v, "UTF-8")
        }

    @Test fun challengeMatchesRfc7636Vector() {
        assertEquals(
            "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM",
            challenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
        )
    }

    @Test fun firstRegistrationUrl() {
        val q = query(make())
        assertEquals("dynamic_agent_client", q["client_id"])
        assertEquals("Mivu", q["agent_name_hint"])
        assertEquals("openid profile email offline_access resource.invoke chatgpt.tokens.use.direct", q["scope"])
        assertEquals("https://api.openai.com/v1", q["resource"])
        assertEquals("S256", q["code_challenge_method"])
        assertEquals(callback, q["redirect_uri"])
        assertFalse(q.containsKey("prompt"))
    }

    @Test fun reauthorizationHasNoAgentNameHint() {
        val q = query(make("oaiapp_x"))
        assertEquals("oaiapp_x", q["client_id"])
        assertFalse(q.containsKey("agent_name_hint"))
    }

    @Test fun planConsentAddsPrompt() {
        assertEquals("consent", query(make(consent = true))["prompt"])
    }

    @Test fun rejectsInvalidRedirects() {
        listOf(
            "http://localhost:1455/auth/callback",
            "https://127.0.0.1:1455/auth/callback",
            "http://127.0.0.1:1455/callback",
            "http://127.0.0.1:1455/auth/callback?x=1",
            "http://127.0.0.1/auth/callback",
            "http://u:p@127.0.0.1:1455/auth/callback",
            "http://127.0.0.1:1455/auth/callback#f",
        ).forEach { r ->
            assertThrows(r, OAuthError.InvalidRedirect::class.java) { OAuthAttempt.make("host", null, r) }
        }
    }

    @Test fun rejectsInvalidRegistration() {
        listOf("dynamic_agent_client", "").forEach { c ->
            assertThrows(OAuthError.InvalidRegistration::class.java) { make(c) }
        }
    }

    @Test fun callbackWithWrongStateIsInvalid() {
        assertThrows(OAuthError.InvalidCallback::class.java) { make().consumeCallback("$callback?state=x&code=c&client_id=oaiapp_x") }
    }

    @Test fun deniedAndProviderErrors() {
        val a = make()
        assertThrows(OAuthError.Denied::class.java) { a.consumeCallback("$callback?state=${a.state}&error=access_denied") }
        val b = make()
        assertThrows(OAuthError.ProviderError::class.java) { b.consumeCallback("$callback?state=${b.state}&error=server_error") }
    }

    @Test fun validCallbackReturnsCodeAndCallbackClient() {
        val a = make()
        val r = a.consumeCallback("$callback?state=${a.state}&code=abc&client_id=oaiapp_x")
        assertEquals(AuthorizationCode("abc", "oaiapp_x", callback), r)
        assertThrows(OAuthError.AlreadyConsumed::class.java) { a.consumeCallback("$callback?state=${a.state}&code=abc&client_id=oaiapp_x") }
    }

    @Test fun callbackClientFallsBackAndRejectsPlaceholderOrMismatch() {
        val a = make("oaiapp_x")
        assertEquals("oaiapp_x", a.consumeCallback("$callback?state=${a.state}&code=abc").issuedClientID)
        val b = make()
        assertThrows(OAuthError.InvalidCallback::class.java) { b.consumeCallback("$callback?state=${b.state}&code=abc") }
        val c = make()
        assertThrows(OAuthError.InvalidCallback::class.java) { c.consumeCallback("$callback?state=${c.state}&code=abc&client_id=dynamic_agent_client") }
        val d = make("oaiapp_x")
        assertThrows(OAuthError.InvalidCallback::class.java) { d.consumeCallback("$callback?state=${d.state}&code=abc&client_id=oaiapp_y") }
    }
}
