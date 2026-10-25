package com.yakov103.mivu.day

import android.Manifest
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.app.Notification
import androidx.core.content.edit
import androidx.test.core.app.ApplicationProvider
import androidx.test.rule.GrantPermissionRule
import com.yakov103.mivu.R
import com.yakov103.mivu.diary.DiaryRepository
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test

class MorningReminderReceiverTest {
    @get:Rule val notifications: GrantPermissionRule = GrantPermissionRule.grant(Manifest.permission.POST_NOTIFICATIONS)
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val prefs = DiaryRepository.preferences(context)
    private val manager = context.getSystemService(NotificationManager::class.java)

    @Before @After fun reset() {
        MorningReminder.cancel(context)
        manager.cancelAll()
        prefs.edit(commit = true) { remove(MorningReminder.ENABLED); remove(MorningReminder.MINUTES) }
    }

    private fun scheduled(): PendingIntent? = PendingIntent.getBroadcast(context, MorningReminder.REQUEST,
        Intent(context, MorningReminderReceiver::class.java).setAction(MorningReminder.ACTION),
        PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE)

    private fun posted() = manager.activeNotifications.firstOrNull { it.id == 4 }

    private fun enable(on: Boolean) = prefs.edit(commit = true) { putBoolean(MorningReminder.ENABLED, on) }

    @Test fun turningOnSchedulesAndOffCancels() {
        enable(true)
        MorningReminder.schedule(context)
        assertNotNull(scheduled())
        enable(false)
        MorningReminder.cancel(context)
        assertNull(scheduled())
    }

    @Test fun alarmPostsTheMorningNotification() {
        enable(true)
        MorningReminderReceiver().onReceive(context, Intent(context, MorningReminderReceiver::class.java).setAction(MorningReminder.ACTION))
        val notification = checkNotNull(posted()).notification
        assertEquals("Good morning", notification.extras.getString(Notification.EXTRA_TITLE))
        assertEquals("Log your weight or breakfast.", notification.extras.getCharSequence(Notification.EXTRA_TEXT).toString())
        assertEquals("morning", notification.channelId)
        assertEquals(R.drawable.ic_stat_pip, notification.smallIcon.resId)
        assertTrue(notification.flags and Notification.FLAG_AUTO_CANCEL != 0)
        assertNotNull(notification.contentIntent)
        assertNotNull(scheduled()) // the next morning is booked
    }

    @Test fun bootReschedulesWithoutPosting() {
        enable(true)
        for (action in listOf(Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_TIME_CHANGED, Intent.ACTION_TIMEZONE_CHANGED)) {
            MorningReminder.cancel(context)
            MorningReminderReceiver().onReceive(context, Intent(action))
            assertNotNull(action, scheduled())
        }
        assertNull(posted())
    }

    @Test fun disabledReceiverPostsNothing() {
        MorningReminderReceiver().onReceive(context, Intent(context, MorningReminderReceiver::class.java).setAction(MorningReminder.ACTION))
        MorningReminderReceiver().onReceive(context, Intent(Intent.ACTION_BOOT_COMPLETED))
        assertNull(posted())
        assertNull(scheduled())
    }
}
