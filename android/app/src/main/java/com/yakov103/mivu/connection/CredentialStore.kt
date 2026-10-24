package com.yakov103.mivu.connection

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.io.File
import java.io.IOException
import java.security.KeyStore
import java.util.UUID
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import org.json.JSONArray
import org.json.JSONObject

class CredentialStoreException(message: String, cause: Throwable? = null) : IOException(message, cause)

/** Keystore-encrypted records under noBackupFilesDir; error messages never include record contents. */
class CredentialStore(context: Context) : CredentialStoring {
    private val dir = File(context.noBackupFilesDir, "accounts")

    @Synchronized override fun hostID(): String {
        read("host")?.let { bytes ->
            val value = String(bytes)
            val uuid = value.removePrefix("urn:uuid:")
            if (!value.startsWith("urn:uuid:") || runCatching { UUID.fromString(uuid) }.isFailure) throw CredentialStoreException("invalid host record")
            return value
        }
        return "urn:uuid:${UUID.randomUUID().toString().lowercase()}".also { write("host", it.toByteArray()) }
    }

    @Synchronized override fun registrations(): List<AccountRegistration> =
        (dir.listFiles { f -> f.name.startsWith("registration-") && f.name.endsWith(".bin") } ?: emptyArray())
            .map { f ->
                val registration = decodeRegistration(JSONObject(String(decrypt(f.readBytes()))))
                if (f.name != "registration-${registration.id}.bin") throw CredentialStoreException("invalid registration record")
                registration
            }.sortedBy { it.id }

    @Synchronized override fun load(registrationID: String): Credentials? {
        val c = decodeCredentials(JSONObject(String(read("credentials-$registrationID") ?: return null)))
        val r = c.registration
        return c.takeIf {
            r.id == registrationID && r.identity.issuer == "https://auth.openai.com" && r.identity.subject.isNotEmpty() &&
                r.issuedClientID.isNotEmpty() && r.issuedClientID != "dynamic_agent_client" &&
                c.accessToken.isNotEmpty() && c.idToken.isNotEmpty()
        }
    }

    @Synchronized override fun replace(credentials: Credentials) {
        val id = credentials.registration.id
        write("registration-$id", encode(credentials.registration).toString().toByteArray())
        write("credentials-$id", JSONObject().put("registration", encode(credentials.registration)).put("accessToken", credentials.accessToken)
            .put("refreshToken", credentials.refreshToken ?: JSONObject.NULL).put("idToken", credentials.idToken)
            .put("scopes", JSONArray(credentials.scopes.sorted())).put("expiresAt", credentials.expiresAtEpochSec).toString().toByteArray())
    }

    // Like iOS, the registration record stays so the account can be re-listed after sign-out.
    @Synchronized override fun delete(registrationID: String) {
        if (!File(dir, "credentials-$registrationID.bin").delete() && File(dir, "credentials-$registrationID.bin").exists()) throw CredentialStoreException("delete failed")
    }

    private fun encode(r: AccountRegistration) =
        JSONObject().put("issuer", r.identity.issuer).put("subject", r.identity.subject).put("issuedClientID", r.issuedClientID)

    private fun decodeRegistration(o: JSONObject) =
        AccountRegistration(VerifiedIdentity(o.getString("issuer"), o.getString("subject")), o.getString("issuedClientID"))

    private fun decodeCredentials(o: JSONObject) = Credentials(
        decodeRegistration(o.getJSONObject("registration")), o.getString("accessToken"),
        if (o.isNull("refreshToken")) null else o.getString("refreshToken"), o.getString("idToken"),
        o.getJSONArray("scopes").let { a -> (0 until a.length()).map(a::getString).toSet() }, o.getLong("expiresAt"),
    )

    private fun read(name: String): ByteArray? =
        File(dir, "$name.bin").takeIf { it.exists() }?.let { decrypt(it.readBytes()) }

    private fun write(name: String, plain: ByteArray) {
        dir.mkdirs()
        val tmp = File(dir, "$name.tmp")
        tmp.writeBytes(encrypt(plain))
        if (!tmp.renameTo(File(dir, "$name.bin"))) throw CredentialStoreException("write failed")
    }

    private fun encrypt(plain: ByteArray): ByteArray {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, key()) }
        return cipher.iv + cipher.doFinal(plain)
    }

    private fun decrypt(data: ByteArray): ByteArray = try {
        Cipher.getInstance("AES/GCM/NoPadding").run {
            init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, data, 0, 12))
            doFinal(data, 12, data.size - 12)
        }
    } catch (e: Exception) {
        throw CredentialStoreException("record cannot be decrypted") // no cause: keep record bytes out of traces
    }

    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").run {
            init(KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256).build())
            generateKey()
        }
    }

    private companion object { const val ALIAS = "mivu.account-sessions" }
}
