package com.yakov103.mivu.connection

import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.CompletableDeferred

/** One-shot HTTP/1.1 listener on 127.0.0.1 that receives the sign-in redirect; never logs the URL (it holds the code). */
class LoopbackCallback : AutoCloseable {
    private val result = CompletableDeferred<String>()
    private val waiting = AtomicBoolean(false)
    private var server: ServerSocket? = null

    fun start(): String {
        check(server == null) { "already started" }
        val socket = ServerSocket(0, 1, InetAddress.getByName("127.0.0.1"))
        server = socket
        val base = "http://127.0.0.1:${socket.localPort}"
        // shortcut: connections are served one at a time (each capped at 5 s); fine for a single browser redirect.
        Thread { serve(socket, base) }.apply { isDaemon = true }.start()
        return "$base$PATH"
    }

    suspend fun await(): String {
        check(waiting.compareAndSet(false, true)) { "already waiting" }
        try {
            return result.await()
        } finally {
            waiting.set(false)
        }
    }

    override fun close() {
        server?.close()
        result.cancel()
    }

    private fun serve(socket: ServerSocket, base: String) {
        while (!socket.isClosed) {
            try {
                socket.accept().use { handle(it, base) }
            } catch (_: Exception) {
                // closed listener or a broken client; keep serving until closed
            }
        }
    }

    private fun handle(client: Socket, base: String) {
        client.soTimeout = 5000
        val target = readTarget(client)
        val ok = target != null
        // Signed in: send the browser straight back to Mivu (MainActivity's mivu://connected filter); the link is the fallback.
        val body = if (ok) "<a href=\"$RETURN\">Return to Mivu</a>" else "Invalid request."
        val head = if (ok) "302 Found\r\nLocation: $RETURN\r\nContent-Type: text/html" else "400 Bad Request\r\nContent-Type: text/plain"
        client.getOutputStream().apply {
            write(
                ("HTTP/1.1 $head; charset=utf-8\r\n" +
                    "Content-Length: ${body.length}\r\nConnection: close\r\n\r\n$body").toByteArray(),
            )
            flush()
        }
        // Drain unread request bytes so closing does not reset the connection and drop the response.
        client.shutdownOutput()
        client.soTimeout = 200
        try { client.getInputStream().readBytes() } catch (_: java.io.IOException) {}
        if (target != null) result.complete("$base$target")
    }

    /** Request target if the head is a valid GET of the callback path, else null. */
    private fun readTarget(client: Socket): String? {
        val input = client.getInputStream()
        val head = java.io.ByteArrayOutputStream()
        while (head.size() <= MAX_HEAD) {
            val b = input.read()
            if (b < 0) return null
            head.write(b)
            if (head.size() >= 4 && head.toByteArray().toString(Charsets.ISO_8859_1).endsWith("\r\n\r\n")) break
        }
        if (head.size() > MAX_HEAD) return null
        val parts = head.toByteArray().toString(Charsets.ISO_8859_1).substringBefore("\r\n").split(" ")
        if (parts.size != 3 || parts[0] != "GET" || parts[2] != "HTTP/1.1") return null
        val target = parts[1]
        if ('#' in target || target.substringBefore('?') != PATH) return null
        return target
    }

    private companion object {
        const val PATH = "/auth/callback"
        const val RETURN = "mivu://connected"
        const val MAX_HEAD = 16384
    }
}
