package com.yakov103.mivu.ui.coach

import java.io.File
import java.nio.file.Files
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

/** Synthetic reports only. */
class CoachReportsTest {
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
