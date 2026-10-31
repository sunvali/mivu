package com.yakov103.mivu.ui.coach

import android.content.Context
import com.yakov103.mivu.coach.CoachWrite
import com.yakov103.mivu.diary.CoachCaptureContext
import com.yakov103.mivu.diary.CoachClarification
import com.yakov103.mivu.diary.CoachQuestion
import com.yakov103.mivu.diary.CoachReply
import com.yakov103.mivu.diary.CoachSubmissionPayload
import com.yakov103.mivu.diary.CoachTurn
import com.yakov103.mivu.diary.CoachTurnState
import com.yakov103.mivu.diary.DiaryDatabase
import com.yakov103.mivu.diary.DiaryRepository
import com.yakov103.mivu.diary.FoodItem
import com.yakov103.mivu.diary.NutritionProvenance
import com.yakov103.mivu.diary.NutritionValues
import com.yakov103.mivu.diary.applyCoachWrites
import com.yakov103.mivu.diary.captureCoachSubmission
import com.yakov103.mivu.diary.finishCoachTurn
import com.yakov103.mivu.diary.startDay
import com.yakov103.mivu.ui.today.TodayFixture
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import java.util.UUID

/** Synthetic Coach turns for screenshots, seeded through the real store; run from `TodayFixtureSeed`, which the suite excludes. */
object CoachFixture {
    private fun turn(db: DiaryDatabase, text: String, at: Instant): CoachTurn {
        val h = db.head()
        return db.captureCoachSubmission(CoachSubmissionPayload(UUID.randomUUID(), text, emptyList(),
            CoachCaptureContext(at, h.profile.timeZoneID, h.activeDayID, h.previousDayConfirmedAt, h.activeConversationSegmentID)), h.revision)
    }

    /** An empty Coach on a started day. */
    fun empty(context: Context) {
        val now = Instant.now().truncatedTo(ChronoUnit.SECONDS)
        val id = TodayFixture.diary(context)
        DiaryRepository(context).database(id).apply { startDay(now, head().revision); close() }
    }

    /** Today's meals plus a logged receipt, one waiting message, then the latest question with chips. */
    fun timeline(context: Context) {
        val now = Instant.now().truncatedTo(ChronoUnit.SECONDS)
        val id = TodayFixture.seed(context)
        val db = DiaryRepository(context).database(id)
        val logged = turn(db, "Greek yogurt with granola and a banana", now.minus(20, ChronoUnit.MINUTES))
        val food = FoodItem(UUID.randomUUID(), "Greek yogurt with granola", 1.0, "bowl", NutritionValues(410.0, 52.0, 21.0, 12.0),
            NutritionProvenance.estimate, "Synthetic", false, emptyMap())
        val receipt = db.applyCoachWrites(logged.id, listOf(CoachWrite.Food(LocalDate.now(ZoneId.systemDefault()).toString(), listOf(food), null)),
            at = now.minus(20, ChronoUnit.MINUTES)).single()
        db.transaction(null) { it.finishCoachTurn(logged.id, "Saved — about **410** kcal.") }
        turn(db, "A flat white with oat milk", now.minus(15, ChronoUnit.MINUTES)) // waits for a connection
        val asked = turn(db, "Make that a smaller bowl", now.minus(10, ChronoUnit.MINUTES))
        db.transaction(null) {
            it.finishCoachTurn(asked.id, "Which meal should I change?",
                CoachQuestion(CoachClarification.meal, listOf(CoachReply.Target.Meal(receipt.mealID!!)), "Make that a smaller bowl"))
        }
        db.close()
    }

    /** Thirty finished exchanges to browse, for Jump to latest. */
    fun history(context: Context) {
        val now = Instant.now().truncatedTo(ChronoUnit.SECONDS)
        val id = TodayFixture.diary(context)
        val db = DiaryRepository(context).database(id)
        db.startDay(now.minus(2, ChronoUnit.HOURS), db.head().revision)
        val day = db.head().activeDayID
        val turns = List(30) {
            CoachTurn(UUID.randomUUID(), now.minus(60L - it, ChronoUnit.MINUTES), "Synthetic question $it", emptyList(), CoachTurnState.completed,
                "Synthetic reply $it.", emptyList(), ZoneId.systemDefault().id, day, emptyList())
        }
        db.replaceAll(db.snapshot().copy(revision = db.head().revision.toInt() + 1, coachTurns = turns))
        db.close()
    }

    /** Five earlier conversations on separate days, then today's chat ending in a quoted reply to Pip. */
    fun conversations(context: Context) {
        val now = Instant.now().truncatedTo(ChronoUnit.SECONDS)
        val id = TodayFixture.diary(context)
        val db = DiaryRepository(context).database(id)
        db.startDay(now.minus(2, ChronoUnit.HOURS), db.head().revision)
        val past = listOf("Lentil soup with a slice of sourdough", "Two eggs on rye toast and a coffee", "Salmon, rice and broccoli",
            "Grilled chicken salad with feta", "Oatmeal with banana and a coffee with oat milk")
        val earlier = past.mapIndexed { i, text ->
            CoachTurn(UUID.randomUUID(), now.minus((past.size - i).toLong(), ChronoUnit.DAYS), text, emptyList(), CoachTurnState.completed,
                "Saved — about **${380 + 40 * i}** kcal.", emptyList(), ZoneId.systemDefault().id, null, emptyList(),
                captureSegmentID = UUID.randomUUID())
        }
        db.replaceAll(db.snapshot().copy(revision = db.head().revision.toInt() + 1, coachTurns = earlier))
        val asked = turn(db, "How much protein have I had today?", now.minus(30, ChronoUnit.MINUTES))
        db.transaction(null) { it.finishCoachTurn(asked.id, "About **42 g** so far.") }
        val h = db.head()
        val follow = db.captureCoachSubmission(CoachSubmissionPayload(UUID.randomUUID(), "What could I add at dinner?", emptyList(),
            CoachCaptureContext(now.minus(25, ChronoUnit.MINUTES), h.profile.timeZoneID, h.activeDayID, h.previousDayConfirmedAt,
                h.activeConversationSegmentID),
            reply = CoachReply(CoachReply.Target.Message(asked.id, fromPip = true), "About 42 g so far.")), h.revision)
        db.transaction(null) { it.finishCoachTurn(follow.id, "A palm-sized piece of chicken or tofu adds about **30 g**.") }
        db.close()
    }
}
