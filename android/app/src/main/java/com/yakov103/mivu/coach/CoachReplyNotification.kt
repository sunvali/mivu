package com.yakov103.mivu.coach

import android.Manifest
import android.app.PendingIntent
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationChannelCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.yakov103.mivu.R
import com.yakov103.mivu.diary.CoachTurn
import com.yakov103.mivu.diary.CoachTurnState
import com.yakov103.mivu.quick.QuickAction
import com.yakov103.mivu.quick.quickIntent
import com.yakov103.mivu.ui.coach.coachReplyText
import java.text.BreakIterator
import java.util.UUID

/**
 * iOS `CoachReplyNotification`: the Coach's answer to a shared message, posted once the background run finishes. Like iOS, it
 * is not shown while Mivu is on screen, where the Coach tab already shows the reply.
 */
object CoachReplyNotification {
    const val TURN = "coachTurnID"
    private const val CHANNEL = "coach"
    private const val SAVED = "Your message is saved. Open Mivu for the Coach's reply."

    /** Null while the turn is still running, and for turns that saved a meal: the meal notification covers those. */
    fun text(turn: CoachTurn): Pair<String, String>? {
        if (turn.pendingMealID != null) return null
        return when (turn.state) {
            CoachTurnState.captured, CoachTurnState.analyzing -> null
            CoachTurnState.completed -> coachReplyText(turn.assistantText ?: "").text.trim().takeIf { it.isNotEmpty() }?.let { "Coach" to cut(it) }
            CoachTurnState.needsClarification -> "Coach" to "The Coach needs a quick answer."
            CoachTurnState.needsRetry, CoachTurnState.waitingForNetwork, CoachTurnState.waitingForConnection -> "Coach" to SAVED
        }
    }

    /** iOS `prefix(179) + "…"` beyond 180 characters, counted as user-perceived characters (a flag or ZWJ family is one). */
    private fun cut(reply: String): String {
        val breaks = BreakIterator.getCharacterInstance().apply { setText(reply) }
        val end = breaks.next(179)
        return if (end == BreakIterator.DONE || breaks.next(2) == BreakIterator.DONE) reply else reply.substring(0, end) + "…"
    }

    fun post(context: Context, turn: CoachTurn) {
        text(turn)?.let { add(context, turn.id, it.first, it.second) }
    }

    /** Tagged like the reply, so a reply that still arrives replaces this one. */
    fun postSaved(context: Context, turnID: UUID) = add(context, turnID, "Coach", SAVED)

    private fun add(context: Context, turnID: UUID, title: String, body: String) {
        if (Build.VERSION.SDK_INT >= 33 &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return
        val manager = NotificationManagerCompat.from(context)
        manager.createNotificationChannel(
            NotificationChannelCompat.Builder(CHANNEL, NotificationManagerCompat.IMPORTANCE_DEFAULT).setName("Coach replies").build())
        // Opens Coach at the latest exchange, as iOS sets openCoach; the turn ID rides along as iOS userInfo does.
        val open = PendingIntent.getActivity(context, 0, quickIntent(context, QuickAction.OpenCoach).putExtra(TURN, turnID.toString()),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val notification = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_pip)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setContentIntent(open)
            .setAutoCancel(true)
            .build()
        manager.notify("coach-reply-$turnID", 0, notification)
    }
}
