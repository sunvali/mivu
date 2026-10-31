package com.yakov103.mivu.connection

import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.runInterruptible
import org.json.JSONObject

sealed class SessionError : Exception() {
    object NoActiveSession : SessionError()
    object PlanPermissionMissing : SessionError()
    object InvalidRegistration : SessionError()
    object IdentityMismatch : SessionError()
    object InvalidResponse : SessionError()
    object NetworkUnavailable : SessionError()
    data class ProviderFailure(val code: Int) : SessionError()
    object InvalidRefresh : SessionError()
    object SessionChanged : SessionError()
}

enum class RevocationOutcome { Confirmed, Unconfirmed }

/** iOS `SessionSnapshot`: which registration is active and whether its plan scopes are granted; never a token. */
data class SessionSnapshot(val registrationID: String, val planPermissionGranted: Boolean)

/** Auth host URLs; tests pass a loopback base, production uses the default. */
class Endpoints(base: String = "https://auth.openai.com", val timeoutMs: Int = 30_000) {
    val token = "$base/api/accounts/oauth/token"
    val revoke = "$base/api/accounts/oauth/revoke"
    val jwks = "$base/.well-known/jwks.json"
}

class AuthSession(private val store: CredentialStoring, private val http: Endpoints = Endpoints()) {
    private val lock = Any()
    // Refresh runs here, not in the caller, so a cancelled caller cannot lose a rotated refresh token.
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var refreshing: Deferred<Credentials>? = null
    @Volatile private var active: Credentials? = null
    @Volatile private var trustedKeys: String? = null
    // Logout, restore and commits bump generation; each sign-in also bumps attempt so a later one wins.
    private var generation = 0
    private var attempt = 0

    suspend fun restore(registrationID: String): Credentials? = afterRefresh {
        store.load(registrationID).also { invalidate(); active = it }
    }

    suspend fun establish(
        code: AuthorizationCode,
        verifier: String,
        nonce: String,
        returningRegistrationID: String? = null,
        nowSec: Long? = null,
    ): Credentials {
        val clientID = code.issuedClientID
        if (clientID.isEmpty() || clientID == "dynamic_agent_client" || code.code.isEmpty() ||
            verifier.isEmpty() || nonce.isEmpty()) throw SessionError.InvalidRegistration
        val expected = if (returningRegistrationID != null) {
            store.registrations().firstOrNull { it.id == returningRegistrationID && it.issuedClientID == clientID }
                ?: throw SessionError.InvalidRegistration
        } else active?.registration?.takeIf { it.issuedClientID == clientID }
        val (myAttempt, revision) = synchronized(lock) { ++attempt to generation }
        fun checkCurrent() = synchronized(lock) {
            if (attempt != myAttempt || generation != revision) throw SessionError.SessionChanged
        }

        val reply = exchange(mapOf("grant_type" to "authorization_code", "client_id" to clientID,
            "code" to code.code, "code_verifier" to verifier, "redirect_uri" to code.redirect,
            "resource" to RESOURCE), isRefresh = false)
        val receivedAt = nowSec ?: epochNow()
        checkCurrent()
        val idToken = reply.idToken?.takeIf { it.isNotEmpty() } ?: throw SessionError.InvalidResponse
        val identity = try {
            IdTokenValidator.validate(idToken, keys(refetch = false), clientID, nonce, receivedAt)
        } catch (_: IdTokenError.UnknownKey) {
            IdTokenValidator.validate(idToken, keys(refetch = true), clientID, nonce, receivedAt)
        }
        checkCurrent()
        if (expected != null && expected.identity != identity) throw SessionError.IdentityMismatch
        val scopes = scopes(reply.scope.orEmpty())
        if ("offline_access" in scopes && reply.refreshToken.isNullOrEmpty()) throw SessionError.InvalidResponse
        val credentials = Credentials(AccountRegistration(identity, clientID), reply.accessToken,
            reply.refreshToken, idToken, scopes, receivedAt + reply.expiresIn)
        // Waiting for a running refresh lets it persist its rotated token before the switch.
        return afterRefresh {
            checkCurrent()
            store.replace(credentials)
            invalidate()
            active = credentials
            credentials
        }
    }

    /** [forceRefresh] exists for the debug proof screen to exercise a refresh before expiry. */
    suspend fun accessToken(nowSec: Long = epochNow(), expectedRegistrationID: String? = null, forceRefresh: Boolean = false): String {
        val current = usable(expectedRegistrationID)
        if (!forceRefresh && current.expiresAtEpochSec > nowSec + 30) return current.accessToken
        val pending = synchronized(lock) {
            // Another caller may have refreshed since the check above.
            val credentials = usable(current.registration.id)
            if (!forceRefresh && credentials.expiresAtEpochSec > nowSec + 30) return credentials.accessToken
            refreshing ?: refresh(credentials, nowSec).also { refreshing = it }
        }
        val replacement = pending.await()
        if (active !== replacement) throw SessionError.SessionChanged
        if (!replacement.planPermissionGranted) throw SessionError.PlanPermissionMissing
        return replacement.accessToken
    }

    fun snapshot(): SessionSnapshot? = active?.let { SessionSnapshot(it.registration.id, it.planPermissionGranted) }

    suspend fun disconnect(): RevocationOutcome {
        // Delete before suspending so a later sign-in cannot be erased by this logout.
        val (credentials, pending) = synchronized(lock) {
            invalidate()
            val current = active?.also { store.delete(it.registration.id); active = null }
            current to refreshing
        }
        credentials ?: return RevocationOutcome.Confirmed
        // A refresh already sent may rotate the token; revoke whichever token the provider still honours.
        val rotated = pending?.let { runCatching { it.await() }.getOrNull() }
        val latest = rotated?.takeIf { it.registration == credentials.registration } ?: credentials
        return revoke(latest)
    }

    // Called under lock; the task's commit waits for that lock, so `refreshing` is set first.
    private fun refresh(credentials: Credentials, nowSec: Long): Deferred<Credentials> {
        val revision = generation
        return scope.async {
            try {
                val refreshToken = credentials.refreshToken?.takeIf { it.isNotEmpty() }
                    ?: throw forget(credentials, revision)
                val reply = try {
                    exchange(mapOf("grant_type" to "refresh_token", "client_id" to credentials.registration.issuedClientID,
                        "refresh_token" to refreshToken, "resource" to RESOURCE), isRefresh = true)
                } catch (e: SessionError.InvalidRefresh) { throw forget(credentials, revision) }
                val rotated = reply.refreshToken?.takeIf { it.isNotEmpty() } ?: throw SessionError.InvalidResponse
                val replacement = credentials.copy(accessToken = reply.accessToken, refreshToken = rotated,
                    scopes = reply.scope?.let(::scopes) ?: credentials.scopes, expiresAtEpochSec = nowSec + reply.expiresIn)
                synchronized(lock) {
                    // Superseded results still return so a logout can revoke the rotated token.
                    if (generation == revision) {
                        store.replace(replacement)
                        active = replacement
                    }
                }
                replacement
            } finally {
                synchronized(lock) { if (refreshing === coroutineContext[Job]) refreshing = null }
            }
        }
    }

    private suspend fun revoke(credentials: Credentials): RevocationOutcome {
        val token = credentials.refreshToken?.takeIf { it.isNotEmpty() } ?: return RevocationOutcome.Unconfirmed
        return try {
            val status = send(http.revoke, mapOf("token" to token, "token_type_hint" to "refresh_token",
                "client_id" to credentials.registration.issuedClientID)).status
            if (status == 200) RevocationOutcome.Confirmed else RevocationOutcome.Unconfirmed
        } catch (_: SessionError) { RevocationOutcome.Unconfirmed }
    }

    /** Runs [block] under the lock once no refresh is in flight. */
    private suspend fun <T> afterRefresh(block: () -> T): T {
        while (true) synchronized(lock) { refreshing ?: return block() }.join()
    }

    private fun usable(expectedRegistrationID: String?): Credentials {
        val credentials = active ?: throw SessionError.NoActiveSession
        if (expectedRegistrationID != null && expectedRegistrationID != credentials.registration.id) {
            throw SessionError.SessionChanged
        }
        if (!credentials.planPermissionGranted) throw SessionError.PlanPermissionMissing
        return credentials
    }

    private fun forget(credentials: Credentials, revision: Int): SessionError = synchronized(lock) {
        if (generation != revision) return SessionError.SessionChanged
        store.delete(credentials.registration.id)
        active = null
        SessionError.InvalidRefresh
    }

    private fun invalidate() { generation++; attempt++ }

    private suspend fun keys(refetch: Boolean): String {
        trustedKeys?.takeUnless { refetch }?.let { return it }
        val reply = send(http.jwks, form = null)
        if (reply.status != 200) throw SessionError.ProviderFailure(reply.status)
        return reply.body.also { trustedKeys = it }
    }

    private class TokenReply(
        val accessToken: String, val refreshToken: String?, val idToken: String?, val expiresIn: Long, val scope: String?,
    )

    private suspend fun exchange(fields: Map<String, String>, isRefresh: Boolean): TokenReply {
        val reply = send(http.token, fields)
        if (reply.status != 200) {
            val error = try { JSONObject(reply.body).opt("error") } catch (_: Exception) { null }
            if (isRefresh && reply.status in 400..401 && error in TERMINAL_REFRESH_ERRORS) throw SessionError.InvalidRefresh
            throw SessionError.ProviderFailure(reply.status)
        }
        val json = try { JSONObject(reply.body) } catch (_: Exception) { throw SessionError.InvalidResponse }
        val accessToken = json.opt("access_token") as? String
        val expiresIn = json.opt("expires_in").let { if (it is Int || it is Long) (it as Number).toLong() else 0L }
        if (accessToken.isNullOrEmpty() || !(json.opt("token_type") as? String).equals("bearer", ignoreCase = true) ||
            expiresIn !in 1..86_400 || (!json.isNull("client_id") && json.opt("client_id") != fields["client_id"])) {
            throw SessionError.InvalidResponse
        }
        return TokenReply(accessToken, json.opt("refresh_token") as? String, json.opt("id_token") as? String,
            expiresIn, json.opt("scope") as? String)
    }

    private class Reply(val status: Int, val body: String)

    private suspend fun send(url: String, form: Map<String, String>?): Reply = runInterruptible(Dispatchers.IO) {
        val connection = URL(url).openConnection() as HttpURLConnection
        try {
            // A redirect could replay the credential-bearing form elsewhere; 3xx is a provider failure.
            connection.instanceFollowRedirects = false
            connection.useCaches = false
            connection.connectTimeout = http.timeoutMs
            connection.readTimeout = http.timeoutMs
            if (form != null) {
                connection.requestMethod = "POST"
                connection.doOutput = true
                connection.setRequestProperty("Content-Type", "application/x-www-form-urlencoded")
                val body = form.entries.sortedBy { it.key }
                    .joinToString("&") { "${URLEncoder.encode(it.key, "UTF-8")}=${URLEncoder.encode(it.value, "UTF-8")}" }
                connection.outputStream.use { it.write(body.toByteArray()) }
            }
            val status = connection.responseCode
            val stream = if (status < 400) connection.inputStream else connection.errorStream
            val buffer = ByteArray(MAX_BODY + 1)
            var length = 0
            stream?.use {
                while (length < buffer.size) {
                    val read = it.read(buffer, length, buffer.size - length)
                    if (read < 0) break
                    length += read
                }
            }
            if (length > MAX_BODY) throw SessionError.InvalidResponse
            Reply(status, String(buffer, 0, length, Charsets.UTF_8))
        } catch (_: IOException) {
            throw SessionError.NetworkUnavailable
        } finally {
            connection.disconnect()
        }
    }

    private companion object {
        const val RESOURCE = "https://api.openai.com/v1"
        const val MAX_BODY = 1_048_576
        val TERMINAL_REFRESH_ERRORS = setOf("invalid_grant", "invalid_refresh_token", "token_expired",
            "refresh_token_expired", "refresh_token_invalidated", "refresh_token_reused")

        fun scopes(value: String) = value.split(" ").filter { it.isNotEmpty() }.toSet()
        fun epochNow() = System.currentTimeMillis() / 1000
    }
}
