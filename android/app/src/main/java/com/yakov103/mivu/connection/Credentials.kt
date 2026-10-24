package com.yakov103.mivu.connection

import java.security.MessageDigest

data class VerifiedIdentity(val issuer: String, val subject: String)

data class AccountRegistration(val identity: VerifiedIdentity, val issuedClientID: String) {
    // Encoded by hand to match iOS JSONEncoder bytes; org.json escaping differs between device and JVM.
    val id: String
        get() = listOf(identity.issuer, identity.subject, issuedClientID).joinToString(",", "[", "]", transform = ::json)
            .let { MessageDigest.getInstance("SHA-256").digest(it.toByteArray()) }
            .joinToString("") { "%02x".format(it) }
}

private fun json(value: String) = buildString {
    append('"')
    for (c in value) when (c) {
        '"' -> append("\\\"")
        '\\' -> append("\\\\")
        '/' -> append("\\/")
        '\n' -> append("\\n")
        '\r' -> append("\\r")
        '\t' -> append("\\t")
        '\b' -> append("\\b")
        '\u000C' -> append("\\f")
        else -> if (c < ' ') append("\\u%04x".format(c.code)) else append(c)
    }
    append('"')
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
