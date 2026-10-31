package com.yakov103.mivu.diary

import android.content.Context
import android.os.SystemClock
import android.util.Log
import androidx.test.core.app.ApplicationProvider
import com.yakov103.mivu.coach.CoachError
import java.io.File
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import java.util.UUID
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test

/** Synthetic diaries only: the Progress screen's bounded reads and its editor writes. */
class ProgressQueriesTest {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val profile = DiaryProfile(UUID.randomUUID(), "Synthetic", "en", "UTC", "")
    private lateinit var db: DiaryDatabase
    private val end = "2027-01-15"
    private val draft = WorkoutDraft(WorkoutKind.cardio, 30, emptyList())

    @Before fun open() {
        File(context.filesDir, "profiles").deleteRecursively()
        db = DiaryDatabase.create(context, profile)
    }

    @After fun close() {
        db.close()
        File(context.filesDir, "profiles").deleteRecursively()
    }

    private inline fun <reified E : Throwable> throws(block: () -> Unit) {
        try { block(); fail("expected ${E::class.simpleName}") } catch (e: Throwable) { if (e !is E) throw e }
    }

    private fun noon(date: String) = LocalDate.parse(date).atTime(12, 0).toInstant(ZoneOffset.UTC)
    private fun back(days: Int) = LocalDate.parse(end).minusDays(days.toLong()).toString()
    private fun food(name: String, kcal: Double?) = FoodItem(UUID.randomUUID(), name, 1.0, "serving",
        NutritionValues(kcal, 1.0, 1.0, 1.0), NutritionProvenance.user, "", false, emptyMap())

    /** One day per date with [mealsPerDay] meals of [items] each, plus [weights]. */
    private fun seed(dates: List<String>, revision: (String) -> Int = { 1 }, weights: List<WeightEntry> = emptyList(), mealsPerDay: Int = 1,
                     items: (String) -> List<FoodItem> = { listOf(food("Synthetic oats", 300.0)) }) {
        val days = dates.map { TrackingDay(UUID.randomUUID(), it, "UTC", noon(it), DayCompleteness.unknown) }
        val meals = days.flatMap { day -> List(mealsPerDay) { DiaryMeal(UUID.randomUUID(), day.id, noon(day.localDate), noon(day.localDate),
            revision(day.localDate), items = items(day.localDate), photos = emptyList(), submissions = emptyList()) } }
        db.replaceAll(db.snapshot().copy(revision = db.head().revision.toInt() + 1, days = days, meals = meals, weights = weights))
    }

    @Test fun displayRangeAcceptsQuarterAndYearButCoachDoesNot() {
        throws<CoachError.InvalidArguments> { db.progressRange(end, 91) }
        throws<CoachError.InvalidArguments> { db.progressRange(end, 365) }
        val quarter = db.progressRange(end, 91, includeDailyReports = true)
        assertEquals(91, quarter.dailyReports!!.size)
        assertEquals(back(90), quarter.startLocalDate)
        // The Coach shape carries no display fields.
        val coach = db.progressRange(end, 30)
        assertNull(coach.dailyReports)
        assertNull(coach.displayWeights)
        assertNull(coach.workoutTotal)
    }

    @Test fun yearLoadIsBounded() {
        val dates = (364 downTo 0).map(::back)
        // Several meals a day, so a scan of every meal per day would show in the time.
        seed(dates, mealsPerDay = 4, weights = dates.filterIndexed { i, _ -> i % 2 == 0 }.mapIndexed { i, d ->
            WeightEntry(UUID.randomUUID(), measuredAt = noon(d), value = 80.0 - i * 0.01, unit = "kg")
        })
        val started = SystemClock.elapsedRealtime()
        val year = db.progressRange(end, 365, includeDailyReports = true)
        val elapsed = SystemClock.elapsedRealtime() - started
        Log.i("ProgressQueriesTest", "365-day progress load took $elapsed ms")
        assertEquals(365, year.dailyReports!!.size)
        assertEquals(183, year.displayWeights!!.size)
        assertEquals(365, year.savedFoodDates!!.size)
        assertEquals(end, year.latestWeight!!.localDate)
        assertEquals(0, year.workoutTotal)
        assertTrue("365-day progress took $elapsed ms", elapsed < 2_000)
        // The child and date lookups have their iOS indexes.
        val indexes = android.database.sqlite.SQLiteDatabase.openDatabase(db.file.path, null, android.database.sqlite.SQLiteDatabase.OPEN_READONLY)
            .use { it.rawQuery("SELECT name FROM sqlite_master WHERE type = 'index'", null).use { c -> buildSet { while (c.moveToNext()) add(c.getString(0)) } } }
        assertTrue(indexes.toString(), indexes.containsAll(listOf("meal_parent_ordinal", "item_parent_ordinal", "weight_parent_ordinal",
            "workout_parent_ordinal", "day_ordinal", "goal_date")))
    }

    @Test fun topFoodsGroupsByNormalisedNameAndSkipsUnknownAndPending() {
        seed(listOf(back(5), back(4), back(3), back(2), back(1)), revision = { if (it == back(1)) 0 else 1 }) { date ->
            when (date) {
                back(5) -> listOf(food(" greek Yogurt ", 150.0))
                back(4) -> listOf(food("Pizza", 721.0))
                back(3) -> listOf(food("Greek yogurt", 150.0))
                back(2) -> listOf(food("Mystery stew", null), food("Toast", 90.0))
                else -> listOf(food("Pending pie", 500.0))
            }
        }
        assertEquals(listOf(TopFood("Pizza", 721.0, 1), TopFood("Greek yogurt", 300.0, 2), TopFood("Toast", 90.0, 1)),
            db.topFoods(back(14), end, 10))
        assertEquals(listOf(TopFood("Pizza", 721.0, 1)), db.topFoods(back(14), end, 1))
        throws<CoachError.InvalidArguments> { db.topFoods("2027-13-01", end, 10) }
    }

    @Test fun historyBeforeLooksPastEmptyWeeks() {
        // Logged 40 days and 1 day back; the weeks between are empty.
        seed(listOf(back(40), back(1)))
        assertTrue(db.hasDays(before = "2027-01-01"))
        assertFalse(db.hasDays(before = back(40)))
        throws<CoachError.InvalidArguments> { db.hasDays(before = "not a date") }
    }

    @Test fun weightHistoryPagesThirtyAtATime() {
        val start = Instant.parse("2026-11-01T08:00:00Z")
        val weights = (0 until 65).map { WeightEntry(UUID.randomUUID(), measuredAt = start.plusSeconds(it * 3_600L), value = 70.0, unit = "kg") }
        seed(emptyList(), weights = weights)
        val newest = weights.reversed().map { it.id }
        val first = db.weightHistory()
        assertEquals(newest.take(30), first.values.map { it.id })
        assertTrue(first.hasMore)
        val second = db.weightHistory(before = first.cursor!!)
        assertEquals(newest.subList(30, 60), second.values.map { it.id })
        val third = db.weightHistory(before = second.cursor!!)
        assertEquals(newest.drop(60), third.values.map { it.id })
        assertFalse(third.hasMore)
        assertNull(third.cursor)
        throws<DiaryError.NotFound> { db.weightHistory(before = 10_000) }
    }

    @Test fun recordWeightStartsADayOnlyWhenAsked() {
        val at = Instant.parse("2026-10-24T09:30:00Z")
        val loose = db.recordWeight(70.0, at = at, startNewDay = false)
        assertNull(loose.dayID)
        assertNull(db.head().activeDayID)
        val started = db.recordWeight(71.0, at = at)
        assertNotNull(started.dayID)
        assertEquals(db.head().activeDayID, started.dayID)
        assertEquals(MealTimePrecision.exact, started.timePrecision)
        assertEquals(at.stored, started.measuredAt)
        val corrected = db.recordWeight(72.0, at = at.plusSeconds(60), startNewDay = false)
        assertEquals(started.id, corrected.id)
        assertEquals(2, corrected.revision)
        assertEquals(72.0, db.weightHistory().values.first { it.id == started.id }.value, 0.0)
    }

    @Test fun staleGoalRevisionIsRejected() {
        val goal = GoalRecord(UUID.randomUUID(), "2026-10-01", "UTC", 0, NutritionValues(kcal = 2000.0), 70.0, false)
        assertEquals(1, db.setGoals(goal, null).revision)
        throws<DiaryError.StaleRevision> { db.setGoals(goal.copy(targets = NutritionValues(kcal = 1900.0)), null) }
        assertEquals(2, db.setGoals(goal.copy(targets = NutritionValues(kcal = 1900.0)), 1).revision)
        assertEquals(1900.0, db.goal("2026-10-20")!!.targets.kcal!!, 0.0)
        assertNull(db.goal("2026-10-20", exact = true))
        assertEquals(2, db.goal("2026-10-01", exact = true)!!.revision)
        assertEquals(listOf(goal.id), db.goalHistory().values.map { it.id })
    }

    @Test fun createWorkoutForADateReusesThatDay() {
        val first = db.createWorkout("2026-10-20", draft)
        val second = db.createWorkout("2026-10-20", draft.copy(durationMinutes = 45))
        assertEquals(first.dayID, second.dayID)
        assertEquals(MealTimePrecision.dateOnly, first.timePrecision)
        assertEquals(listOf(second.id, first.id).toSet(), db.workoutHistory().values.map { it.id }.toSet())
        throws<DiaryError.StaleRevision> { db.updateWorkout(first.copy(durationMinutes = 20), 2) }
        assertEquals(2, db.updateWorkout(first.copy(durationMinutes = 20), 1).revision)
        db.deleteWorkout(second.id, 1)
        assertEquals(listOf(first.id), db.workoutHistory().values.map { it.id })
    }
}
