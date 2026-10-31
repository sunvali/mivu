package com.yakov103.mivu

import android.content.Intent
import android.graphics.drawable.AdaptiveIconDrawable
import android.os.Build
import androidx.test.core.app.ApplicationProvider
import android.content.Context
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test

class AppIconTest {
    private val context: Context = ApplicationProvider.getApplicationContext()

    @Test fun launcherIconIsAdaptiveWithMonochrome() {
        val info = context.packageManager.getApplicationInfo(context.packageName, 0)
        assertNotEquals(0, info.icon)
        val icon = info.loadIcon(context.packageManager)
        assertTrue(icon is AdaptiveIconDrawable)
        assumeTrue(Build.VERSION.SDK_INT >= 33)
        assertNotNull((icon as AdaptiveIconDrawable).monochrome)
    }

    @Test fun launcherActivityUsesTheIcon() {
        val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER).setPackage(context.packageName)
        val resolved = context.packageManager.queryIntentActivities(launcher, 0)
            .single { it.activityInfo.name == MainActivity::class.java.name } // debug builds add tool launchers
        assertEquals(R.mipmap.ic_launcher, resolved.iconResource)
    }
}
