package com.yakov103.mivu.release

import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.TextView
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.platform.app.InstrumentationRegistry
import com.yakov103.mivu.R
import com.yakov103.mivu.SampleMode
import com.yakov103.mivu.diary.DiaryArchive
import com.yakov103.mivu.diary.PhotoSpool
import com.yakov103.mivu.share.ShareToCoachActivity
import com.yakov103.mivu.widget.CaloriesWidget
import com.yakov103.mivu.widget.WidgetSnapshot
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The minified build's smoke test: `./gradlew :app:connectedAndroidTest -Pmivu.testBuildType=release` with
 * `-Pandroid.testInstrumentationRunnerArguments.class=com.yakov103.mivu.release.ReleaseSmokeTest`. Synthetic data only;
 * androidx.test and platform APIs only, as the Compose test manifest is debug-only.
 */
class ReleaseSmokeTest {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private fun fixture(name: String) = javaClass.classLoader!!.getResourceAsStream("archive/$name")

    private fun <T> spooled(block: (PhotoSpool) -> T) = PhotoSpool(File(context.cacheDir, "smoke-${UUID.randomUUID()}")).use(block)

    @Test fun androidAndIosFixturesDecode() {
        for (name in listOf("android-v4-full.json", "ios-v4-full.json")) spooled { spool ->
            val snapshot = DiaryArchive.decode(fixture(name), spool)
            assertEquals(name, UUID.fromString("00000000-0000-0000-0000-000000000001"), snapshot.profile.id)
            assertEquals(name, 4, snapshot.meals.size)
            assertEquals(name, 4, (snapshot.meals.flatMap { it.photos } + snapshot.coachTurns.flatMap { it.photos }).map { it.id }.toSet().size)
        }
        spooled { spool ->
            val golden = fixture("android-v4-full.json").readBytes().decodeToString()
            val out = ByteArrayOutputStream()
            DiaryArchive.encode(DiaryArchive.decode(golden.byteInputStream(), spool), out, spool::bytes)
            // Byte-for-byte, so also the same JSON value; the fixture writer adds one newline after the archive.
            assertEquals(golden, out.toString(Charsets.UTF_8.name()) + "\n")
        }
    }

    /** Reports the median of five decodes of the iOS fixture as `archiveReadMs`; the figure goes in the release record. */
    @Test fun archiveReadTime() {
        val bytes = fixture("ios-v4-full.json").readBytes()
        val ms = (1..5).map {
            spooled { spool ->
                val started = System.nanoTime()
                DiaryArchive.decode(bytes.inputStream(), spool)
                (System.nanoTime() - started) / 1_000_000
            }
        }.sorted()[2]
        InstrumentationRegistry.getInstrumentation().sendStatus(0, Bundle().apply { putLong("archiveReadMs", ms) })
    }

    @Test fun widgetDrawsUnderR8() {
        val now = System.currentTimeMillis()
        val day = WidgetSnapshot("2026-10-25", 1360.0, 2100.0, true, rolloverAt = now + 3_600_000, writtenAt = now)
        for (views in listOf(CaloriesWidget.small(context, day, now), CaloriesWidget.medium(context, day, now))) {
            val parent = FrameLayout(context)
            parent.addView(views.apply(context, parent), ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
            assertEquals("1,360", parent.findViewById<TextView>(R.id.widget_eaten).text.toString())
            assertEquals(View.VISIBLE, parent.findViewById<View>(R.id.widget_figure).visibility)
        }
    }

    @Test fun shareSheetOpens() {
        val share = Intent(Intent.ACTION_SEND).setClass(context, ShareToCoachActivity::class.java)
            .setType("text/plain").putExtra(Intent.EXTRA_TEXT, "two boiled eggs and a slice of toast")
        ActivityScenario.launch<ShareToCoachActivity>(share).use { assertEquals(Lifecycle.State.RESUMED, it.state) }
    }

    @Test fun releaseShipsNoDebugComponents() {
        // Only the release build is under test; the debug build ships these by design.
        if (InstrumentationRegistry.getArguments().getString("mivuTestBuildType") != "release") return
        val pm = context.packageManager
        val activities = pm.getPackageInfo(context.packageName, PackageManager.PackageInfoFlags.of(PackageManager.GET_ACTIVITIES.toLong()))
            .activities.orEmpty().map { it.name.substringAfterLast('.') }
        for (debugOnly in listOf("ConnectionProofActivity", "CaptureProbeActivity", "PipRigPreviewActivity")) {
            assertFalse(activities.toString(), debugOnly in activities)
        }
        val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER).setPackage(context.packageName)
        assertEquals(1, pm.queryIntentActivities(launcher, PackageManager.ResolveInfoFlags.of(0)).size)
        assertFalse(SampleMode.enabled)
        val flags = context.applicationInfo.flags
        assertEquals(0, flags and ApplicationInfo.FLAG_DEBUGGABLE)
        assertTrue(flags and ApplicationInfo.FLAG_ALLOW_BACKUP != 0)
    }
}
