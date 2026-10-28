package com.yakov103.mivu.connection

import com.sun.net.httpserver.HttpServer
import com.yakov103.mivu.analysis.ResponsesClient
import com.yakov103.mivu.coach.CoachInferenceInput
import com.yakov103.mivu.coach.CoachTools
import java.net.InetSocketAddress
import java.net.URI
import java.net.URL
import java.net.URLDecoder
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.cancel
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ChatGPTConnectionTest {
    private val identity = SyntheticIdentity()
    private val auth = FakeAuthServer()
    private val store = MemoryCredentialStore()
    private val prefs = MemoryPreferences()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val planScopes = "openid offline_access resource.invoke chatgpt.tokens.use.direct"
    private val tokenPath = "/api/accounts/oauth/token"
    private val registration = AccountRegistration(VerifiedIdentity("https://auth.openai.com", "synthetic-account"), identity.clientID)
    @Volatile private var nonce = ""
    @Volatile private var subject = "synthetic-account"

    // Synthetic Responses host: two listed models; `/v1/responses` replies with [status] after [release] opens.
    private val apiPaths = CopyOnWriteArrayList<String>()
    @Volatile private var catalog = listOf("synthetic-model-a", "synthetic-model-b")
    @Volatile private var status = 200
    @Volatile private var release = CountDownLatch(0)
    private val api = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0).apply {
        executor = java.util.concurrent.Executors.newCachedThreadPool()
        createContext("/") { ex ->
            ex.requestBody.readBytes()
            apiPaths += ex.requestURI.path
            val models = ex.requestURI.path == "/v1/models"
            if (!models) release.await(5, TimeUnit.SECONDS)
            val code = if (models) 200 else status
            val body = if (code != 200) "" else if (models) JSONObject().put("models", catalog.map {
                mapOf("slug" to it, "display_name" to it, "visibility" to "list")
            }).toString() else "data: $COMPLETED\n\n"
            val bytes = body.toByteArray()
            ex.sendResponseHeaders(code, if (bytes.isEmpty()) -1 else bytes.size.toLong())
            if (bytes.isNotEmpty()) ex.responseBody.use { it.write(bytes) }
            ex.close()
        }
        start()
    }

    init {
        auth.respond = { request ->
            when (request.path) {
                "/.well-known/jwks.json" -> 200 to identity.jwks
                tokenPath -> 200 to tokenReply()
                else -> 200 to ""
            }
        }
    }

    @After fun stop() {
        scope.cancel()
        auth.close()
        api.stop(0)
    }

    private fun connection() = ChatGPTConnection(store, AuthSession(store, auth.endpoints),
        ResponsesClient("http://127.0.0.1:${api.address.port}/v1/"), prefs, scope)

    private fun now() = System.currentTimeMillis() / 1000

    private fun tokenReply() = JSONObject(mapOf("access_token" to "synthetic-access", "refresh_token" to "synthetic-refresh",
        "id_token" to identity.token(mapOf("nonce" to nonce, "sub" to subject, "iat" to now() - 10, "exp" to now() + 300)),
        "token_type" to "Bearer", "expires_in" to 3600, "scope" to planScopes)).toString()

    private fun consent() { prefs.edit().putBoolean("openAISharingConsent", true).commit() }

    /** A session saved by an earlier sign-in: its credentials and the chosen registration. */
    private fun saved(expiresAt: Long = now() + 3600) {
        store.replace(Credentials(registration, "synthetic-access", "synthetic-refresh", "synthetic-id-token",
            planScopes.split(" ").toSet(), expiresAt))
        prefs.edit().putString("selectedRegistrationID", registration.id).commit()
    }

    private fun restored() = connection().also { runBlocking { it.restore() } }

    /** A synthetic browser: reads `state` and `nonce` from the authorization URL and follows the loopback redirect. */
    private fun browser(error: String? = null): (String) -> Unit = { url ->
        val query = URI(url).rawQuery.split("&").associate {
            it.substringBefore("=") to URLDecoder.decode(it.substringAfter("="), "UTF-8")
        }
        nonce = query.getValue("nonce")
        val result = if (error != null) "error=$error" else "code=synthetic-code&client_id=${identity.clientID}"
        runCatching { URL("${query.getValue("redirect_uri")}?state=${query.getValue("state")}&$result").readBytes() }
    }

    private fun connect(c: ChatGPTConnection, open: (String) -> Unit = browser()) = runBlocking { c.connect(open).join() }

    private val input = listOf(CoachInferenceInput.Message(CoachInferenceInput.Role.user, "two boiled eggs and a slice of toast"))

    private fun respond(c: ChatGPTConnection): Result<*> = runBlocking { runCatching { c.inference()(input, CoachTools.declarations()) } }

    private fun awaitResponseRequest() {
        val deadline = System.currentTimeMillis() + 5_000
        while ("/v1/responses" !in apiPaths) {
            check(System.currentTimeMillis() < deadline) { "no responses request" }
            Thread.sleep(5)
        }
    }

    @Test fun restoreWithoutConsentStaysDisconnected() {
        saved()
        val c = restored()
        assertEquals(AccountState.disconnected, c.state.value.account)
        assertFalse(c.state.value.planAuthorized)
        assertTrue(apiPaths.isEmpty())
    }

    @Test fun restoreWithConsentLoadsModelsAndSelectsFirst() {
        consent(); saved()
        val state = restored().state.value
        assertEquals(AccountState.connected, state.account)
        assertEquals(registration.id, state.registrationID)
        assertEquals(catalog, state.models.map { it.slug })
        assertEquals("synthetic-model-a", state.selectedModel)
        assertTrue(state.planAuthorized)
    }

    @Test fun connectRequiresConsent() {
        var opened = false
        val c = connection()
        connect(c) { opened = true }
        assertFalse(opened)
        assertTrue(auth.requests.isEmpty())
        assertEquals(AccountState.disconnected, c.state.value.account)
    }

    @Test fun connectSuccessConnectsAndKeepsSelectionInCatalog() {
        consent()
        val c = connection()
        assertEquals("Continue with ChatGPT", c.state.value.buttonTitle)
        connect(c)
        val state = c.state.value
        assertEquals(AccountState.connected, state.account)
        assertEquals(store.registrations().single().id, state.registrationID)
        assertFalse(state.isConnecting)
        assertEquals("synthetic-model-a", state.selectedModel)
        assertEquals("Reauthorize ChatGPT", state.buttonTitle)
        c.selectModel("synthetic-model-b")
        c.selectModel("not-in-catalog")
        assertEquals("synthetic-model-b", c.state.value.selectedModel)
        assertTrue(c.state.value.planAuthorized)
    }

    @Test fun networkFailureShowsOfflineNotice() {
        consent()
        auth.delayMs = 1_000 // past the 300 ms client timeout: the token host is unreachable
        val c = connection()
        connect(c)
        assertEquals(ConnectionNotice.offline, c.state.value.notice)
        assertEquals(AccountState.disconnected, c.state.value.account)
        assertFalse(c.state.value.isConnecting)
        assertTrue(store.records.isEmpty())
        auth.delayMs = 0
        connect(c)
        assertEquals(AccountState.connected, c.state.value.account)
        assertNull(c.state.value.notice)
    }

    @Test fun deniedShowsDeniedNotice() {
        consent()
        val c = connection()
        connect(c, browser(error = "access_denied"))
        assertEquals(ConnectionNotice.denied, c.state.value.notice)
        assertTrue(auth.requests.isEmpty())
    }

    @Test fun cancelShowsCancelled() {
        consent()
        val c = connection()
        val opened = CompletableDeferred<Unit>()
        runBlocking {
            val job = c.connect { opened.complete(Unit) }
            withTimeout(5_000) { opened.await() }
            assertTrue(c.state.value.isConnecting)
            c.cancelConnection()
            job.join()
        }
        assertEquals(ConnectionNotice.cancelled, c.state.value.notice)
        assertFalse(c.state.value.isConnecting)
        assertTrue(auth.requests.isEmpty())
    }

    @Test fun disconnectClearsStateAndReportsOutcome() {
        consent()
        for ((revokeStatus, notice) in listOf(200 to ConnectionNotice.disconnected, 500 to ConnectionNotice.unconfirmed)) {
            auth.respond = { (if (it.path.endsWith("/revoke")) revokeStatus else 200) to "" }
            saved()
            val c = restored()
            runBlocking { c.disconnect() }
            val state = c.state.value
            assertTrue(store.records.isEmpty())
            assertEquals(notice, state.notice)
            assertEquals(AccountState.disconnected, state.account)
            assertNull(state.registrationID)
            assertTrue(state.models.isEmpty())
            assertFalse(state.isDisconnecting)
        }
    }

    @Test fun disconnectDuringRespondThrowsSessionChanged() {
        consent(); saved()
        val c = restored()
        release = CountDownLatch(1)
        val result = runBlocking {
            val pending = async(Dispatchers.IO) { respond(c) }
            awaitResponseRequest()
            c.disconnect()
            release.countDown()
            pending.await()
        }
        assertEquals(SessionError.SessionChanged, result.exceptionOrNull())
        assertTrue(store.records.isEmpty())
    }

    @Test fun selectModelChangeDuringRespondThrowsSessionChanged() {
        consent(); saved()
        val c = restored()
        release = CountDownLatch(1)
        val result = runBlocking {
            val pending = async(Dispatchers.IO) { respond(c) }
            awaitResponseRequest()
            c.selectModel("synthetic-model-b")
            release.countDown()
            pending.await()
        }
        assertEquals(SessionError.SessionChanged, result.exceptionOrNull())
        assertEquals(AccountState.connected, c.state.value.account)
    }

    @Test fun restoreBringsBackOnlyTheChosenAccount() {
        consent()
        // Account A's credentials remain from before consent; the person connects B, then disconnects it.
        store.replace(Credentials(registration, "synthetic-access", "synthetic-refresh", "synthetic-id-token",
            planScopes.split(" ").toSet(), now() + 3600))
        subject = "synthetic-account-b"
        val c = connection()
        connect(c)
        assertEquals(AccountState.connected, c.state.value.account)
        assertTrue(c.state.value.registrationID != registration.id)
        runBlocking { c.disconnect() }
        val relaunched = restored()
        assertEquals(AccountState.disconnected, relaunched.state.value.account)
        assertNull(relaunched.state.value.registrationID)
        assertNull(relaunched.auth.snapshot())
    }

    @Test fun modelChangeMidTurnEndsTheTurn() {
        consent(); saved()
        val c = restored()
        val turn = c.inference()
        runBlocking { turn(input, CoachTools.declarations()) }
        c.selectModel("synthetic-model-b")
        val next = runBlocking { runCatching { turn(input, CoachTools.declarations()) } }
        assertEquals(SessionError.SessionChanged, next.exceptionOrNull())
        assertEquals(1, apiPaths.count { it == "/v1/responses" })
    }

    @Test fun offlineRefreshShowsOfflineNotice() {
        consent(); saved(expiresAt = now())
        auth.delayMs = 1_000
        assertEquals(ConnectionNotice.offline, restored().state.value.notice)
    }

    @Test fun respondReturnsTheModelReply() {
        consent(); saved()
        assertEquals("Synthetic reply", (respond(restored()).getOrThrow() as com.yakov103.mivu.coach.CoachInferenceResult).text)
    }

    @Test fun unauthorizedPausesPlanPermission() {
        consent(); saved()
        val c = restored()
        status = 401
        assertEquals(ResponsesClient.Failure.Unauthorized, respond(c).exceptionOrNull())
        val state = c.state.value
        assertEquals(AccountState.planPermissionMissing, state.account)
        assertEquals(ConnectionNotice.revoked, state.notice)
        assertEquals("Enable ChatGPT plan usage", state.buttonTitle)
        assertFalse(state.planAuthorized)
        val modelRequests = apiPaths.count { it == "/v1/models" }
        val relaunched = restored()
        assertEquals(AccountState.planPermissionMissing, relaunched.state.value.account)
        assertEquals(modelRequests, apiPaths.count { it == "/v1/models" })
    }

    @Test fun quotaSetsQuotaNotice() {
        consent(); saved()
        val c = restored()
        status = 429
        assertEquals(ResponsesClient.Failure.QuotaReached, respond(c).exceptionOrNull())
        assertEquals(ConnectionNotice.quota, c.state.value.notice)
        assertEquals(AccountState.connected, c.state.value.account)
    }

    @Test fun planUnauthorizedWithoutModels() {
        consent(); saved()
        catalog = emptyList()
        val c = restored()
        assertEquals(AccountState.connected, c.state.value.account)
        assertFalse(c.state.value.planAuthorized)
        assertEquals(SessionError.NoActiveSession, respond(c).exceptionOrNull())
        assertFalse("/v1/responses" in apiPaths)
    }

    private companion object {
        const val COMPLETED = """{"type":"response.completed","response":{"status":"completed","model":"synthetic-model-a","output":[""" +
            """{"type":"message","id":"msg_1","role":"assistant","status":"completed","content":[{"type":"output_text","text":"Synthetic reply"}]}]}}"""
    }
}
