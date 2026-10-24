package com.yakov103.mivu.connection

import java.net.URI
import java.net.URISyntaxException
import java.net.URLDecoder
import java.net.URLEncoder
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Base64

sealed class OAuthError : Exception() {
    object InvalidRedirect : OAuthError()
    object InvalidRegistration : OAuthError()
    object InvalidCallback : OAuthError()
    object Denied : OAuthError()
    object ProviderError : OAuthError()
    object AlreadyConsumed : OAuthError()
}

data class AuthorizationCode(val code: String, val issuedClientID: String, val redirect: String)

private const val PLACEHOLDER_CLIENT = "dynamic_agent_client"

class OAuthAttempt private constructor(
    val state: String,
    val nonce: String,
    val verifier: String,
    val callback: String,
    val authorizationUrl: String,
    private val issuedClientID: String?,
) {
    private var consumed = false

    @Synchronized
    fun consumeCallback(url: String): AuthorizationCode {
        if (consumed) throw OAuthError.AlreadyConsumed
        val received = parse(url) ?: throw OAuthError.InvalidCallback
        val expected = parse(callback)!!
        if (received.scheme != expected.scheme || received.host != expected.host ||
            received.port != expected.port || received.path != expected.path ||
            received.userInfo != null || received.rawFragment != null
        ) throw OAuthError.InvalidCallback
        val params = mutableMapOf<String, String>()
        received.rawQuery?.split("&")?.forEach { item ->
            val (name, value) = item.split("=", limit = 2).let { it[0] to it.getOrNull(1) }
            if (name in params || value == null) throw OAuthError.InvalidCallback
            params[decode(name)] = decode(value)
        }
        if (params["state"] != state) throw OAuthError.InvalidCallback
        params["error"]?.let {
            consumed = true
            throw if (it == "access_denied") OAuthError.Denied else OAuthError.ProviderError
        }
        val code = params["code"]?.takeIf { it.isNotEmpty() } ?: throw OAuthError.InvalidCallback
        val clientID = params["client_id"] ?: issuedClientID
        if (clientID.isNullOrEmpty() || clientID == PLACEHOLDER_CLIENT ||
            (issuedClientID != null && issuedClientID != clientID)
        ) throw OAuthError.InvalidCallback
        consumed = true
        return AuthorizationCode(code, clientID, callback)
    }

    companion object {
        fun make(
            hostID: String,
            issuedClientID: String?,
            callback: String,
            requestPlanConsent: Boolean = false,
        ): OAuthAttempt {
            if (hostID.isEmpty() || issuedClientID == "" || issuedClientID == PLACEHOLDER_CLIENT) {
                throw OAuthError.InvalidRegistration
            }
            val r = parse(callback)
            if (r == null || r.scheme != "http" || r.host != "127.0.0.1" || r.port !in 1..65535 ||
                r.path != "/auth/callback" || r.userInfo != null || r.rawQuery != null || r.rawFragment != null
            ) throw OAuthError.InvalidRedirect
            val state = randomValue()
            val nonce = randomValue()
            val verifier = randomValue()
            val query = mutableListOf(
                "client_id" to (issuedClientID ?: PLACEHOLDER_CLIENT),
                "ext_agent_host_id" to hostID,
                "response_type" to "code",
                "redirect_uri" to callback,
                "scope" to "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct",
                "resource" to "https://api.openai.com/v1",
                "state" to state,
                "nonce" to nonce,
                "code_challenge_method" to "S256",
                "code_challenge" to challenge(verifier),
            )
            if (issuedClientID == null) query += "agent_name_hint" to "Mivu"
            if (requestPlanConsent) query += "prompt" to "consent"
            val url = "https://auth.openai.com/api/accounts/authorize?" +
                query.joinToString("&") { (k, v) -> "${encode(k)}=${encode(v)}" }
            return OAuthAttempt(state, nonce, verifier, callback, url, issuedClientID)
        }

        private fun parse(url: String): URI? = try { URI(url) } catch (_: URISyntaxException) { null }
        private fun encode(s: String) = URLEncoder.encode(s, "UTF-8").replace("+", "%20")
        private fun decode(s: String) = try { URLDecoder.decode(s, "UTF-8") } catch (_: IllegalArgumentException) { throw OAuthError.InvalidCallback }
        private fun base64Url(b: ByteArray) = Base64.getUrlEncoder().withoutPadding().encodeToString(b)
        private fun randomValue() = base64Url(ByteArray(32).also { SecureRandom().nextBytes(it) })
    }
}

fun challenge(verifier: String): String =
    Base64.getUrlEncoder().withoutPadding().encodeToString(
        MessageDigest.getInstance("SHA-256").digest(verifier.toByteArray()),
    )
