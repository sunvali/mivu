package com.yakov103.mivu.widget

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.util.SizeF
import android.view.View
import android.widget.RemoteViews
import androidx.core.content.edit
import com.yakov103.mivu.R
import com.yakov103.mivu.quick.QuickAction
import com.yakov103.mivu.quick.quickIntent
import java.text.NumberFormat
import kotlin.math.roundToLong
import kotlinx.serialization.json.Json

// Port of ios/MivuWidgets/CaloriesWidget.swift (home-screen families) with platform RemoteViews.

/** The Calories widget: draws the stored [WidgetSnapshot], never the diary. */
object CaloriesWidget {
    private const val PREFS = "widget"
    private const val KEY = "caloriesSnapshot"
    private const val ROLLOVER_REQUEST = 20
    private const val WINDOW_MS = 10 * 60_000L

    fun stored(context: Context): WidgetSnapshot? = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, null)
        ?.let { runCatching { Json.decodeFromString(WidgetSnapshot.serializer(), it) }.getOrNull() }

    /** Stores [snapshot], redraws every placed widget and books the rollover. */
    fun publish(context: Context, snapshot: WidgetSnapshot) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit(commit = true) {
            putString(KEY, Json.encodeToString(WidgetSnapshot.serializer(), snapshot))
        }
        update(context, ids(context))
    }

    internal fun ids(context: Context): IntArray =
        AppWidgetManager.getInstance(context).getAppWidgetIds(ComponentName(context, CaloriesWidgetProvider::class.java))

    /** Draws [ids] from the stored snapshot; an inexact alarm redraws them once the waking day ends, as iOS's second entry. */
    internal fun update(context: Context, ids: IntArray) {
        if (ids.isEmpty()) return
        val now = System.currentTimeMillis()
        val snapshot = stored(context)
        AppWidgetManager.getInstance(context).updateAppWidget(ids, views(context, snapshot, now))
        val alarms = context.getSystemService(AlarmManager::class.java)
        val rollover = PendingIntent.getBroadcast(context, ROLLOVER_REQUEST,
            Intent(AppWidgetManager.ACTION_APPWIDGET_UPDATE).setClass(context, CaloriesWidgetProvider::class.java)
                .putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids(context)),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        // RTC, not a wakeup: a sleeping screen shows nothing, so the redraw can wait for the phone to wake.
        if (snapshot != null && snapshot.rolloverAt > now) alarms.setWindow(AlarmManager.RTC, snapshot.rolloverAt, WINDOW_MS, rollover)
        else alarms.cancel(rollover)
    }

    /**
     * The launcher picks the largest layout that fits. Medium needs iOS's systemMedium width (329 pt): narrower, its
     * 200 dp bar and buttons would run under Pip, so a three-cell widget keeps the small layout.
     */
    fun views(context: Context, snapshot: WidgetSnapshot?, nowMillis: Long): RemoteViews = RemoteViews(mapOf(
        SizeF(110f, 110f) to small(context, snapshot, nowMillis),
        SizeF(320f, 110f) to medium(context, snapshot, nowMillis),
    ))

    internal fun small(context: Context, snapshot: WidgetSnapshot?, nowMillis: Long) =
        layout(context, R.layout.widget_calories_small, snapshot, nowMillis, barDp = 64f)

    internal fun medium(context: Context, snapshot: WidgetSnapshot?, nowMillis: Long) =
        layout(context, R.layout.widget_calories_medium, snapshot, nowMillis, barDp = 200f).apply {
            setOnClickPendingIntent(R.id.widget_snap_it, open(context, QuickAction.SnapIt, 22))
            setOnClickPendingIntent(R.id.widget_coach, open(context, QuickAction.OpenCoach, 23))
            setViewVisibility(R.id.widget_actions, if (snapshot?.hasDiary == true) View.VISIBLE else View.GONE)
        }

    private fun layout(context: Context, id: Int, stored: WidgetSnapshot?, nowMillis: Long, barDp: Float) =
        RemoteViews(context.packageName, id).apply {
            setOnClickPendingIntent(android.R.id.background, open(context, QuickAction.Today, 21))
            val snapshot = stored?.takeIf { it.hasDiary }?.let { if (nowMillis >= it.rolloverAt) it.afterRollover() else it }
            val shown = { visible: Boolean -> if (visible) View.VISIBLE else View.GONE }
            setViewVisibility(R.id.widget_setup, shown(snapshot == null))
            setViewVisibility(R.id.widget_figure, shown(snapshot != null))
            setViewVisibility(R.id.widget_bar, shown(snapshot?.target != null))
            setViewVisibility(R.id.widget_set_target, shown(snapshot != null && snapshot.target == null))
            if (snapshot == null) return@apply
            val target = snapshot.target
            setTextViewText(R.id.widget_eaten, kcal(snapshot.eaten))
            setTextViewText(R.id.widget_goal, target?.let { "of ${kcal(it)} kcal" } ?: "kcal recorded")
            setContentDescription(R.id.widget_figure,
                target?.let { "${kcal(snapshot.eaten)} of ${kcal(it)} calories eaten" } ?: "${kcal(snapshot.eaten)} calories eaten")
            // As iOS, anything eaten shows at least a 6 dp sliver.
            val fraction = maxOf(snapshot.ringFraction, if (snapshot.eaten > 0) 6 / barDp.toDouble() else 0.0)
            setProgressBar(R.id.widget_bar, 1000, (fraction * 1000).roundToLong().toInt(), false)
        }

    private fun open(context: Context, action: QuickAction, request: Int) =
        PendingIntent.getActivity(context, request, quickIntent(context, action), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)

    // Swift `Int(value.rounded()).formatted()`: grouped whole kilocalories.
    private fun kcal(value: Double) = NumberFormat.getIntegerInstance().format(value.roundToLong())
}

class CaloriesWidgetProvider : AppWidgetProvider() {
    // Reads one small preference, never the diary, so the system's update broadcast stays quick.
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) = CaloriesWidget.update(context, ids)
}
