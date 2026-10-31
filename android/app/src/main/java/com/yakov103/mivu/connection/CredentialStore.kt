package com.yakov103.mivu.connection

import android.content.Context
import android.util.AtomicFile
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.io.File
import java.io.IOException
import java.security.KeyStore
import java.util.UUID
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject

class CredentialStoreException(message: String, cause: Throwable? = null) : IOException(message, cause)

/** Keystore-encrypted records under noBackupFilesDir; error messages never include record contents. */
class CredentialStore(context: Context, private val key: () -> SecretKey = ::keystoreKey) : CredentialStoring {
    private val dir = File(context.noBackupFilesDir, "accounts")

    // An unreadable or malformed host record is replaced: a new host ID for OpenAI is acceptable recovery.
    @Synchronized override fun hostID(): String {
        read("host")?.let { String(it) }?.takeIf { v -> v.startsWith("urn:uuid:") && runCatching { UUID.fromString(v.drop(9)) }.isSuccess }?.let { return it }
        return "urn:uuid:${UUID.randomUUID().toString().lowercase()}".also { write("host", it.toByteArray()) }
    }

    @Synchronized override fun registrations(): List<AccountRegistration> =
        (dir.listFiles { f -> f.name.startsWith("registration-") && f.name.endsWith(".bin") } ?: emptyArray())
            .mapNotNull { f ->
                val registration = read(f.name.removeSuffix(".bin"))?.let { try { decodeRegistration(JSONObject(String(it))) } catch (e: JSONException) { null } }
                    ?.takeIf { f.name == "registration-${it.id}.bin" }
                registration.also { if (it == null) f.delete() } // unreadable: drop; sign-in recreates it
            }.sortedBy { it.id }

    @Synchronized override fun load(registrationID: String): Credentials? {
        val bytes = read("credentials-$registrationID") ?: return null
        val c = try { decodeCredentials(JSONObject(String(bytes))) } catch (e: JSONException) { return null }
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

    // Null when absent or undecryptable (lost key, truncated file): callers treat both as signed out.
    private fun read(name: String): ByteArray? = try {
        AtomicFile(File(dir, "$name.bin")).takeIf { it.baseFile.exists() }?.let { decrypt(it.readFully()) }
    } catch (e: CredentialStoreException) { null }

    private fun write(name: String, plain: ByteArray) {
        dir.mkdirs()
        val bytes = encrypt(plain)
        val file = AtomicFile(File(dir, "$name.bin")) // fsyncs, then renames
        val out = file.startWrite()
        try { out.write(bytes); file.finishWrite(out) } catch (e: Throwable) { file.failWrite(out); throw e }
    }

    private fun encrypt(plain: ByteArray): ByteArray {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, key()) }
        return cipher.iv + cipher.doFinal(plain)
    }

    // Only corrupt data (bad tag, e.g. a regenerated key, or a short payload) counts as unreadable; Keystore failures propagate.
    private fun decrypt(data: ByteArray): ByteArray {
        if (data.size < 12 + 16) throw CredentialStoreException("record cannot be decrypted")
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, data, 0, 12)) }
        try { return cipher.doFinal(data, 12, data.size - 12) } catch (e: AEADBadTagException) {
            throw CredentialStoreException("record cannot be decrypted") // no cause: keep record bytes out of traces
        }
    }

}

private const val KEY_ALIAS = "mivu.account-sessions"

private fun keystoreKey(): SecretKey = synchronized(KEY_ALIAS) {
    val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
    (store.getKey(KEY_ALIAS, null) as? SecretKey) ?: KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").run {
        init(KeyGenParameterSpec.Builder(KEY_ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256).build())
        generateKey()
    }
}
