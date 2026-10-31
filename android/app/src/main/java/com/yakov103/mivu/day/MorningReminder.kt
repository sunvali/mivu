package com.yakov103.mivu.day

import android.Manifest
import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationChannelCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.yakov103.mivu.R
import com.yakov103.mivu.diary.DiaryRepository
import java.time.ZonedDateTime

// Port of ios/Mivu/Diary/DaySettingsSection.swift MorningReminder and MorningCheckInCard.greeting.

/** iOS check-in greeting for the hour of the day. */
fun greeting(hour: Int): String = when (hour) {
    in 5..11 -> "Good morning"
    in 12..17 -> "Good afternoon"
    else -> "Good evening"
}

/** The optional daily morning notification, off until the person turns it on in Settings. */
object MorningReminder {
    const val ENABLED = "morningReminder"
    const val MINUTES = "morningReminderMinutes"
    const val ACTION = "com.yakov103.mivu.action.MORNING_REMINDER"
    const val REQUEST = 4
    private const val CHANNEL = "morning"
    private const val NOTIFICATION_ID = 4
    private const val WINDOW_MS = 10 * 60_000L

    /** Today at [minutes] past midnight if that is still ahead of [now], else tomorrow; wall-clock time across DST. */
    fun nextTrigger(now: ZonedDateTime, minutes: Int): ZonedDateTime {
        val today = now.toLocalDate().atTime(minutes / 60, minutes % 60).atZone(now.zone)
        return if (today.isAfter(now)) today else now.toLocalDate().plusDays(1).atTime(minutes / 60, minutes % 60).atZone(now.zone)
    }

    /** Books the next reminder when it is on; one alarm, replaced on every call. */
    fun schedule(context: Context) {
        val prefs = DiaryRepository.preferences(context)
        if (!prefs.getBoolean(ENABLED, false)) return cancel(context)
        val at = nextTrigger(ZonedDateTime.now(), prefs.getInt(MINUTES, 8 * 60)).toInstant().toEpochMilli()
        // inexact by design: a reminder needs no exact-alarm permission.
        context.getSystemService(AlarmManager::class.java).setWindow(AlarmManager.RTC_WAKEUP, at, WINDOW_MS, alarm(context))
    }

    fun cancel(context: Context) {
        val pending = alarm(context)
        context.getSystemService(AlarmManager::class.java).cancel(pending)
        pending.cancel()
    }

    /** iOS copy only: no diary data on the lock screen. Tapping opens the app on Today. */
    fun post(context: Context) {
        if (Build.VERSION.SDK_INT >= 33 &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return
        val manager = NotificationManagerCompat.from(context)
        manager.createNotificationChannel(
            NotificationChannelCompat.Builder(CHANNEL, NotificationManagerCompat.IMPORTANCE_DEFAULT).setName("Morning check-in").build())
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName) ?: return
        val open = PendingIntent.getActivity(context, REQUEST, launch, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val notification = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_pip)
            .setContentTitle("Good morning")
            .setContentText("Log your weight or breakfast.")
            .setContentIntent(open)
            .setAutoCancel(true)
            .build()
        manager.notify(NOTIFICATION_ID, notification)
    }

    private fun alarm(context: Context): PendingIntent = PendingIntent.getBroadcast(context, REQUEST,
        Intent(context, MorningReminderReceiver::class.java).setAction(ACTION), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
}

/** Posts on its own alarm, then books the next one; boot, clock, zone and app-update broadcasts only reschedule. */
class MorningReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (!DiaryRepository.preferences(context).getBoolean(MorningReminder.ENABLED, false)) return
        if (intent.action == MorningReminder.ACTION) MorningReminder.post(context)
        MorningReminder.schedule(context)
    }
}
