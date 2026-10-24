package com.yakov103.mivu.ui.coach

import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle

// iOS CoachReplyLines.attributed: inline Markdown with links dropped to plain text. Only the inline styles Coach writes
// are read; an underscore inside a word (snake_case) stays text, as in CommonMark.
private val inline = Regex("""\*\*(.+?)\*\*|\*(.+?)\*|(?<!\w)_(.+?)_(?!\w)|\[([^\]]+)]\([^)]*\)""")

fun coachReplyText(markdown: String): AnnotatedString = buildAnnotatedString {
    var at = 0
    for (match in inline.findAll(markdown)) {
        append(markdown, at, match.range.first)
        val (bold, star, underscore, link) = match.destructured
        when {
            bold.isNotEmpty() -> withStyle(SpanStyle(fontWeight = FontWeight.Bold)) { append(bold) }
            star.isNotEmpty() -> withStyle(SpanStyle(fontStyle = FontStyle.Italic)) { append(star) }
            underscore.isNotEmpty() -> withStyle(SpanStyle(fontStyle = FontStyle.Italic)) { append(underscore) }
            else -> append(link)
        }
        at = match.range.last + 1
    }
    append(markdown, at, markdown.length)
}
