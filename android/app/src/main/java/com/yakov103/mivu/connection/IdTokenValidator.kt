package com.yakov103.mivu.connection

import java.math.BigInteger
import java.security.KeyFactory
import java.security.PublicKey
import java.security.Signature
import java.security.spec.RSAPublicKeySpec
import java.util.Base64
import org.json.JSONArray
import org.json.JSONObject

sealed class IdTokenError : Exception() {
    object InvalidToken : IdTokenError()
    object UnsupportedAlgorithm : IdTokenError()
    object MissingKey : IdTokenError()
    object UnknownKey : IdTokenError()
    object InvalidKey : IdTokenError()
    object InvalidSignature : IdTokenError()
    object InvalidClaims : IdTokenError()
}

object IdTokenValidator {
    private const val ISSUER = "https://auth.openai.com"

    fun validate(token: String, jwks: String, clientID: String, nonce: String, nowSec: Long): VerifiedIdentity {
        if (clientID.isEmpty() || clientID == "dynamic_agent_client" || nonce.isEmpty()) throw IdTokenError.InvalidClaims
        val parts = token.split(".")
        if (parts.size != 3) throw IdTokenError.InvalidToken
        val header = parse(parts[0]) ?: throw IdTokenError.InvalidToken
        if (header.opt("alg") != "RS256" || header.has("crit") || header.has("b64")) throw IdTokenError.UnsupportedAlgorithm
        val kid = (header.opt("kid") as? String)?.takeIf { it.isNotEmpty() } ?: throw IdTokenError.MissingKey

        val signature = Signature.getInstance("SHA256withRSA").apply {
            initVerify(key(jwks, kid))
            update("${parts[0]}.${parts[1]}".toByteArray(Charsets.US_ASCII))
        }
        val verified = try { signature.verify(decode(parts[2])) } catch (_: Exception) { false }
        if (!verified) throw IdTokenError.InvalidSignature

        val claims = parse(parts[1]) ?: throw IdTokenError.InvalidClaims
        val issuer = claims.opt("iss") as? String
        val subject = claims.opt("sub") as? String
        val audience = when (val aud = claims.opt("aud")) {
            is String -> listOf(aud)
            is JSONArray -> List(aud.length()) { aud.opt(it) as? String ?: throw IdTokenError.InvalidClaims }
            else -> throw IdTokenError.InvalidClaims
        }
        val azp = claims.opt("azp")
        val exp = integer(claims, "exp")
        val iat = integer(claims, "iat")
        val nbf = if (claims.opt("nbf") == null) null else integer(claims, "nbf") ?: throw IdTokenError.InvalidClaims
        val valid = issuer == ISSUER && subject != null && subject.isNotBlank() &&
            clientID in audience && claims.opt("nonce") == nonce &&
            (audience.size <= 1 || azp == clientID) && (azp == null || azp == clientID) &&
            exp != null && iat != null && exp > nowSec - 5 && iat <= nowSec + 5 && iat > 0 && exp > iat &&
            (nbf == null || nbf <= nowSec + 5)
        if (!valid) throw IdTokenError.InvalidClaims
        return VerifiedIdentity(issuer, subject)
    }

    private fun key(jwks: String, kid: String): PublicKey {
        val keys = try { JSONObject(jwks).getJSONArray("keys") } catch (_: Exception) { throw IdTokenError.InvalidKey }
        val matching = List(keys.length()) { keys.optJSONObject(it) }.filter { it?.opt("kid") == kid }
        if (matching.isEmpty()) throw IdTokenError.UnknownKey
        val jwk = matching.singleOrNull() ?: throw IdTokenError.InvalidKey
        val ops = jwk.opt("key_ops")
        if (jwk.opt("kty") != "RSA" || jwk.opt("alg").let { it != null && it != "RS256" } ||
            jwk.opt("use").let { it != null && it != "sig" } ||
            (ops != null && !(ops is JSONArray && ops.length() == 1 && ops.opt(0) == "verify"))) throw IdTokenError.InvalidKey
        return try {
            val spec = RSAPublicKeySpec(BigInteger(1, decode(jwk.getString("n"))), BigInteger(1, decode(jwk.getString("e"))))
            KeyFactory.getInstance("RSA").generatePublic(spec)
        } catch (_: Exception) { throw IdTokenError.InvalidKey }
    }

    // JSON numbers like 1.5 or 1e9 are not NumericDate integers here.
    private fun integer(json: JSONObject, name: String) =
        json.opt(name).let { if (it is Int || it is Long) (it as Number).toLong() else null }

    private fun parse(segment: String) = try { JSONObject(String(decode(segment), Charsets.UTF_8)) } catch (_: Exception) { null }

    private fun decode(segment: String): ByteArray = Base64.getUrlDecoder().decode(segment)
}
