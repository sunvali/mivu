package com.yakov103.mivu.widget

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.res.Configuration
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.RemoteViews
import android.widget.TextView
import androidx.core.view.children
import androidx.test.core.app.ApplicationProvider
import com.yakov103.mivu.MivuApplication
import com.yakov103.mivu.R
import com.yakov103.mivu.diary.Bootstrap
import com.yakov103.mivu.diary.DiaryDatabase
import com.yakov103.mivu.diary.FoodItem
import com.yakov103.mivu.diary.GoalRecord
import com.yakov103.mivu.diary.ManualNutritionDayChoice
import com.yakov103.mivu.diary.ManualNutritionOperation
import com.yakov103.mivu.diary.ManualNutritionPayload
import com.yakov103.mivu.diary.MealTimePrecision
import com.yakov103.mivu.diary.NutritionProvenance
import com.yakov103.mivu.diary.NutritionValues
import com.yakov103.mivu.diary.prepareManualNutritionTarget
import com.yakov103.mivu.diary.saveManualNutrition
import com.yakov103.mivu.ui.today.TodayFixture
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.BeforeClass
import org.junit.Test

/** Synthetic diaries only. Each layout is applied as a launcher would, into a frame of the widget's size. */
class CaloriesWidgetTest {
    private val app: MivuApplication = ApplicationProvider.getApplicationContext()
    private val density = app.resources.displayMetrics.density
    private val now = System.currentTimeMillis()
    private val day = WidgetSnapshot("2026-10-25", 1360.0, 2100.0, true, rolloverAt = now + 3_600_000, writtenAt = now)

    companion object {
        private lateinit var profileID: UUID
        /** Read before any test writes, so test order cannot change it. */
        private lateinit var seeded: WidgetSnapshot

        fun meal(db: DiaryDatabase, name: String, kcal: Double) {
            val at = Instant.now()
            val item = FoodItem(UUID.randomUUID(), name, 1.0, "serving", NutritionValues(kcal, null, null, null),
                NutritionProvenance.user, "Entered manually", false, emptyMap())
            db.saveManualNutrition(ManualNutritionPayload(profileID, UUID.randomUUID(), UUID.randomUUID(), ManualNutritionOperation.create,
                db.prepareManualNutritionTarget(ManualNutritionDayChoice.Current, at), at, at, MealTimePrecision.exact, null, listOf(item)),
                db.head().revision)
        }

        // Before anything opens the app's diary: today's fixture, opened by the app's own repository.
        @BeforeClass @JvmStatic fun seed() {
            val context: Context = ApplicationProvider.getApplicationContext()
            TodayFixture.wipe(context)
            profileID = TodayFixture.seed(context, photo = false) // 380 + 640 kcal
            val app = context as MivuApplication
            assertTrue(runBlocking { app.repository.bootstrap() } is Bootstrap.Ready)
            val db = app.repository.database(profileID)
            val zone = ZoneId.systemDefault().id
            val today = db.read { tx -> tx.day(tx.head.activeDayID!!)!!.localDate }
            // Today's goal wins over the fixture's older one; a later one has not started yet.
            db.transaction(db.head().revision) {
                it.putGoal(GoalRecord(UUID.randomUUID(), today, zone, 1, NutritionValues(2100.0, null, null, null), null, false))
                it.putGoal(GoalRecord(UUID.randomUUID(), LocalDate.parse(today).plusDays(1).toString(), zone, 1,
                    NutritionValues(2500.0, null, null, null), null, false))
            }
            meal(db, "Synthetic yogurt bowl", 340.0)
            seeded = db.widgetSnapshot(Instant.now())
        }
    }

    private fun apply(views: RemoteViews, widthDp: Int, heightDp: Int): View {
        val parent = FrameLayout(app)
        return measured(parent, views.apply(app, parent), widthDp, heightDp)
    }

    private fun measured(parent: FrameLayout, view: View, widthDp: Int, heightDp: Int): View {
        parent.addView(view, ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
        val w = View.MeasureSpec.makeMeasureSpec((widthDp * density).toInt(), View.MeasureSpec.EXACTLY)
        val h = View.MeasureSpec.makeMeasureSpec((heightDp * density).toInt(), View.MeasureSpec.EXACTLY)
        parent.measure(w, h)
        parent.layout(0, 0, parent.measuredWidth, parent.measuredHeight)
        return parent
    }

    private fun small(snapshot: WidgetSnapshot?, at: Long = now) = apply(CaloriesWidget.small(app, snapshot, at), 110, 110)
    private fun medium(snapshot: WidgetSnapshot?) = apply(CaloriesWidget.medium(app, snapshot, now), 330, 180)
    private fun View.visibleWords(): List<CharSequence> = if (visibility != View.VISIBLE) emptyList()
        else listOfNotNull((this as? TextView)?.text, contentDescription) + (this as? ViewGroup)?.children?.flatMap { it.visibleWords() }.orEmpty()
    private fun View.text(id: Int) = findViewById<TextView>(id).text.toString()
    // isShown needs a window; this walks the same visibility chain up the detached frame.
    private fun View.shown(id: Int) = generateSequence(findViewById<View>(id)) { it.parent as? View }.all { it.visibility == View.VISIBLE }

    @Test fun smallShowsIntakeAndGoal() {
        val view = small(day)
        assertEquals("1,360", view.text(R.id.widget_eaten))
        assertEquals("of 2,100 kcal", view.text(R.id.widget_goal))
        assertEquals("1,360 of 2,100 calories eaten", view.findViewById<View>(R.id.widget_figure).contentDescription)
        assertTrue(view.shown(R.id.widget_bar))
        assertFalse(view.findViewById<View>(R.id.widget_pip).isImportantForAccessibility)
    }

    @Test fun initialLayoutShowsNoNumbers() {
        val info = AppWidgetManager.getInstance(app).getInstalledProvidersForPackage(app.packageName, null)
            .single { it.provider.className == CaloriesWidgetProvider::class.java.name }
        val root = LayoutInflater.from(app).inflate(info.initialLayout, FrameLayout(app), false)
        val words = root.visibleWords().joinToString(" ")
        assertFalse(words, words.any(Char::isDigit))
        assertTrue(words, "Set up Mivu" in words)
    }

    @Test fun largeTextShrinksInsteadOfClipping() {
        val large = app.createConfigurationContext(Configuration(app.resources.configuration).apply { fontScale = 2f })
        fun TextView.assertFits() {
            val room = width - totalPaddingLeft - totalPaddingRight
            assertTrue("\"$text\" needs ${layout.getLineWidth(0)} of $room px", layout.lineCount == 1 && layout.getLineWidth(0) <= room)
        }
        // RemoteViews.apply inflates with the package's own context, dropping the override: inflate here, then reapply.
        fun inflate(views: RemoteViews, widthDp: Int): View {
            val parent = FrameLayout(large)
            val view = LayoutInflater.from(large).inflate(views.layoutId, parent, false).also { views.reapply(large, it) }
            return measured(parent, view, widthDp, 210)
        }
        inflate(CaloriesWidget.small(app, day, now), 179).findViewById<TextView>(R.id.widget_goal).assertFits()
        val medium = inflate(CaloriesWidget.medium(app, day, now), 373)
        for (id in listOf(R.id.widget_goal, R.id.widget_snap_it, R.id.widget_coach)) medium.findViewById<TextView>(id).assertFits()
    }

    @Test fun mediumHasSnapItAndCoach() {
        val view = medium(day)
        assertEquals("Today", view.text(R.id.widget_eyebrow))
        assertEquals("1,360", view.text(R.id.widget_eaten))
        for ((id, label) in listOf(R.id.widget_snap_it to "Snap It", R.id.widget_coach to "Coach")) {
            val button = view.findViewById<TextView>(id)
            assertEquals(label, button.text.toString())
            assertTrue(view.shown(id) && button.hasOnClickListeners())
            assertTrue("$label is ${button.height / density} dp high", button.height >= 48 * density - 0.5f)
        }
    }

    @Test fun noDiaryShowsSetUp() {
        for (view in listOf(small(null), medium(null), small(day.copy(hasDiary = false)))) {
            assertEquals("Set up Mivu", view.text(R.id.widget_setup_title))
            assertEquals("Pip will track your day here.", view.text(R.id.widget_setup_body))
            assertTrue(view.shown(R.id.widget_setup_title))
            assertFalse(view.shown(R.id.widget_figure))
        }
        assertFalse(medium(null).shown(R.id.widget_snap_it))
    }

    @Test fun noTargetShowsSetATarget() {
        val view = small(day.copy(target = null))
        assertEquals("kcal recorded", view.text(R.id.widget_goal))
        assertEquals("Set a target", view.text(R.id.widget_set_target))
        assertTrue(view.shown(R.id.widget_set_target))
        assertFalse(view.shown(R.id.widget_bar))
        assertEquals("1,360 calories eaten", view.findViewById<View>(R.id.widget_figure).contentDescription)
    }

    @Test fun rolloverEntryShowsZeroAfterCutoff() {
        val view = small(day, at = day.rolloverAt + 1)
        assertEquals("0", view.text(R.id.widget_eaten))
        assertEquals("of 2,100 kcal", view.text(R.id.widget_goal))
    }

    @Test fun snapshotFromDatabaseUsesTodaysGoal() {
        val snapshot = seeded
        assertTrue(snapshot.hasDiary)
        assertEquals(1360.0, snapshot.eaten, 0.0)
        assertEquals(2100.0, snapshot.target!!, 0.0)
        assertEquals("1,360", small(snapshot).text(R.id.widget_eaten))
        assertTrue(snapshot.rolloverAt > System.currentTimeMillis())
    }

    @Test fun snapshotFollowsADiaryWrite() {
        val db = app.repository.database(profileID)
        val before = db.widgetSnapshot(Instant.now()).eaten
        meal(db, "Synthetic apple", 95.0)
        val deadline = System.currentTimeMillis() + 2_000
        while (CaloriesWidget.stored(app)?.eaten != before + 95 && System.currentTimeMillis() < deadline) Thread.sleep(25)
        assertEquals(before + 95, CaloriesWidget.stored(app)?.eaten)
    }
}
