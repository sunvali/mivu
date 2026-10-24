package com.yakov103.mivu.ui

import androidx.annotation.DrawableRes
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.ScaffoldDefaults
import androidx.compose.material3.ShortNavigationBar
import androidx.compose.material3.ShortNavigationBarItem
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.platform.LocalDensity
import androidx.navigation.NavDestination.Companion.hasRoute
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.dialog
import androidx.navigation.toRoute
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.createSavedStateHandle
import com.yakov103.mivu.ui.composer.MealComposerScreen
import com.yakov103.mivu.ui.composer.MealComposerViewModel
import com.yakov103.mivu.ui.manual.ManualNutritionScreen
import com.yakov103.mivu.ui.meal.MealDetailScreen
import com.yakov103.mivu.ui.meal.MealDetailViewModel
import androidx.compose.ui.platform.LocalContext
import com.yakov103.mivu.ui.manual.ManualNutritionViewModel
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.yakov103.mivu.R
import com.yakov103.mivu.SampleMode
import com.yakov103.mivu.ui.today.TodayScreen
import com.yakov103.mivu.ui.diary.DiaryScreen
import com.yakov103.mivu.ui.diary.DiaryViewModel
import com.yakov103.mivu.ui.today.TodayViewModel
import com.yakov103.mivu.diary.Bootstrap
import com.yakov103.mivu.diary.DiaryProfile
import com.yakov103.mivu.diary.DiaryRepository
import java.util.UUID
import kotlinx.coroutines.launch
import kotlinx.serialization.Serializable

/** The savedStateHandle key a capture screen sets on the Today entry when it saves a meal. */
const val SAVED_MEAL_ID = "savedMealID"

@Serializable
sealed interface Route {
    @Serializable data object Today : Route
    @Serializable data object Diary : Route
    @Serializable data object Progress : Route
    @Serializable data object Coach : Route
    @Serializable data class ManualEntry(val dayID: String?, val mealID: String?) : Route
    @Serializable data object Composer : Route
    @Serializable data class MealDetail(val mealID: String) : Route
}

private enum class Tab(val route: Route, val label: String, @DrawableRes val icon: Int, @DrawableRes val selectedIcon: Int) {
    Today(Route.Today, "Today", R.drawable.ic_today, R.drawable.ic_today),
    Diary(Route.Diary, "Diary", R.drawable.ic_diary, R.drawable.ic_diary_filled),
    Progress(Route.Progress, "Progress", R.drawable.ic_progress, R.drawable.ic_progress),
    Coach(Route.Coach, "Coach", R.drawable.ic_coach, R.drawable.ic_coach_filled),
}

/**
 * The app root, as iOS `DiaryRootView`: diary setup until a diary is open, then the four tabs. [onMealCaptured] runs
 * after a capture is saved, with its profile, to start analysis outside the screen.
 */
@Composable
fun MivuApp(repository: DiaryRepository, onMealCaptured: (UUID) -> Unit = {}) {
    val state by repository.bootstrapState.collectAsState()
    val scope = rememberCoroutineScope()
    // A finished result survives activity recreation in the repository, so only the first composition starts one.
    LaunchedEffect(repository) { if (repository.bootstrapState.value == null) repository.bootstrap() }
    Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
        when (state) {
            is Bootstrap.Ready -> Shell(repository, (state as Bootstrap.Ready).profileID, onMealCaptured)
            Bootstrap.Failed -> SetupMessage("Couldn't create your diary") {
                Button(onClick = { scope.launch { repository.bootstrap() } }) { Text("Try again") }
            }
            is Bootstrap.Choose -> ChooseDiary((state as Bootstrap.Choose).profiles) { id -> scope.launch { repository.choose(id) } }
            null -> SetupMessage("Setting up your diary") { CircularProgressIndicator() }
        }
    }
}

@Composable
private fun SetupMessage(text: String, action: @Composable () -> Unit) {
    Column(
        Modifier.fillMaxSize().padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(text, style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center)
        action()
    }
}

/** The stored diary is gone: list the ones on this phone instead of opening one silently. */
@Composable
private fun ChooseDiary(profiles: List<DiaryProfile>, onChoose: (UUID) -> Unit) {
    LazyColumn(Modifier.fillMaxSize().safeDrawingPadding(), contentPadding = PaddingValues(vertical = 24.dp)) {
        item {
            Text("Choose a diary", Modifier.padding(horizontal = 16.dp, vertical = 8.dp).semantics { heading() },
                style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
        }
        items(profiles, key = { it.id }) { profile ->
            ListItem(
                headlineContent = { Text(profile.name) },
                modifier = Modifier.clickable { onChoose(profile.id) },
                colors = ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.background),
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun Shell(repository: DiaryRepository, profileID: UUID, onMealCaptured: (UUID) -> Unit) {
    val navController = rememberNavController()
    val entry by navController.currentBackStackEntryAsState()
    val root = Tab.entries.firstOrNull { tab -> entry?.destination?.hasRoute(tab.route::class) == true }
    val current = root ?: Tab.Today
    val selectTab = { route: Route ->
        navController.navigate(route) {
            popUpTo(navController.graph.findStartDestination().id) { saveState = true }
            launchSingleTop = true
            restoreState = true
        }
    }
    Scaffold(
        // Pushed screens such as meal detail draw edge to edge and handle their own insets.
        contentWindowInsets = if (root != null) ScaffoldDefaults.contentWindowInsets else WindowInsets(0),
        topBar = {
            // Diary has its own actions; pushed screens such as meal detail bring their own bar.
            if (root != null && root != Tab.Diary) TopAppBar(
                title = {
                    Text(current.label, Modifier.semantics { heading() },
                        style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
                },
                actions = {
                    // shortcut: Settings arrives with its own milestone; the control is in place so every root has it.
                    IconButton(onClick = {}, Modifier.testTag("profileSettings")) {
                        Icon(painterResource(R.drawable.ic_profile), contentDescription = "Profile and settings")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background),
            )
        },
        bottomBar = {
            if (root != null) ShortNavigationBar {
                Tab.entries.forEach { tab ->
                    val selected = tab == current
                    ShortNavigationBarItem(
                        selected = selected,
                        onClick = { selectTab(tab.route) },
                        icon = { Icon(painterResource(if (selected) tab.selectedIcon else tab.icon), contentDescription = null) },
                        label = {
                            // The label grows with the system's (nonlinear) font scale up to 18 dp: at 200% a full-size
                            // "Progress" no longer fits a quarter of a phone and breaks mid-word.
                            val style = MaterialTheme.typography.labelMedium
                            val size = with(LocalDensity.current) { minOf(style.fontSize.toDp(), 18.dp).toSp() }
                            Text(tab.label, maxLines = 1, style = style.copy(fontSize = size, lineHeight = size * 1.34f))
                        },
                    )
                }
            }
        },
    ) { padding ->
        NavHost(navController, startDestination = Route.Today, Modifier.padding(padding).consumeWindowInsets(padding)) {
            composable<Route.Today> { entry ->
                val today = viewModel(key = profileID.toString()) { TodayViewModel(repository, profileID, SampleMode.enabled) }
                // Capture screens hand back the saved meal through this entry, for the "Saved on this phone" receipt.
                val saved by entry.savedStateHandle.getStateFlow<String?>(SAVED_MEAL_ID, null).collectAsStateWithLifecycle()
                LaunchedEffect(saved) {
                    saved?.let { today.showReceipt(UUID.fromString(it)); entry.savedStateHandle[SAVED_MEAL_ID] = null }
                }
                TodayScreen(
                    today,
                    onOpenMeal = { navController.navigate(Route.MealDetail(it.toString())) },
                    onLogWithPip = { selectTab(Route.Coach) },
                    // As iOS Today: the current day (a new one when it has turned over), not a recorded-day target.
                    onAddManually = { navController.navigate(Route.ManualEntry(null, null)) },
                    onLogMeal = { navController.navigate(Route.Composer) },
                )
            }
            composable<Route.Diary> {
                val diary = viewModel(key = "diary-$profileID") { DiaryViewModel(repository, profileID, SampleMode.enabled) }
                DiaryScreen(
                    diary,
                    onOpenMeal = { navController.navigate(Route.MealDetail(it.toString())) },
                    // shortcut: Ask Pip opens Coach without a day draft until Coach arrives in milestone 4.
                    onAskPip = { selectTab(Route.Coach) },
                    onEnterNutrition = { navController.navigate(Route.ManualEntry(it.toString(), null)) },
                    // shortcut: the profile button does nothing until the Profile and settings screen is ported; wire it then.
                    onProfile = {},
                )
            }
            composable<Route.MealDetail> { entry ->
                val mealID = UUID.fromString(entry.toRoute<Route.MealDetail>().mealID)
                val model = viewModel { MealDetailViewModel(repository, profileID, mealID, SampleMode.enabled, createSavedStateHandle()) }
                MealDetailScreen(
                    model,
                    onBack = { navController.popBackStack() },
                    // shortcut: Ask Pip opens Coach without a meal reply until Coach arrives in milestone 4.
                    onAskPip = { selectTab(Route.Coach) },
                    onAddFoodManually = { navController.navigate(Route.ManualEntry(null, mealID.toString())) },
                    onRetryAnalysis = { onMealCaptured(profileID) },
                )
            }
            composable<Route.Progress> { LaterUpdate() }
            composable<Route.Coach> { LaterUpdate() }
            // The screen owns back (and Escape), so an edited draft always asks before it is discarded.
            dialog<Route.ManualEntry>(
                dialogProperties = DialogProperties(dismissOnBackPress = false, usePlatformDefaultWidth = false, decorFitsSystemWindows = false),
            ) { entry ->
                val route = entry.toRoute<Route.ManualEntry>()
                val model = viewModel {
                    ManualNutritionViewModel(repository, profileID, route.dayID?.let(UUID::fromString), route.mealID?.let(UUID::fromString),
                        createSavedStateHandle())
                }
                val leave = { navController.popBackStack<Route.ManualEntry>(inclusive = true) }
                ManualNutritionScreen(model, onClose = { leave() }, onSaved = { id ->
                    navController.previousBackStackEntry?.savedStateHandle?.set(SAVED_MEAL_ID, id.toString())
                    leave()
                })
            }
            // Sample mode only: Today offers "Log meal" there. Analysis runs outside the screen, after it closes.
            dialog<Route.Composer>(
                dialogProperties = DialogProperties(dismissOnBackPress = false, usePlatformDefaultWidth = false, decorFitsSystemWindows = false),
            ) { entry ->
                val context = LocalContext.current.applicationContext
                val model = viewModel { MealComposerViewModel(repository, profileID, context, createSavedStateHandle()) }
                // "Enter nutrition manually" hands its saved meal back through this entry.
                val manualSaved by entry.savedStateHandle.getStateFlow<String?>(SAVED_MEAL_ID, null).collectAsStateWithLifecycle()
                val leave = { navController.popBackStack<Route.Composer>(inclusive = true) }
                MealComposerScreen(model, manualSaved?.let(UUID::fromString), onClose = { leave() }, onSaved = { id ->
                    navController.previousBackStackEntry?.savedStateHandle?.set(SAVED_MEAL_ID, id.toString())
                    leave()
                    onMealCaptured(profileID)
                }, onEnterManually = { navController.navigate(Route.ManualEntry(null, null)) })
            }
        }
    }
}

@Composable
private fun LaterUpdate(modifier: Modifier = Modifier) {
    Box(modifier.fillMaxSize().padding(24.dp), contentAlignment = Alignment.Center) {
        Text("Arrives in a later update", style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
    }
}
