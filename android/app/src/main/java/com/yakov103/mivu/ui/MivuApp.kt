package com.yakov103.mivu.ui

import androidx.annotation.DrawableRes
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.safeDrawingPadding
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
import androidx.compose.ui.unit.Density
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.runtime.CompositionLocalProvider
import androidx.navigation.NavDestination.Companion.hasRoute
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.yakov103.mivu.R
import com.yakov103.mivu.SampleMode
import com.yakov103.mivu.ui.today.TodayScreen
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
}

private enum class Tab(val route: Route, val label: String, @DrawableRes val icon: Int, @DrawableRes val selectedIcon: Int) {
    Today(Route.Today, "Today", R.drawable.ic_today, R.drawable.ic_today),
    Diary(Route.Diary, "Diary", R.drawable.ic_diary, R.drawable.ic_diary_filled),
    Progress(Route.Progress, "Progress", R.drawable.ic_progress, R.drawable.ic_progress),
    Coach(Route.Coach, "Coach", R.drawable.ic_coach, R.drawable.ic_coach_filled),
}

/** The app root, as iOS `DiaryRootView`: diary setup until a diary is open, then the four tabs. */
@Composable
fun MivuApp(repository: DiaryRepository) {
    val state by repository.bootstrapState.collectAsState()
    val scope = rememberCoroutineScope()
    // A finished result survives activity recreation in the repository, so only the first composition starts one.
    LaunchedEffect(repository) { if (repository.bootstrapState.value == null) repository.bootstrap() }
    Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
        when (state) {
            is Bootstrap.Ready -> Shell(repository, (state as Bootstrap.Ready).profileID)
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
private fun Shell(repository: DiaryRepository, profileID: UUID) {
    val navController = rememberNavController()
    val entry by navController.currentBackStackEntryAsState()
    val current = Tab.entries.firstOrNull { tab -> entry?.destination?.hasRoute(tab.route::class) == true } ?: Tab.Today
    val selectTab = { route: Route ->
        navController.navigate(route) {
            popUpTo(navController.graph.findStartDestination().id) { saveState = true }
            launchSingleTop = true
            restoreState = true
        }
    }
    Scaffold(
        topBar = {
            TopAppBar(
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
            ShortNavigationBar {
                Tab.entries.forEach { tab ->
                    val selected = tab == current
                    ShortNavigationBarItem(
                        selected = selected,
                        onClick = { selectTab(tab.route) },
                        icon = { Icon(painterResource(if (selected) tab.selectedIcon else tab.icon), contentDescription = null) },
                        label = {
                            // Labels scale to 150% at most: at 200% "Progress" no longer fits a quarter of a phone and breaks mid-word.
                            val density = LocalDensity.current
                            CompositionLocalProvider(LocalDensity provides Density(density.density, minOf(density.fontScale, 1.5f))) {
                                Text(tab.label, maxLines = 1)
                            }
                        },
                    )
                }
            }
        },
    ) { padding ->
        NavHost(navController, startDestination = Route.Today, Modifier.padding(padding)) {
            composable<Route.Today> { entry ->
                val today = viewModel(key = profileID.toString()) { TodayViewModel(repository, profileID, SampleMode.enabled) }
                // Capture screens hand back the saved meal through this entry, for the "Saved on this phone" receipt.
                val saved by entry.savedStateHandle.getStateFlow<String?>(SAVED_MEAL_ID, null).collectAsStateWithLifecycle()
                LaunchedEffect(saved) {
                    saved?.let { today.showReceipt(UUID.fromString(it)); entry.savedStateHandle[SAVED_MEAL_ID] = null }
                }
                TodayScreen(
                    today,
                    onOpenMeal = null, // shortcut: meal detail arrives with the Diary milestone; rows open it then.
                    onLogWithPip = { selectTab(Route.Coach) },
                    onAddManually = { day -> navController.navigate(Route.ManualEntry(day?.toString(), null)) },
                    onLogMeal = { navController.navigate(Route.Composer) },
                )
            }
            composable<Route.Diary> { LaterUpdate() }
            composable<Route.Progress> { LaterUpdate() }
            composable<Route.Coach> { LaterUpdate() }
            // shortcut: placeholders until the manual entry and composer screens replace them.
            composable<Route.ManualEntry> { LaterUpdate(Modifier.testTag("manualEntryRoute")) }
            composable<Route.Composer> { LaterUpdate() }
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
