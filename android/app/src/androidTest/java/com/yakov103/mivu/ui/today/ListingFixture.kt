package com.yakov103.mivu.ui.today

import android.content.Context
import androidx.activity.ComponentActivity
import androidx.activity.enableEdgeToEdge
import androidx.activity.compose.setContent
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import com.yakov103.mivu.coach.CoachWrite
import com.yakov103.mivu.diary.CoachCaptureContext
import com.yakov103.mivu.diary.CoachSubmissionPayload
import com.yakov103.mivu.diary.DayCompleteness
import com.yakov103.mivu.diary.DiaryMeal
import com.yakov103.mivu.diary.DiaryRepository
import com.yakov103.mivu.diary.FoodItem
import com.yakov103.mivu.diary.GoalRecord
import com.yakov103.mivu.diary.MealSubmission
import com.yakov103.mivu.diary.MealTimePrecision
import com.yakov103.mivu.diary.NutritionProvenance
import com.yakov103.mivu.diary.NutritionValues
import com.yakov103.mivu.diary.SubmissionState
import com.yakov103.mivu.diary.TrackingDay
import com.yakov103.mivu.diary.WeightEntry
import com.yakov103.mivu.diary.applyCoachWrites
import com.yakov103.mivu.diary.captureCoachSubmission
import com.yakov103.mivu.diary.finishCoachTurn
import com.yakov103.mivu.diary.startDay
import com.yakov103.mivu.ui.CoachHooks
import com.yakov103.mivu.ui.MivuApp
import com.yakov103.mivu.ui.theme.MivuTheme
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import java.util.UUID
import kotlinx.coroutines.flow.MutableStateFlow
import org.junit.Assume.assumeTrue
import org.junit.Test

/** The Play listing's synthetic diary: two weeks of meals and weights under a goal, and today's Coach receipt. */
object ListingFixture {
    private class Food(val name: String, val kcal: Double, val p: Double, val c: Double, val f: Double)

    private val breakfasts = listOf(Food("Overnight oats with berries", 380.0, 14.0, 58.0, 9.0),
        Food("Greek yogurt with granola", 410.0, 21.0, 52.0, 12.0), Food("Avocado toast with an egg", 450.0, 17.0, 38.0, 26.0),
        Food("Two eggs on sourdough toast", 420.0, 22.0, 34.0, 20.0))
    private val lunches = listOf(Food("Chicken rice bowl", 640.0, 42.0, 71.0, 16.0), Food("Lentil soup with bread", 520.0, 24.0, 76.0, 11.0),
        Food("Turkey wrap with salad", 560.0, 35.0, 52.0, 21.0), Food("Salmon poke bowl", 610.0, 34.0, 68.0, 19.0))
    private val dinners = listOf(Food("Grilled salmon with potatoes", 680.0, 40.0, 52.0, 30.0),
        Food("Pasta with tomato and tuna", 690.0, 36.0, 88.0, 18.0), Food("Tofu stir-fry with noodles", 620.0, 28.0, 78.0, 20.0),
        Food("Chicken curry with rice", 720.0, 38.0, 80.0, 24.0), Food("Beef chili with rice", 700.0, 40.0, 74.0, 22.0))
    private val snacks = listOf(Food("Apple with peanut butter", 260.0, 7.0, 28.0, 16.0), Food("Protein bar", 210.0, 20.0, 22.0, 7.0),
        Food("Hummus with carrots", 180.0, 6.0, 18.0, 9.0))
    private val weights = listOf(74.8, 74.9, 74.6, 74.5, 74.6, 74.3, 74.2, 74.2, 74.0, 73.9, 74.0, 73.7, 73.6, 73.5) // oldest first

    private fun item(food: Food) = FoodItem(UUID.randomUUID(), food.name, 1.0, "serving", NutritionValues(food.kcal, food.c, food.p, food.f),
        NutritionProvenance.user, "Entered manually", false, emptyMap())

    fun seed(context: Context) {
        val id = TodayFixture.diary(context)
        val db = DiaryRepository(context).database(id)
        val zone = ZoneId.systemDefault()
        val active = db.startDay(Instant.now().truncatedTo(ChronoUnit.SECONDS), db.head().revision)
        val today = LocalDate.parse(active.localDate)
        fun at(date: LocalDate, h: Int, m: Int) = date.atTime(h, m).atZone(zone).toInstant()
        db.transaction(db.head().revision) { tx ->
            fun meal(day: TrackingDay, h: Int, m: Int, food: Food) {
                val time = at(LocalDate.parse(day.localDate), h, m)
                tx.putMeal(DiaryMeal(UUID.randomUUID(), day.id, time, time, 1, timePrecision = MealTimePrecision.exact, items = listOf(item(food)),
                    photos = emptyList(), submissions = listOf(MealSubmission(UUID.randomUUID(), 0, food.name, emptyList(), false, SubmissionState.saved))))
            }
            tx.putGoal(GoalRecord(UUID.randomUUID(), "2026-01-01", zone.id, 1, NutritionValues(2000.0, 220.0, 120.0, 70.0), null, false))
            for (back in 13L downTo 1L) {
                val date = today.minusDays(back)
                val day = TrackingDay(UUID.randomUUID(), date.toString(), zone.id, at(date, 7, 0), DayCompleteness.complete).also(tx::putDay)
                val i = back.toInt()
                meal(day, 8, 0, breakfasts[i % breakfasts.size])
                meal(day, 12, 45, lunches[(i * 3) % lunches.size])
                meal(day, 19, 30, dinners[i % dinners.size])
                if (i % 3 != 0) meal(day, 16, 15, snacks[i % snacks.size])
                tx.putWeight(WeightEntry(UUID.randomUUID(), day.id, at(date, 7, 10), weights[13 - i], "kg"))
            }
            tx.putWeight(WeightEntry(UUID.randomUUID(), active.id, at(today, 7, 10), weights.last(), "kg"))
            meal(active, 12, 50, lunches[0])
            meal(active, 16, 10, snacks[0])
        }
        fun chat(text: String, at: Instant, reply: String, foods: List<Food> = emptyList()) {
            val h = db.head()
            val turn = db.captureCoachSubmission(CoachSubmissionPayload(UUID.randomUUID(), text, emptyList(),
                CoachCaptureContext(at, h.profile.timeZoneID, h.activeDayID, h.previousDayConfirmedAt, h.activeConversationSegmentID)), h.revision)
            if (foods.isNotEmpty()) db.applyCoachWrites(turn.id, listOf(CoachWrite.Food(today.toString(), foods.map(::item), at)), at = at)
            db.transaction(null) { it.finishCoachTurn(turn.id, reply) }
        }
        chat("Two eggs on toast and a flat white", at(today, 8, 10), "Saved — about **530** kcal. A strong start.",
            listOf(breakfasts[3], Food("Flat white", 110.0, 6.0, 9.0, 6.0)))
        db.close()
    }
}

/**
 * Seeds the listing diary (`-e seedListing true`), then, with `-e holdCoachSeconds N`, shows the app as if a plan were connected for N
 * seconds, so Coach can be opened and captured. No sign-in happens; the drain does nothing.
 */
@FixtureSeed
class ListingFixtureSeed {
    @Test fun seedListing() {
        val args = InstrumentationRegistry.getArguments()
        assumeTrue(args.getString("seedListing") == "true")
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        TodayFixture.wipe(context)
        ListingFixture.seed(context)
        val hold = args.getString("holdCoachSeconds")?.toLong() ?: return
        ActivityScenario.launch(ComponentActivity::class.java).use { scenario ->
            scenario.onActivity {
                it.enableEdgeToEdge()
                it.setContent { MivuTheme { MivuApp(DiaryRepository(context), coach = CoachHooks(connected = MutableStateFlow(true))) } }
            }
            Thread.sleep(hold * 1000)
        }
    }
}
