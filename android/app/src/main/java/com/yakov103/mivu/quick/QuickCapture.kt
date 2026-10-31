package com.yakov103.mivu.quick

import android.content.Context
import android.content.Intent
import com.yakov103.mivu.MainActivity
import com.yakov103.mivu.MivuApplication
import com.yakov103.mivu.coach.CoachReplyNotification

/**
 * iOS `QuickLogRequest`: the one intent shape that launcher shortcuts, the Snap It tile and widgets open the app with.
 * It only chooses a screen; it never captures anything by itself.
 */
enum class QuickAction(val action: String) {
    SnapIt("com.yakov103.mivu.action.SNAP_IT"),
    OpenCoach("com.yakov103.mivu.action.OPEN_COACH"),
    Today("com.yakov103.mivu.action.TODAY"),
    /** A Coach reply notification: iOS only selects the Coach tab, without focusing the composer. */
    CoachReply("com.yakov103.mivu.action.COACH_REPLY");

    companion object {
        /** The action alone decides; extras and data are never read, as any app can start the exported activity. */
        fun from(intent: Intent?): QuickAction? = intent?.action?.let { action -> entries.firstOrNull { it.action == action } }
    }
}

fun quickIntent(context: Context, action: QuickAction): Intent = Intent(action.action).setClass(context, MainActivity::class.java)
    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)

/**
 * Publishes a quick action for the shell, which consumes it once a diary is ready; any other intent changes nothing. Open Coach
 * carrying a reply notification's turn only selects Coach; the extra is never trusted beyond that.
 */
fun MivuApplication.receive(intent: Intent?) {
    val action = QuickAction.from(intent) ?: return
    val reply = action == QuickAction.OpenCoach && runCatching { intent!!.hasExtra(CoachReplyNotification.TURN) }.getOrDefault(false)
    quickRequest.value = if (reply) QuickAction.CoachReply else action
}
