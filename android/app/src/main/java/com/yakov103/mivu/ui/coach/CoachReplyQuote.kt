package com.yakov103.mivu.ui.coach

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.yakov103.mivu.R
import com.yakov103.mivu.diary.CoachReply
import com.yakov103.mivu.ui.today.isLargeText
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale
import java.util.UUID

// Port of ios/Mivu/Coach/CoachReplyQuote.swift and the Diary "Ask Pip" handoffs (HistoryView.askPipAction,
// MealDetailView.askPip).

/** What a Diary or meal screen asks Pip about; MivuApp turns it into the composer's quote and draft. */
sealed interface AskPip {
    /** A Diary date; [dayID] is null when the date has no recorded day, so only a draft names it. */
    data class Day(val dayID: UUID?, val localDate: String) : AskPip
    data class Meal(val mealID: UUID, val title: String) : AskPip
    data class Food(val mealID: UUID, val itemID: UUID, val name: String, val dayLocalDate: String?) : AskPip

    /** The quote (null for a date without a day) and the unsent message the composer starts with. */
    fun handoff(locale: Locale = Locale.getDefault()): Pair<CoachReply?, String?> {
        fun format(date: String, pattern: String) = runCatching { LocalDate.parse(date).format(DateTimeFormatter.ofPattern(pattern, locale)) }.getOrDefault(date)
        return when (this) {
            is Day -> if (dayID == null) null to "For ${format(localDate, "EEEE, d MMM")}: "
                else CoachReply(CoachReply.Target.Day(dayID), format(localDate, "EEEE, d MMM").take(280)) to null
            is Meal -> CoachReply(CoachReply.Target.Meal(mealID), title.ifBlank { "Meal" }.take(280)) to null
            is Food -> CoachReply(CoachReply.Target.Item(mealID, itemID), name.take(280)) to
                "About the $name${dayLocalDate?.let { " from ${format(it, "EEE d MMM")}" }.orEmpty()}: "
        }
    }
}

/** Who wrote the quoted content, as the person reads it. */
val CoachReply.author: String get() = when (val t = target) {
    is CoachReply.Target.Message -> if (t.fromPip) "Pip" else "You"
    is CoachReply.Target.Meal, is CoachReply.Target.Item, is CoachReply.Target.Day -> "Diary"
    is CoachReply.Target.Weight, is CoachReply.Target.Workout -> "Progress"
}

val CoachReply.composerTitle: String get() = when (val t = target) {
    is CoachReply.Target.Message -> if (t.fromPip) "Replying to Pip" else "Replying to you"
    is CoachReply.Target.Meal, is CoachReply.Target.Item, is CoachReply.Target.Day -> "From Diary"
    is CoachReply.Target.Weight, is CoachReply.Target.Workout -> "From Progress"
}

/** The quote at the top of the composer field: an accent rule, title and one-line excerpt, with a 48 dp Cancel reply. */
@Composable
fun CoachReplyBar(reply: CoachReply, onCancel: () -> Unit, modifier: Modifier = Modifier) {
    val accent = MaterialTheme.colorScheme.primary
    Row(
        modifier.padding(start = 6.dp, end = 2.dp, top = 6.dp).background(accent.copy(alpha = 0.07f), RoundedCornerShape(18.dp))
            .padding(start = 10.dp).height(IntrinsicSize.Min).testTag("coachReplyBar"),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.padding(vertical = 8.dp).width(3.dp).fillMaxHeight().background(accent, CircleShape))
        Column(
            Modifier.weight(1f).padding(start = 8.dp, top = 6.dp, bottom = 6.dp).semantics(mergeDescendants = true) {
                contentDescription = "Reply to ${if (reply.author == "You") "your message" else reply.author}: ${reply.excerpt}"
            },
            verticalArrangement = Arrangement.spacedBy(1.dp),
        ) {
            Text(reply.composerTitle, style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold, color = accent)
            // One line, two at large text sizes.
            Text(reply.excerpt, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = if (isLargeText()) 2 else 1, overflow = TextOverflow.Ellipsis)
        }
        IconButton(onCancel, Modifier.size(48.dp)) {
            Icon(painterResource(R.drawable.ic_close), contentDescription = "Cancel reply", Modifier.size(20.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}
