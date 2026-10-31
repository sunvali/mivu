package com.yakov103.mivu.connection

import java.security.KeyPairGenerator
import java.security.PrivateKey
import java.security.Signature
import java.security.interfaces.RSAPublicKey
import java.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

/** Synthetic RSA signer and JWKS; never a real account or key. */
class SyntheticIdentity(val kid: String = "synthetic-key") {
    val now = 1_800_000_000L
    val clientID = "oaiapp_synthetic"
    val nonce = "synthetic-nonce"
    private val pair = KeyPairGenerator.getInstance("RSA").apply { initialize(2048) }.generateKeyPair()
    val jwks: String = JSONObject().put("keys", JSONArray().put(jwk(pair.public as RSAPublicKey, kid))).toString()

    fun token(
        claims: Map<String, Any?> = emptyMap(),
        header: Map<String, Any?> = emptyMap(),
        key: PrivateKey = pair.private,
    ): String {
        val body = JSONObject(mapOf("iss" to "https://auth.openai.com", "sub" to "synthetic-account",
            "aud" to clientID, "iat" to now - 10, "exp" to now + 300, "nonce" to nonce) + claims)
        val head = JSONObject(mapOf("alg" to "RS256", "kid" to "synthetic-key") + header)
        val input = "${encode(head.toString().toByteArray())}.${encode(body.toString().toByteArray())}"
        val signature = Signature.getInstance("SHA256withRSA").run {
            initSign(key); update(input.toByteArray()); sign()
        }
        return "$input.${encode(signature)}"
    }

    companion object {
        fun encode(bytes: ByteArray): String = Base64.getUrlEncoder().withoutPadding().encodeToString(bytes)
        private fun unsigned(n: java.math.BigInteger) = n.toByteArray().let { if (it[0] == 0.toByte()) it.drop(1).toByteArray() else it }
        fun jwk(key: RSAPublicKey, kid: String): JSONObject = JSONObject().put("kty", "RSA").put("kid", kid)
            .put("use", "sig").put("alg", "RS256")
            .put("n", encode(unsigned(key.modulus))).put("e", encode(unsigned(key.publicExponent)))
    }
}

class IdTokenValidatorTest {
    private val fixture = SyntheticIdentity()

    private fun validate(token: String, jwks: String = fixture.jwks) =
        IdTokenValidator.validate(token, jwks, fixture.clientID, fixture.nonce, fixture.now)

    private fun rejects(expected: Class<out IdTokenError>, token: String, jwks: String = fixture.jwks) {
        assertThrows(expected) { validate(token, jwks) }
    }

    @Test fun acceptsTokenSignedByServedKey() {
        assertEquals(VerifiedIdentity("https://auth.openai.com", "synthetic-account"), validate(fixture.token()))
    }

    @Test fun acceptsFiveSecondSkewAndArrayAudienceWithAuthorizedParty() {
        validate(fixture.token(mapOf("iat" to fixture.now + 5,
            "aud" to JSONArray(listOf(fixture.clientID, "oaiapp_other")), "azp" to fixture.clientID)))
    }

    @Test fun rejectsMalformedToken() = rejects(IdTokenError.InvalidToken::class.java, "invalid")

    @Test fun rejectsAlgorithmsOtherThanRs256() {
        for (alg in listOf("HS256", "none", "RS512")) {
            rejects(IdTokenError.UnsupportedAlgorithm::class.java, fixture.token(header = mapOf("alg" to alg)))
        }
        rejects(IdTokenError.UnsupportedAlgorithm::class.java, fixture.token(header = mapOf("crit" to JSONArray(listOf("b64")))))
    }

    @Test fun rejectsMissingAndUnknownKey() {
        rejects(IdTokenError.MissingKey::class.java, fixture.token(header = mapOf("kid" to "")))
        rejects(IdTokenError.UnknownKey::class.java, fixture.token(header = mapOf("kid" to "other-key")))
    }

    @Test fun rejectsInvalidKeyMetadata() {
        val key = JSONObject(fixture.jwks).getJSONArray("keys").getJSONObject(0)
        for ((name, value) in listOf("kty" to "EC", "alg" to "RS512", "use" to "enc", "key_ops" to JSONArray(listOf("sign")))) {
            val changed = JSONObject(key.toString()).put(name, value)
            rejects(IdTokenError.InvalidKey::class.java, fixture.token(), JSONObject().put("keys", JSONArray().put(changed)).toString())
        }
        rejects(IdTokenError.InvalidKey::class.java, fixture.token(), JSONObject().put("keys", JSONArray().put(key).put(key)).toString())
    }

    @Test fun rejectsBadSignature() {
        val token = fixture.token()
        val parts = token.split(".")
        val tampered = SyntheticIdentity.encode(
            JSONObject(String(Base64.getUrlDecoder().decode(parts[1]))).put("sub", "other-account").toString().toByteArray())
        rejects(IdTokenError.InvalidSignature::class.java, "${parts[0]}.$tampered.${parts[2]}")
        val otherKey = KeyPairGenerator.getInstance("RSA").apply { initialize(2048) }.generateKeyPair().private
        rejects(IdTokenError.InvalidSignature::class.java, fixture.token(key = otherKey))
    }

    @Test fun rejectsInvalidClaims() {
        val now = fixture.now
        val changes = listOf(
            mapOf("iss" to "https://untrusted.example"), mapOf("sub" to "  "), mapOf("aud" to "oaiapp_other"),
            mapOf("nonce" to "another-nonce"), mapOf("exp" to now - 6, "iat" to now - 60), mapOf("iat" to now + 6),
            mapOf("iat" to JSONObject.NULL), mapOf("iat" to now - 0.5), mapOf("nbf" to now + 6),
            mapOf("aud" to JSONArray(listOf(fixture.clientID, "oaiapp_other"))),
        )
        for (change in changes) rejects(IdTokenError.InvalidClaims::class.java, fixture.token(change))
    }
}
