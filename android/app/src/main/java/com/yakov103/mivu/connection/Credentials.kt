package com.yakov103.mivu.connection

import java.security.MessageDigest
import org.json.JSONArray

data class VerifiedIdentity(val issuer: String, val subject: String)

data class AccountRegistration(val identity: VerifiedIdentity, val issuedClientID: String) {
    // Same bytes as iOS JSONEncoder, which escapes every "/".
    val id: String
        get() = JSONArray(listOf(identity.issuer, identity.subject, issuedClientID)).toString()
            .replace("<\\/", "</").replace("/", "\\/")
            .let { MessageDigest.getInstance("SHA-256").digest(it.toByteArray()) }
            .joinToString("") { "%02x".format(it) }
}

data class Credentials(
    val registration: AccountRegistration,
    val accessToken: String,
    val refreshToken: String?,
    val idToken: String,
    val scopes: Set<String>,
    val expiresAtEpochSec: Long,
) {
    val planPermissionGranted get() = scopes.containsAll(setOf("resource.invoke", "chatgpt.tokens.use.direct"))

    override fun toString() = "Credentials(registration=$registration, scopes=$scopes, expiresAtEpochSec=$expiresAtEpochSec)"
}

interface CredentialStoring {
    fun hostID(): String
    fun registrations(): List<AccountRegistration>
    fun load(registrationID: String): Credentials?
    fun replace(credentials: Credentials)
    fun delete(registrationID: String)
}
