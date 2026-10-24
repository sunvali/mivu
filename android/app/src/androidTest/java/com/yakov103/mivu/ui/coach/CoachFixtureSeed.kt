package com.yakov103.mivu.ui.coach

import androidx.test.platform.app.InstrumentationRegistry
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
import org.junit.Assume.assumeTrue
import org.junit.Test

/** Seeds synthetic Coach turns for screenshots; each test is skipped unless run with its `-e <name> true` argument. */
class CoachFixtureSeed {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private val now = Instant.now().truncatedTo(ChronoUnit.SECONDS)

    private fun only(argument: String) {
        assumeTrue(InstrumentationRegistry.getArguments().getString(argument) == "true")
        TodayFixture.wipe(context)
    }

    private fun turn(db: DiaryDatabase, text: String, at: Instant = now): CoachTurn {
        val h = db.head()
        return db.captureCoachSubmission(CoachSubmissionPayload(UUID.randomUUID(), text, emptyList(),
            CoachCaptureContext(at, h.profile.timeZoneID, h.activeDayID, h.previousDayConfirmedAt, h.activeConversationSegmentID)), h.revision)
    }

    /** An empty Coach on a started day: `-e seedCoachEmpty true`. */
    @Test fun seedCoachEmpty() {
        only("seedCoachEmpty")
        val id = TodayFixture.diary(context)
        DiaryRepository(context).database(id).apply { startDay(now, head().revision); close() }
    }

    /** Today's meals plus a logged receipt, a question with chips and one pending message: `-e seedCoachTimeline true`. */
    @Test fun seedCoachTimeline() {
        only("seedCoachTimeline")
        val id = TodayFixture.seed(context)
        val db = DiaryRepository(context).database(id)
        val logged = turn(db, "Greek yogurt with granola and a banana", now.minus(20, ChronoUnit.MINUTES))
        val food = FoodItem(UUID.randomUUID(), "Greek yogurt with granola", 1.0, "bowl", NutritionValues(410.0, 52.0, 21.0, 12.0),
            NutritionProvenance.estimate, "Synthetic", false, emptyMap())
        val receipt = db.applyCoachWrites(logged.id, listOf(CoachWrite.Food(LocalDate.now(ZoneId.systemDefault()).toString(), listOf(food), null)),
            at = now.minus(20, ChronoUnit.MINUTES)).single()
        db.transaction(null) { it.finishCoachTurn(logged.id, "Saved — about **410** kcal.") }
        val asked = turn(db, "Make that a smaller bowl", now.minus(10, ChronoUnit.MINUTES))
        db.transaction(null) {
            it.finishCoachTurn(asked.id, "Which meal should I change?",
                CoachQuestion(CoachClarification.meal, listOf(CoachReply.Target.Meal(receipt.mealID!!)), "Make that a smaller bowl"))
        }
        turn(db, "A flat white with oat milk")
        db.close()
    }

    /** Thirty finished exchanges to browse, for Jump to latest: `-e seedCoachHistory true`. */
    @Test fun seedCoachHistory() {
        only("seedCoachHistory")
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
}
