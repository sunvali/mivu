package com.yakov103.mivu.connection

import com.sun.net.httpserver.HttpServer
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.URLDecoder
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.Executors
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class MemoryCredentialStore : CredentialStoring {
    val records = ConcurrentHashMap<String, Credentials>()
    override fun hostID() = "urn:uuid:00000000-0000-4000-8000-000000000001"
    override fun registrations() = records.values.map { it.registration }
    override fun load(registrationID: String) = records[registrationID]
    override fun replace(credentials: Credentials) { records[credentials.registration.id] = credentials }
    override fun delete(registrationID: String) { records.remove(registrationID) }
}

/** Fake auth host on 127.0.0.1; records each request as (path, headers' content type, form fields). */
class FakeAuthServer : AutoCloseable {
    class Request(val path: String, val contentType: String?, val form: Map<String, String>)
    val requests = CopyOnWriteArrayList<Request>()
    @Volatile var delayMs = 0L
    @Volatile var respond: (Request) -> Pair<Int, String> = { 500 to "" }
    private val server = HttpServer.create(InetSocketAddress(InetAddress.getLoopbackAddress(), 0), 0).apply {
        executor = Executors.newCachedThreadPool()
        createContext("/") { exchange ->
            val body = exchange.requestBody.readBytes().decodeToString()
            val form = body.split("&").filter { it.isNotEmpty() }.associate {
                val (k, v) = it.split("=", limit = 2)
                URLDecoder.decode(k, "UTF-8") to URLDecoder.decode(v, "UTF-8")
            }
            val request = Request(exchange.requestURI.path, exchange.requestHeaders.getFirst("Content-Type"), form)
            requests += request
            Thread.sleep(delayMs)
            val (status, reply) = respond(request)
            if (status in 300..399) exchange.responseHeaders.add("Location", "/redirected")
            val bytes = reply.toByteArray()
            exchange.sendResponseHeaders(status, if (bytes.isEmpty()) -1 else bytes.size.toLong())
            if (bytes.isNotEmpty()) exchange.responseBody.use { it.write(bytes) }
            exchange.close()
        }
        start()
    }
    val endpoints = Endpoints("http://127.0.0.1:${server.address.port}", timeoutMs = 300)
    fun hits(path: String) = requests.count { it.path == path }
    override fun close() = server.stop(0)
}

class AuthSessionTest {
    private val identity = SyntheticIdentity()
    private val server = FakeAuthServer()
    private val store = MemoryCredentialStore()
    private val session = AuthSession(store, server.endpoints)
    private val code = AuthorizationCode("synthetic-code", identity.clientID, "http://127.0.0.1:1455/auth/callback")
    private val planScopes = "openid offline_access resource.invoke chatgpt.tokens.use.direct"
    private val registration = AccountRegistration(VerifiedIdentity("https://auth.openai.com", "synthetic-account"), identity.clientID)
    private val tokenPath = "/api/accounts/oauth/token"

    @After fun stop() = server.close()

    private fun reply(vararg changes: Pair<String, Any?>) = JSONObject(mapOf(
        "access_token" to "synthetic-access", "refresh_token" to "synthetic-refresh", "id_token" to identity.token(),
        "token_type" to "Bearer", "expires_in" to 3600, "scope" to planScopes) + changes).toString()

    private fun serve(token: () -> Pair<Int, String>) {
        server.respond = { if (it.path == "/.well-known/jwks.json") 200 to identity.jwks else token() }
    }

    private fun establish() = runBlocking { session.establish(code, "synthetic-verifier", identity.nonce, nowSec = identity.now) }

    private fun restore(expiresAt: Long, refresh: String? = "old-refresh"): Credentials {
        val saved = Credentials(registration, "old-access", refresh, "synthetic-id-token", planScopes.split(" ").toSet(), expiresAt)
        store.replace(saved)
        runBlocking { session.restore(registration.id) }
        return saved
    }

    private inline fun <reified E : SessionError> fails(block: () -> Unit): E {
        try { block() } catch (e: SessionError) {
            if (e is E) return e
            fail("expected ${E::class.simpleName}, got $e")
        }
        fail("expected ${E::class.simpleName}")
        error("unreachable")
    }

    @Test fun registrationIdMatchesIos() {
        assertEquals("c6ae4edc7569e9d158b5df9dc6d02b0b39fe4a4506cc0e4bcde04c1dc180146b", registration.id)
        // iOS bytes: ["https:\/\/auth.openai.com","a\/b\"c\\d\u0001\né","oaiapp_synthetic"]
        val escaped = AccountRegistration(VerifiedIdentity("https://auth.openai.com", "a/b\"c\\d\u0001\né"), identity.clientID)
        assertEquals("9f21ff3ab5d3efc4b4d9b84fb3cbeab1153d259b699e25e65229d54dfe37a40d", escaped.id)
    }

    private fun awaitTokenRequest() {
        val deadline = System.currentTimeMillis() + 2_000
        while (server.hits(tokenPath) == 0) {
            check(System.currentTimeMillis() < deadline) { "no token request" }
            Thread.sleep(5)
        }
    }

    @Test fun cancelledCallerStillStoresRotatedToken() {
        restore(identity.now)
        server.delayMs = 150
        serve { 200 to reply("access_token" to "new-access", "refresh_token" to "new-refresh") }
        runBlocking {
            val caller = launch(Dispatchers.IO) { session.accessToken(identity.now) }
            awaitTokenRequest()
            caller.cancelAndJoin()
            assertEquals("new-access", session.accessToken(identity.now))
        }
        assertEquals("new-refresh", store.load(registration.id)?.refreshToken)
        assertEquals(1, server.hits(tokenPath))
    }

    @Test fun disconnectDuringRefreshRevokesRotatedToken() {
        restore(identity.now)
        server.delayMs = 150
        server.respond = { if (it.path == tokenPath) 200 to reply("refresh_token" to "new-refresh") else 200 to "" }
        runBlocking {
            val caller = async(Dispatchers.IO) { runCatching { session.accessToken(identity.now) } }
            awaitTokenRequest()
            assertEquals(RevocationOutcome.Confirmed, session.disconnect())
            assertEquals(SessionError.SessionChanged, caller.await().exceptionOrNull())
        }
        assertEquals(listOf("new-refresh"), server.requests.filter { it.path.endsWith("/revoke") }.map { it.form["token"] })
        assertTrue(store.records.isEmpty())
    }

    @Test fun waitersShareAFailedRefresh() {
        restore(identity.now)
        server.delayMs = 100
        serve { 503 to "" }
        val errors = runBlocking {
            List(2) { async(Dispatchers.IO) { runCatching { session.accessToken(identity.now) }.exceptionOrNull() } }.awaitAll()
        }
        assertEquals(listOf(SessionError.ProviderFailure(503), SessionError.ProviderFailure(503)), errors)
        assertEquals(1, server.hits(tokenPath))
    }

    @Test fun establishPostsCodeExchangeFormAndStoresVerifiedCredentials() {
        serve { 200 to reply() }
        val credentials = establish()
        val request = server.requests.first { it.path == tokenPath }
        assertEquals("application/x-www-form-urlencoded", request.contentType)
        assertEquals(mapOf("grant_type" to "authorization_code", "client_id" to identity.clientID,
            "code" to "synthetic-code", "code_verifier" to "synthetic-verifier",
            "redirect_uri" to "http://127.0.0.1:1455/auth/callback", "resource" to "https://api.openai.com/v1"), request.form)
        assertEquals(registration, credentials.registration)
        assertEquals(identity.now + 3600, credentials.expiresAtEpochSec)
        assertTrue(credentials.planPermissionGranted)
        assertEquals(credentials, store.load(registration.id))
        assertEquals("synthetic-access", runBlocking { session.accessToken(identity.now) })
    }

    @Test fun invalidTokenRepliesAreRejectedAndNothingIsStored() {
        val bad = listOf(
            reply("refresh_token" to null), reply("token_type" to "mac"), reply("access_token" to ""),
            reply("client_id" to "oaiapp_other"), reply("expires_in" to 0), reply("id_token" to null), "not json")
        for (body in bad) {
            serve { 200 to body }
            fails<SessionError.InvalidResponse> { establish() }
        }
        assertTrue(store.records.isEmpty())
    }

    @Test fun mismatchedNonceIsRejected() {
        serve { 200 to reply("id_token" to identity.token(mapOf("nonce" to "other"))) }
        try { establish(); fail() } catch (_: IdTokenError.InvalidClaims) {}
    }

    @Test fun returningAccountWithAnotherSubjectIsIdentityMismatch() {
        val saved = restore(identity.now + 3600)
        serve { 200 to reply("id_token" to identity.token(mapOf("sub" to "another-account"))) }
        fails<SessionError.IdentityMismatch> {
            runBlocking { session.establish(code, "v", identity.nonce, registration.id, identity.now) }
        }
        assertEquals(saved, store.load(registration.id))
    }

    @Test fun redirectsAreNotFollowed() {
        serve { 302 to "" }
        assertEquals(302, fails<SessionError.ProviderFailure> { establish() }.code)
        assertEquals(0, server.hits("/redirected"))
    }

    @Test fun accessTokenReturnsStoredTokenWhileMoreThanThirtySecondsRemain() {
        restore(identity.now + 31)
        assertEquals("old-access", runBlocking { session.accessToken(identity.now) })
        assertTrue(server.requests.isEmpty())
    }

    @Test fun refreshReplacesTokensExpiryAndScopesTogether() {
        restore(identity.now + 30)
        serve { 200 to reply("access_token" to "new-access", "refresh_token" to "new-refresh",
            "scope" to "openid resource.invoke chatgpt.tokens.use.direct extra") }
        assertEquals("new-access", runBlocking { session.accessToken(identity.now) })
        assertEquals(mapOf("grant_type" to "refresh_token", "client_id" to identity.clientID,
            "refresh_token" to "old-refresh", "resource" to "https://api.openai.com/v1"), server.requests.single().form)
        val stored = store.load(registration.id)!!
        assertEquals("new-refresh", stored.refreshToken)
        assertEquals(identity.now + 3600, stored.expiresAtEpochSec)
        assertEquals(setOf("openid", "resource.invoke", "chatgpt.tokens.use.direct", "extra"), stored.scopes)
    }

    @Test fun expiredSessionWithoutRefreshTokenIsDeleted() {
        restore(identity.now, refresh = null)
        fails<SessionError.InvalidRefresh> { runBlocking { session.accessToken(identity.now) } }
        assertNull(store.load(registration.id))
        fails<SessionError.NoActiveSession> { runBlocking { session.accessToken(identity.now) } }
    }

    @Test fun terminalRefreshErrorsDeleteCredentials() {
        for (error in listOf("invalid_grant", "invalid_refresh_token", "token_expired",
                "refresh_token_expired", "refresh_token_invalidated", "refresh_token_reused")) {
            restore(identity.now)
            serve { 400 to JSONObject().put("error", error).toString() }
            fails<SessionError.InvalidRefresh> { runBlocking { session.accessToken(identity.now) } }
            assertNull(error, store.load(registration.id))
        }
    }

    @Test fun otherProviderErrorsKeepCredentials() {
        restore(identity.now)
        serve { 503 to JSONObject().put("error", "invalid_grant").toString() }
        assertEquals(503, fails<SessionError.ProviderFailure> { runBlocking { session.accessToken(identity.now) } }.code)
        assertNotNull(store.load(registration.id))
    }

    @Test fun socketTimeoutIsNetworkUnavailableAndKeepsCredentials() {
        val saved = restore(identity.now)
        server.delayMs = 1_000
        serve { 200 to reply() }
        fails<SessionError.NetworkUnavailable> { runBlocking { session.accessToken(identity.now) } }
        assertEquals(saved, store.load(registration.id))
    }

    @Test fun concurrentCallsShareOneRefresh() {
        restore(identity.now)
        server.delayMs = 100
        serve { 200 to reply("access_token" to "new-access") }
        val tokens = runBlocking { List(2) { async(Dispatchers.IO) { session.accessToken(identity.now) } }.awaitAll() }
        assertEquals(listOf("new-access", "new-access"), tokens)
        assertEquals(1, server.hits(tokenPath))
    }

    @Test fun disconnectDeletesThenRevokesRefreshToken() {
        restore(identity.now + 3600)
        serve { 200 to "" }
        assertEquals(RevocationOutcome.Confirmed, runBlocking { session.disconnect() })
        assertNull(store.load(registration.id))
        val request = server.requests.single()
        assertEquals("/api/accounts/oauth/revoke", request.path)
        assertEquals(mapOf("token" to "old-refresh", "token_type_hint" to "refresh_token",
            "client_id" to identity.clientID), request.form)
        fails<SessionError.NoActiveSession> { runBlocking { session.accessToken(identity.now) } }
    }

    @Test fun failedRevocationIsUnconfirmedButStillDeletes() {
        restore(identity.now + 3600)
        serve { 503 to "" }
        assertEquals(RevocationOutcome.Unconfirmed, runBlocking { session.disconnect() })
        assertNull(store.load(registration.id))
    }

    @Test fun credentialsNeverPrintTokens() {
        val text = restore(identity.now).toString()
        assertTrue(text, "old-access" !in text && "old-refresh" !in text && "synthetic-id-token" !in text)
    }
}
