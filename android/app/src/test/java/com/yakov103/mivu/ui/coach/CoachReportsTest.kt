package com.yakov103.mivu.ui.coach

import com.sun.net.httpserver.HttpServer
import java.io.File
import java.net.InetSocketAddress
import java.nio.file.Files
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Synthetic reports only. */
class CoachReportsTest {
    @Test fun sendPostsOnlyTheReportAndReadsTheStatus() {
        val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
        var status = 204
        var seen = JSONObject()
        var type: String? = null
        server.createContext("/") { ex ->
            seen = JSONObject(ex.requestBody.readBytes().decodeToString())
            type = ex.requestHeaders.getFirst("Content-Type")
            ex.sendResponseHeaders(status, -1)
            ex.close()
        }
        server.start()
        val url = "http://127.0.0.1:${server.address.port}/"
        try {
            val body = CoachReports.body("Synthetic reply", "Something else", " Synthetic note ", "Android 0.0.0")
            assertTrue(CoachReports.send(body, url))
            assertEquals(setOf("reply", "reason", "note", "app"), seen.keys().asSequence().toSet())
            assertEquals("Synthetic reply", seen.getString("reply"))
            assertEquals("Something else", seen.getString("reason"))
            assertEquals("Synthetic note", seen.getString("note"))
            assertEquals("Android 0.0.0", seen.getString("app"))
            assertEquals("application/json; charset=utf-8", type)
            status = 500
            assertFalse(CoachReports.send(body, url))
        } finally {
            server.stop(0)
        }
        assertFalse(CoachReports.send(JSONObject(), url)) // nothing listening
    }

    @Test fun keepsTheNewestLinesAndSkipsATornOne() {
        val dir = Files.createTempDirectory("reports").toFile()
        val file = File(dir, "coach-reports.jsonl")
        file.writeText("{\"turnID\":\"torn")
        repeat(CoachReports.MAX_LINES + 5) { CoachReports.append(file, JSONObject().put("n", it)) }
        val kept = CoachReports.read(file)
        assertEquals((5 until CoachReports.MAX_LINES + 5).toList(), kept.map { it.getInt("n") })
        assertFalse(File(dir, "coach-reports.jsonl.tmp").exists())
        val big = "x".repeat(4_000)
        repeat(100) { CoachReports.append(file, JSONObject().put("n", it).put("note", big)) }
        assert(file.length() <= CoachReports.MAX_BYTES)
        assertEquals(99, CoachReports.read(file).last().getInt("n"))
        dir.deleteRecursively()
    }
}
