package com.yakov103.mivu.connection

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import java.io.File
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class CredentialStoreTest {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val store get() = CredentialStore(context)

    @Before @After fun clean() { File(context.noBackupFilesDir, "accounts").deleteRecursively() }

    private fun credentials(issuer: String = "https://auth.openai.com", client: String = "client_1", access: String = "access-secret-123") =
        Credentials(AccountRegistration(VerifiedIdentity(issuer, "user@example.com"), client), access, "refresh-secret", "id.token.value", setOf("resource.invoke"), 1_900_000_000)

    @Test fun hostIDIsStableUrnUuid() {
        val id = store.hostID()
        assertTrue(Regex("^urn:uuid:[0-9a-f-]{36}$").matches(id))
        assertEquals(id, store.hostID())
    }

    @Test fun replaceThenLoadRoundTripsAndListsRegistration() {
        val c = credentials()
        store.replace(c)
        assertEquals(c, store.load(c.registration.id))
        assertEquals(listOf(c.registration), store.registrations())
    }

    @Test fun foreignIssuerOrDynamicClientLoadsAsNull() {
        for (c in listOf(credentials(issuer = "https://evil.example"), credentials(client = "dynamic_agent_client"), credentials(client = ""))) {
            store.replace(c)
            assertNull(store.load(c.registration.id))
        }
    }

    @Test fun deleteRemovesCredentialsButKeepsRegistration() {
        val c = credentials()
        store.replace(c)
        store.delete(c.registration.id)
        assertNull(store.load(c.registration.id))
        assertEquals(1, store.registrations().size)
    }

    @Test fun filesAreEncryptedUnderNoBackupDirWithoutIdentityInNames() {
        store.replace(credentials())
        val files = File(context.noBackupFilesDir, "accounts").listFiles()!!
        assertTrue(files.isNotEmpty())
        for (f in files) {
            val bytes = f.readBytes().toString(Charsets.ISO_8859_1)
            assertFalse(bytes.contains("access-secret-123"))
            assertFalse(bytes.contains("user@example.com"))
            assertFalse(f.name.contains("example.com"))
        }
        assertNotNull(files.firstOrNull { it.name.startsWith("credentials-") })
    }
}
