package com.yakov103.mivu.ui

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test

/** Pip's reviewed moment reaches Today only when meal detail was opened from Today, though Today stays in the back stack. */
class ReviewedOriginTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private lateinit var nav: NavHostController

    private fun launch() = compose.setContent {
        nav = rememberNavController()
        NavHost(nav, startDestination = Route.Today) {
            composable<Route.Today> {}
            composable<Route.Diary> {}
            composable<Route.MealDetail> {}
        }
    }

    @Test fun mealDetailFromTodayReachesToday() {
        launch()
        compose.runOnIdle { nav.navigate(Route.MealDetail("m")) }
        compose.runOnIdle { assertNotNull(nav.todayOrigin()) }
    }

    @Test fun mealDetailFromDiaryDoesNotReachToday() {
        launch()
        compose.runOnIdle {
            // As MivuApp's selectTab: Today stays at the bottom of the back stack.
            nav.navigate(Route.Diary) {
                popUpTo(nav.graph.findStartDestination().id) { saveState = true }
                launchSingleTop = true
                restoreState = true
            }
        }
        compose.runOnIdle { nav.navigate(Route.MealDetail("m")) }
        compose.runOnIdle {
            assertNotNull(nav.getBackStackEntry<Route.Today>())
            assertNull(nav.todayOrigin())
        }
    }
}
