package com.yakov103.mivu.connection

import java.net.InetAddress
import java.net.Socket
import java.net.URI
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class LoopbackCallbackTest {
    private fun send(base: String, raw: (String) -> String): String {
        val uri = URI(base)
        Socket(InetAddress.getByName("127.0.0.1"), uri.port).use {
            it.soTimeout = 5000
            it.getOutputStream().write(raw(uri.authority).toByteArray())
            return it.getInputStream().readBytes().toString(Charsets.UTF_8)
        }
    }

    private fun get(base: String, target: String) =
        send(base) { "GET $target HTTP/1.1\r\nHost: $it\r\n\r\n" }

    @Test fun startBindsLoopbackCallbackPath() = LoopbackCallback().use {
        val url = URI(it.start())
        assertEquals("127.0.0.1", url.host)
        assertEquals("/auth/callback", url.path)
        assertTrue(url.port > 0)
    }

    @Test fun validCallbackCompletesAwaitWithQueryIntact() = runBlocking {
        LoopbackCallback().use {
            val base = it.start()
            val waiting = async(start = CoroutineStart.UNDISPATCHED) { it.await() }
            val response = get(base, "/auth/callback?code=c&state=s")
            assertEquals("$base?code=c&state=s", withTimeout(5000) { waiting.await() })
            assertTrue(response.startsWith("HTTP/1.1 200 OK\r\n"))
            assertTrue(response.contains("Content-Type: text/plain; charset=utf-8"))
            assertTrue(response.contains("Connection: close"))
            assertTrue(response.endsWith("\r\n\r\nYou can return to Mivu."))
        }
    }

    @Test fun invalidRequestsGetBadRequestAndDoNotComplete() = runBlocking {
        LoopbackCallback().use {
            val base = it.start()
            val waiting = async(start = CoroutineStart.UNDISPATCHED) { it.await() }
            val bad = listOf(
                get(base, "/other?code=c"),
                send(base) { h -> "POST /auth/callback HTTP/1.1\r\nHost: $h\r\n\r\n" },
                send(base) { h -> "GET /auth/callback HTTP/1.0\r\nHost: $h\r\n\r\n" },
                send(base) { "garbage\r\n\r\n" },
                send(base) { h -> "GET /auth/callback HTTP/1.1\r\nHost: $h\r\nX: ${"a".repeat(16400)}\r\n\r\n" },
            )
            bad.forEach { r ->
                assertTrue(r, r.startsWith("HTTP/1.1 400 Bad Request\r\n"))
                assertTrue(r.endsWith("\r\n\r\nInvalid request."))
            }
            assertFalse(waiting.isCompleted)
            get(base, "/auth/callback?code=ok")
            assertEquals("$base?code=ok", withTimeout(5000) { waiting.await() })
        }
    }

    @Test fun closeCancelsAwait() = runBlocking {
        val callback = LoopbackCallback()
        callback.start()
        val waiting = async(start = CoroutineStart.UNDISPATCHED) { callback.await() }
        callback.close()
        try {
            withTimeout(5000) { waiting.await() }
            fail("expected cancellation")
        } catch (_: CancellationException) {
        }
    }

    @Test fun secondConcurrentAwaitFails() = runBlocking {
        LoopbackCallback().use {
            it.start()
            val first = async(start = CoroutineStart.UNDISPATCHED) { it.await() }
            try {
                it.await()
                fail("expected IllegalStateException")
            } catch (_: IllegalStateException) {
            }
            first.cancel()
        }
    }
}
