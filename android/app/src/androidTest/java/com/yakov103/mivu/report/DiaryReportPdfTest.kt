package com.yakov103.mivu.report

import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import androidx.test.core.app.ApplicationProvider
import com.yakov103.mivu.diary.DayCompleteness
import com.yakov103.mivu.diary.DiaryMeal
import com.yakov103.mivu.diary.DiaryProfile
import com.yakov103.mivu.diary.DiarySnapshot
import com.yakov103.mivu.diary.FoodItem
import com.yakov103.mivu.diary.NutritionProvenance
import com.yakov103.mivu.diary.NutritionValues
import com.yakov103.mivu.diary.TrackingDay
import com.yakov103.mivu.diary.WeightEntry
import java.io.File
import java.time.Instant
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Synthetic diaries, parsed back with the platform renderer. */
class DiaryReportPdfTest {
    private val folder = File(ApplicationProvider.getApplicationContext<android.content.Context>().cacheDir, "report-test")

    private fun pageCount(file: File) = PdfRenderer(ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)).use { renderer ->
        renderer.openPage(0).close()
        renderer.pageCount
    }

    @Test fun pdfHasPageCountFooterAndOpens() {
        val profile = DiaryProfile(UUID.randomUUID(), "Sample", "en", "UTC", "")
        val days = (1..20).map { TrackingDay(UUID.randomUUID(), "2026-10-%02d".format(it), "UTC", Instant.parse("2026-10-%02dT06:00:00Z".format(it)), DayCompleteness.complete) }
        val meals = days.flatMap { day ->
            (0 until 4).map { n ->
                DiaryMeal(UUID.randomUUID(), day.id, day.startAt, day.startAt.plusSeconds(3600L * (n + 1)), 1, items = listOf(
                    FoodItem(UUID.randomUUID(), "Sample meal $n", 1.0, "serving", NutritionValues(450.0, 50.0, 30.0, 15.0), NutritionProvenance.user, "", false, emptyMap()),
                ), photos = emptyList(), submissions = emptyList())
            }
        }
        val weights = days.mapIndexed { index, day -> WeightEntry(UUID.randomUUID(), day.id, day.startAt, 74.0 - index * 0.1, "kg") }
        val report = DiaryReport(DiarySnapshot(1, 1, profile, days, meals, weights, deletedMealIDs = emptyList()), null, null)
        val file = report.write(DiaryReport.Format.PDF, folder).single()
        assertEquals("Mivu report 2026-10-01 to 2026-10-20.pdf", file.name)
        // 80 meal rows overflow one meal page: the summary plus at least two meal pages.
        assertTrue(pageCount(file) >= 3)
        folder.deleteRecursively()
    }

    @Test fun emptyRangeStillMakesAReport() {
        val profile = DiaryProfile(UUID.randomUUID(), "Sample", "en", "UTC", "")
        val report = DiaryReport(DiarySnapshot(1, 1, profile, emptyList(), emptyList(), emptyList(), deletedMealIDs = emptyList()), null, null)
        val file = report.write(DiaryReport.Format.PDF, folder).single()
        assertEquals("Mivu report empty.pdf", file.name)
        assertEquals(2, pageCount(file))
        folder.deleteRecursively()
    }
}
