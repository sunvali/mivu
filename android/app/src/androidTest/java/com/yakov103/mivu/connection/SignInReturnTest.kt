package com.yakov103.mivu.connection

import android.app.ActivityManager
import android.content.Intent
import android.net.Uri
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import com.yakov103.mivu.MainActivity
import com.yakov103.mivu.ui.settings.openCustomTab
import org.junit.Assert.assertEquals
import org.junit.Assume.assumeTrue
import org.junit.Test

/** The ChatGPT sign-in tab must close once the page hands back to mivu://connected, not linger behind Mivu. */
class SignInReturnTest {
    private val context = ApplicationProvider.getApplicationContext<android.content.Context>()
    private val tasks = context.getSystemService(ActivityManager::class.java)

    @Test fun returningFromSignInClosesTheBrowserTab() {
        val browser = Intent(Intent.ACTION_VIEW, Uri.parse("https://example.com"))
        assumeTrue("needs a browser", context.packageManager.resolveActivity(browser, 0) != null)
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity { it.openCustomTab("about:blank") }
            waitFor("the sign-in tab opens above Mivu, in Mivu's task") { top()?.packageName != context.packageName }

            // What the sign-in page's redirect does; the browser starts it as a new task.
            context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("mivu://connected")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            waitFor("Mivu is back on top") { top()?.className == MainActivity::class.java.name }
            assertEquals("only Mivu is left in its task", 1, tasks.appTasks.single().taskInfo?.numActivities)
        }
    }

    private fun top() = tasks.appTasks.singleOrNull()?.taskInfo?.topActivity

    private fun waitFor(what: String, condition: () -> Boolean) {
        val end = System.currentTimeMillis() + 10_000
        while (!condition()) {
            check(System.currentTimeMillis() < end) { "timed out: $what" }
            Thread.sleep(100)
        }
    }
}
