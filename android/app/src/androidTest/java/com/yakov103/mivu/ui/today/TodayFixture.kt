package com.yakov103.mivu.ui.today

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import androidx.test.platform.app.InstrumentationRegistry
import com.yakov103.mivu.analysis.MealAnalysisWorker
import com.yakov103.mivu.analysis.SampleAnalyzer
import com.yakov103.mivu.diary.DiaryDatabase
import com.yakov103.mivu.diary.DiaryProfile
import com.yakov103.mivu.diary.DiaryRepository
import com.yakov103.mivu.diary.FoodItem
import com.yakov103.mivu.diary.GoalRecord
import com.yakov103.mivu.diary.ManualNutritionDayChoice
import com.yakov103.mivu.diary.ManualNutritionOperation
import com.yakov103.mivu.diary.ManualNutritionPayload
import com.yakov103.mivu.diary.MealPhoto
import com.yakov103.mivu.diary.MealTimePrecision
import com.yakov103.mivu.diary.NutritionProvenance
import com.yakov103.mivu.diary.NutritionValues
import com.yakov103.mivu.diary.PhotoRole
import com.yakov103.mivu.diary.captureProjection
import com.yakov103.mivu.diary.prepareManualNutritionTarget
import com.yakov103.mivu.diary.saveManualNutrition
import com.yakov103.mivu.diary.startDay
import java.io.ByteArrayOutputStream
import java.io.File
import java.time.Instant
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import java.util.UUID
import kotlinx.coroutines.runBlocking
import org.junit.Assume.assumeTrue
import org.junit.Test

/** Synthetic Today fixtures: a selected diary with a started day, manual meals, a sample photo meal and a goal. */
object TodayFixture {
    fun wipe(context: Context) {
        File(context.filesDir, "profiles").deleteRecursively()
        DiaryRepository.preferences(context).edit().clear().commit()
    }

    /** An empty selected diary; returns its profile ID. */
    fun diary(context: Context): UUID {
        val profile = DiaryProfile(UUID.randomUUID(), "My diary", "en", ZoneId.systemDefault().id, "")
        DiaryDatabase.create(context, profile).close()
        DiaryRepository.preferences(context).edit().putString("selectedProfile", profile.id.toString()).commit()
        return profile.id
    }

    /** Seeds today's meals through the real store; returns the profile ID. Leaves no database open. */
    fun seed(context: Context, unknownProtein: Boolean = false, photo: Boolean = true): UUID {
        val id = diary(context)
        val repository = DiaryRepository(context)
        val db = repository.database(id)
        val now = Instant.now().truncatedTo(ChronoUnit.SECONDS)
        db.startDay(now, db.head().revision)
        manual(db, id, now.minus(5, ChronoUnit.HOURS), item("Overnight oats", 380.0, if (unknownProtein) null else 14.0, 58.0, 9.0))
        manual(db, id, now.minus(2, ChronoUnit.HOURS), item("Chicken rice bowl", 640.0, 42.0, 71.0, 16.0))
        db.transaction(db.head().revision) {
            it.putGoal(GoalRecord(UUID.randomUUID(), "2026-01-01", ZoneId.systemDefault().id, 1,
                NutritionValues(2000.0, 220.0, 120.0, 70.0), null, false))
        }
        if (photo) {
            db.captureProjection("Afternoon snack", listOf(MealPhoto(UUID.randomUUID(), plateJpeg(), now, PhotoRole.unspecified)),
                reviewFirst = false, dayID = db.head().activeDayID!!, at = now.minus(30, ChronoUnit.MINUTES), expectedRevision = db.head().revision)
            runBlocking { MealAnalysisWorker(repository, SampleAnalyzer::analyze).drain(id) }
        }
        db.close()
        return id
    }

    private fun item(name: String, kcal: Double, protein: Double?, carbs: Double, fat: Double) = FoodItem(UUID.randomUUID(), name, 1.0,
        "serving", NutritionValues(kcal, carbs, protein, fat), NutritionProvenance.user, "Entered manually", false, emptyMap())

    private fun manual(db: DiaryDatabase, profileID: UUID, at: Instant, item: FoodItem) {
        val payload = ManualNutritionPayload(profileID, UUID.randomUUID(), UUID.randomUUID(), ManualNutritionOperation.create,
            db.prepareManualNutritionTarget(ManualNutritionDayChoice.Current, at), at, at, MealTimePrecision.exact, null, listOf(item))
        db.saveManualNutrition(payload, db.head().revision)
    }

    /** A drawn plate: synthetic photo bytes, no real food image. */
    internal fun plateJpeg(): ByteArray {
        val bitmap = Bitmap.createBitmap(640, 640, Bitmap.Config.ARGB_8888)
        Canvas(bitmap).apply {
            drawColor(Color.rgb(222, 205, 178))
            drawCircle(320f, 320f, 260f, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE })
            drawCircle(250f, 290f, 90f, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.rgb(196, 48, 43) })
            drawCircle(390f, 360f, 80f, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.rgb(120, 170, 60) })
        }
        return ByteArrayOutputStream().also { bitmap.compress(Bitmap.CompressFormat.JPEG, 85, it) }.toByteArray()
    }
}

/** Seeds the emulator app for screenshots; skipped unless run with `-e seedTodayFixture true`. */
class TodayFixtureSeed {
    @Test fun seedTodayFixture() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("seedTodayFixture") == "true")
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        TodayFixture.wipe(context)
        TodayFixture.seed(context)
    }

    /** The Diary screenshots' synthetic week; run with `-e seedDiaryFixture true`. */
    @Test fun seedDiaryFixture() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("seedDiaryFixture") == "true")
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        TodayFixture.wipe(context)
        com.yakov103.mivu.ui.diary.DiaryFixture.seed(context)
    }

    /** The meal detail screenshots' meal: three foods and a photo; run with `-e seedMealFixture true`. */
    @Test fun seedMealFixture() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("seedMealFixture") == "true")
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        TodayFixture.wipe(context)
        val id = TodayFixture.diary(context)
        val db = DiaryRepository(context).database(id)
        val at = Instant.now().truncatedTo(ChronoUnit.SECONDS).minus(1, ChronoUnit.HOURS)
        db.startDay(at, db.head().revision)
        fun food(name: String, quantity: Double, unit: String, kcal: Double, p: Double, c: Double, f: Double, source: NutritionProvenance,
                 uncertain: Boolean = false) = FoodItem(UUID.randomUUID(), name, quantity, unit, NutritionValues(kcal, c, p, f), source, "",
            uncertain, emptyMap())
        val photo = MealPhoto(UUID.randomUUID(), TodayFixture.plateJpeg(), at, PhotoRole.unspecified)
        val items = listOf(food("Greek yogurt", 200.0, "g", 190.0, 17.0, 8.0, 5.0, NutritionProvenance.estimate),
            food("Blueberries", 80.0, "g", 46.0, 0.6, 11.5, 0.3, NutritionProvenance.user),
            food("Honey", 1.0, "tbsp", 74.0, 0.4, 13.0, 3.8, NutritionProvenance.user, uncertain = true))
        db.transaction(db.head().revision) {
            it.putMeal(com.yakov103.mivu.diary.DiaryMeal(UUID.randomUUID(), db.head().activeDayID!!, at, at, 1,
                timePrecision = MealTimePrecision.exact, items = items, photos = listOf(photo),
                submissions = listOf(com.yakov103.mivu.diary.MealSubmission(UUID.randomUUID(), 0, "", listOf(photo.id), false,
                    com.yakov103.mivu.diary.SubmissionState.saved))))
        }
        db.close()
    }
}
