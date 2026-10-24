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
import androidx.compose.runtime.remember
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
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.isImeVisible
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import com.yakov103.mivu.ui.coach.AskPip
import com.yakov103.mivu.ui.composer.preparePhoto
import java.io.File
import com.yakov103.mivu.ui.manual.ManualNutritionViewModel
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.yakov103.mivu.R
import com.yakov103.mivu.SampleMode
import com.yakov103.mivu.ui.today.PlanWelcome
import com.yakov103.mivu.ui.today.TodayScreen
import com.yakov103.mivu.ui.coach.CoachCameraScreen
import com.yakov103.mivu.ui.coach.CoachScreen
import com.yakov103.mivu.ui.coach.CoachViewModel
import com.yakov103.mivu.ui.coach.CoachHistoryScreen
import com.yakov103.mivu.ui.coach.CoachHistoryWindow
import androidx.compose.runtime.produceState
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.customActions
import java.time.ZoneId
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.CoroutineScope
import com.yakov103.mivu.coach.CoachActivity
import androidx.lifecycle.viewmodel.compose.LocalViewModelStoreOwner
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import com.yakov103.mivu.ui.diary.DiaryScreen
import com.yakov103.mivu.ui.progress.GoalEditorScreen
import com.yakov103.mivu.ui.progress.GoalEditorViewModel
import com.yakov103.mivu.ui.progress.WeightEditorScreen
import com.yakov103.mivu.ui.progress.WeightEditorViewModel
import com.yakov103.mivu.ui.progress.WorkoutDetailScreen
import com.yakov103.mivu.ui.progress.WorkoutDetailViewModel
import com.yakov103.mivu.ui.progress.WorkoutEditorScreen
import com.yakov103.mivu.ui.progress.WorkoutEditorViewModel
import com.yakov103.mivu.ui.diary.DiaryViewModel
import com.yakov103.mivu.progress.ProgressRange
import com.yakov103.mivu.ui.progress.ProgressDetailKind
import com.yakov103.mivu.ui.progress.ProgressDetailScreen
import com.yakov103.mivu.ui.progress.ProgressDetailViewModel
import com.yakov103.mivu.ui.progress.ProgressScreen
import com.yakov103.mivu.ui.progress.ProgressViewModel
import com.yakov103.mivu.ui.today.TodayViewModel
import com.yakov103.mivu.diary.Bootstrap
import com.yakov103.mivu.diary.DiaryProfile
import com.yakov103.mivu.diary.DiaryRepository
import java.util.UUID
import kotlinx.coroutines.launch
import kotlinx.serialization.Serializable
import com.yakov103.mivu.connection.ChatGPTConnection
import com.yakov103.mivu.connection.ConnectionState
import com.yakov103.mivu.ui.settings.ConnectionScreen
import com.yakov103.mivu.ui.settings.SettingsScreen
import com.yakov103.mivu.ui.settings.openCustomTab
import com.yakov103.mivu.connection.SessionError
import com.yakov103.mivu.ui.onboarding.OnboardingScreen
import com.yakov103.mivu.ui.onboarding.OnboardingViewModel

/** The app's Coach worker as the Coach tab uses it: run saved turns, whether ChatGPT is connected, and the running turn. */
class CoachHooks(
    /** Runs saved turns; true marks a connection or network change. */
    val drain: (retryWaiting: Boolean) -> Unit = {},
    val connected: StateFlow<Boolean> = MutableStateFlow(false),
    val activity: StateFlow<Pair<UUID, CoachActivity>?> = MutableStateFlow(null),
)

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
    /** [retaking] is the draft photo path a shot replaces. */
    @Serializable data class CoachCamera(val retaking: String? = null) : Route
    @Serializable data object CoachHistory : Route
    @Serializable data object Settings : Route
    @Serializable data object Connection : Route
    /** "Add weight manually" (today, or [dayID]) or, with [weightID], "Edit weight". */
    @Serializable data class WeightEditor(val dayID: String? = null, val weightID: String? = null) : Route
    @Serializable data class WorkoutEditor(val localDate: String, val dayID: String? = null, val sessionID: String? = null) : Route
    @Serializable data class WorkoutDetail(val sessionID: String) : Route
    @Serializable data object Goals : Route
    /** A Progress card's full screen: [kind] is a [ProgressDetailKind] and [range] the [ProgressRange] it opened on. */
    @Serializable data class ProgressDetail(val kind: String, val range: String = ProgressRange.Week.name) : Route
    /** Setup with Pip: once over a diary this launch created, and from Settings' "Redo setup with Pip". */
    @Serializable data object Onboarding : Route
}

private enum class Tab(val route: Route, val label: String, @DrawableRes val icon: Int, @DrawableRes val selectedIcon: Int) {
    Today(Route.Today, "Today", R.drawable.ic_today, R.drawable.ic_today),
    Diary(Route.Diary, "Diary", R.drawable.ic_diary, R.drawable.ic_diary_filled),
    Progress(Route.Progress, "Progress", R.drawable.ic_progress, R.drawable.ic_progress),
    Coach(Route.Coach, "Coach", R.drawable.ic_coach, R.drawable.ic_coach_filled),
}

/**
 * The app root, as iOS `DiaryRootView`: diary setup until a diary is open, then the four tabs. [onMealCaptured] runs
 * after a capture is saved, with its profile, to start analysis outside the screen. [coach] connects the Coach tab to the
 * app's Coach worker. [connection] backs Settings' Coach AI screen; without it (tests) the screen shows a disconnected state.
 * [setupNewDiary] opens setup with Pip once over a diary this launch created (the activity passes true; tests opt in).
 */
@Composable
fun MivuApp(
    repository: DiaryRepository,
    onMealCaptured: (UUID) -> Unit = {},
    coach: CoachHooks = CoachHooks(),
    connection: ChatGPTConnection? = null,
    /** Outlives screens and configuration changes; a disconnect runs here. */
    appScope: CoroutineScope = rememberCoroutineScope(),
    setupNewDiary: Boolean = false,
) {
    val state by repository.bootstrapState.collectAsState()
    val scope = rememberCoroutineScope()
    // A finished result survives activity recreation in the repository, so only the first composition starts one.
    LaunchedEffect(repository) { if (repository.bootstrapState.value == null) repository.bootstrap() }
    Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
        when (state) {
            is Bootstrap.Ready -> Shell(repository, (state as Bootstrap.Ready).profileID, onMealCaptured, coach, connection, appScope, setupNewDiary)
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

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
private fun Shell(repository: DiaryRepository, profileID: UUID, onMealCaptured: (UUID) -> Unit, hooks: CoachHooks, connection: ChatGPTConnection?,
    appScope: CoroutineScope, setupNewDiary: Boolean) {
    val navController = rememberNavController()
    LaunchedEffect(profileID) { if (setupNewDiary && repository.takeCreated()) navController.navigate(Route.Onboarding) }
    // Coach keeps its window across tab switches: its view model belongs to the activity, not the Coach entry.
    val activityOwner = checkNotNull(LocalViewModelStoreOwner.current)
    val context = LocalContext.current.applicationContext
    val coach = viewModel(viewModelStoreOwner = activityOwner, key = "coach-$profileID") {
        val photos = File(context.cacheDir, "coach/$profileID")
        CoachViewModel(repository, profileID, hooks.drain, hooks.connected, hooks.activity, createSavedStateHandle(),
            prepare = { preparePhoto(context.contentResolver, it, photos) })
    }
    var focusCoach by rememberSaveable { mutableStateOf(false) }
    // Ask Pip: the quote goes first (it never replaces a started message), then the unsent draft, then Coach with the field focused.
    val askPip = { ask: AskPip ->
        val (reply, draft) = ask.handoff()
        coach.startReply(reply, draft)
        focusCoach = true
    }
    val connectionState by connectionState(connection)
    // The owner calls back off the main thread, maybe after a rotation: the tab starts from the app, on the main thread.
    val connect: () -> Unit = { connection?.connect { url -> context.mainExecutor.execute { context.openCustomTab(url) } } }
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
                    if (root == Tab.Coach) CoachHistoryButton(coach) { navController.navigate(Route.CoachHistory) }
                    IconButton(onClick = { navController.navigate(Route.Settings) }, Modifier.testTag("profileSettings")) {
                        Icon(painterResource(R.drawable.ic_profile), contentDescription = "Profile and settings")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background),
            )
        },
        bottomBar = {
            // The keyboard covers the bar's place: the composer rides on the keyboard instead.
            if (root != null && !WindowInsets.isImeVisible) ShortNavigationBar {
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
                    onLogWithPip = { focusCoach = true; selectTab(Route.Coach) },
                    // As iOS Today: the current day (a new one when it has turned over), not a recorded-day target.
                    onAddManually = { navController.navigate(Route.ManualEntry(null, null)) },
                    onLogMeal = { navController.navigate(Route.Composer) },
                    onAddWeight = { navController.navigate(Route.WeightEditor()) },
                    onEditGoals = { navController.navigate(Route.Goals) },
                )
            }
            composable<Route.Diary> {
                val diary = viewModel(key = "diary-$profileID") { DiaryViewModel(repository, profileID, SampleMode.enabled) }
                DiaryScreen(
                    diary,
                    onOpenMeal = { navController.navigate(Route.MealDetail(it.toString())) },
                    onAskPip = { askPip(it); selectTab(Route.Coach) },
                    onEnterNutrition = { navController.navigate(Route.ManualEntry(it.toString(), null)) },
                    onProfile = { navController.navigate(Route.Settings) },
                    onAddWeight = { navController.navigate(Route.WeightEditor(dayID = it.toString())) },
                    onAddWorkout = { date, day -> navController.navigate(Route.WorkoutEditor(date, day.toString())) },
                    onOpenWorkout = { navController.navigate(Route.WorkoutDetail(it.toString())) },
                )
            }
            composable<Route.MealDetail> { entry ->
                val mealID = UUID.fromString(entry.toRoute<Route.MealDetail>().mealID)
                val model = viewModel { MealDetailViewModel(repository, profileID, mealID, SampleMode.enabled, createSavedStateHandle()) }
                MealDetailScreen(
                    model,
                    onBack = { navController.popBackStack() },
                    // As iOS dismisses meal detail first: the tab it came from is not left on it.
                    onAskPip = { ask ->
                        askPip(ask)
                        // iOS askPip: Coach opens at the turn that logged the meal, else at the meal's day.
                        model.state.value?.meal?.let { coach.seekSource(it.id, it.dayID) }
                        navController.popBackStack(); selectTab(Route.Coach)
                    },
                    onAddFoodManually = { navController.navigate(Route.ManualEntry(null, mealID.toString())) },
                    // Live analysis runs through Coach, as on iOS: the meal's own saved turn runs again.
                    onRetryAnalysis = { if (SampleMode.enabled) onMealCaptured(profileID) else coach.retryMeal(mealID) },
                )
            }
            composable<Route.WorkoutDetail> { entry ->
                val id = UUID.fromString(entry.toRoute<Route.WorkoutDetail>().sessionID)
                WorkoutDetailScreen(
                    viewModel { WorkoutDetailViewModel(repository, profileID, id) },
                    onBack = { navController.popBackStack() },
                    onEdit = { date, session -> navController.navigate(Route.WorkoutEditor(date, sessionID = session.toString())) },
                    onAskPip = { askPip(it); navController.popBackStack(); selectTab(Route.Coach) },
                )
            }
            composable<Route.Progress> {
                val model = viewModel(key = "progress-$profileID") { ProgressViewModel(repository, profileID) }
                ProgressScreen(
                    model,
                    onOpenDetail = { navController.navigate(Route.ProgressDetail(it.name, model.range.value.name)) },
                    onOpenGoals = { navController.navigate(Route.Goals) },
                    onOpenDiary = { selectTab(Route.Diary) },
                )
            }
            composable<Route.ProgressDetail> { entry ->
                val route = entry.toRoute<Route.ProgressDetail>()
                val model = viewModel {
                    ProgressDetailViewModel(repository, profileID, ProgressDetailKind.valueOf(route.kind), ProgressRange.valueOf(route.range))
                }
                ProgressDetailScreen(
                    model,
                    onBack = { navController.popBackStack() },
                    onEditWeight = { navController.navigate(Route.WeightEditor(weightID = it.toString())) },
                    onAddWeight = { navController.navigate(Route.WeightEditor()) },
                    onAddWorkout = { navController.navigate(Route.WorkoutEditor(it)) },
                    onOpenWorkout = { navController.navigate(Route.WorkoutDetail(it.toString())) },
                    onAskPip = { askPip(it); navController.popBackStack(); selectTab(Route.Coach) },
                )
            }
            composable<Route.Coach> {
                // The weigh-in bubble reads the same day and preferences as Today's check-in.
                val checkIn = viewModel(key = "checkIn-$profileID") { TodayViewModel(repository, profileID, SampleMode.enabled) }
                CoachScreen(
                    coach,
                    onOpenMeal = { navController.navigate(Route.MealDetail(it.toString())) },
                    onSeeToday = { selectTab(Route.Today) },
                    onSeeProgress = { selectTab(Route.Progress) },
                    focusRequested = focusCoach,
                    onFocusConsumed = { focusCoach = false },
                    onOpenCamera = { navController.navigate(Route.CoachCamera(it)) },
                    connection = connectionState,
                    onAgree = { connection?.recordConsent() },
                    onConnect = connect,
                    onOpenConnection = { navController.navigate(Route.Connection) },
                    onOpenSettings = { navController.navigate(Route.Settings) },
                    checkIn = checkIn,
                )
            }
            composable<Route.CoachHistory> {
                val zone by produceState(ZoneId.systemDefault()) {
                    value = withContext(Dispatchers.IO) {
                        runCatching { ZoneId.of(repository.database(profileID).head().profile.timeZoneID) }.getOrDefault(value)
                    }
                }
                CoachHistoryScreen(coach, zone, onOpen = { coach.seek(it); navController.popBackStack() },
                    onClose = { navController.popBackStack() })
            }
            composable<Route.Settings> {
                // shortcut: "Backup & export" does nothing until Task 7 adds its screen.
                SettingsScreen(connectionState, onOpenConnection = { navController.navigate(Route.Connection) },
                    onOpenGoals = { navController.navigate(Route.Goals) },
                    onRedoSetup = { navController.navigate(Route.Onboarding) },
                    onBack = { navController.popBackStack() })
            }
            composable<Route.Connection> {
                ConnectionScreen(
                    connectionState,
                    onAgree = { connection?.recordConsent() },
                    onConnect = connect,
                    onCancel = { connection?.cancelConnection() },
                    onSelectModel = { connection?.selectModel(it) },
                    // Leaving the screen must not stop (or drop) a disconnect halfway through deleting the session.
                    onDisconnect = { appScope.launch { withContext(NonCancellable) { connection?.disconnect() } } },
                    onBack = { navController.popBackStack() },
                )
            }
            // Full screen over Coach: Coach is no longer resumed, so Pip hides; the draft lives in the activity's model.
            dialog<Route.CoachCamera>(
                dialogProperties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false),
            ) { entry ->
                CoachCameraScreen(coach, entry.toRoute<Route.CoachCamera>().retaking,
                    onClose = { navController.popBackStack<Route.CoachCamera>(inclusive = true) })
            }
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
            // The Progress editors, full screen as manual entry: the screen owns back so an edit asks before it is discarded.
            val editor = DialogProperties(dismissOnBackPress = false, usePlatformDefaultWidth = false, decorFitsSystemWindows = false)
            dialog<Route.WeightEditor>(dialogProperties = editor) { entry ->
                val route = entry.toRoute<Route.WeightEditor>()
                val model = viewModel {
                    WeightEditorViewModel(repository, profileID, route.dayID?.let(UUID::fromString), route.weightID?.let(UUID::fromString))
                }
                WeightEditorScreen(model, onClose = { navController.popBackStack<Route.WeightEditor>(inclusive = true) })
            }
            dialog<Route.WorkoutEditor>(dialogProperties = editor) { entry ->
                val route = entry.toRoute<Route.WorkoutEditor>()
                val model = viewModel {
                    WorkoutEditorViewModel(repository, profileID, route.localDate, route.dayID?.let(UUID::fromString), route.sessionID?.let(UUID::fromString))
                }
                WorkoutEditorScreen(model, onClose = { navController.popBackStack<Route.WorkoutEditor>(inclusive = true) })
            }
            dialog<Route.Goals>(dialogProperties = editor) {
                GoalEditorScreen(viewModel { GoalEditorViewModel(repository, profileID) },
                    onClose = { navController.popBackStack<Route.Goals>(inclusive = true) })
            }
            // Full screen; the screen owns back after its first step, where back is "Later".
            dialog<Route.Onboarding>(dialogProperties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
                val model = viewModel {
                    OnboardingViewModel(repository, profileID, connection?.state ?: MutableStateFlow(ConnectionState()),
                        { connection?.inference() ?: { _, _ -> throw SessionError.NoActiveSession } }, createSavedStateHandle())
                }
                OnboardingScreen(model, onAgree = { connection?.recordConsent() }, onConnect = connect,
                    onFinish = { navController.popBackStack<Route.Onboarding>(inclusive = true) })
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
    // As iOS, over any tab once no route (capture, manual entry, meal detail) covers it, so it waits instead of being dropped.
    if (connectionState.showsPlanWelcome && root != null) PlanWelcome { connection?.acknowledgePlanWelcome() }
}

/**
 * iOS Chat history toolbar button. Its accessibility actions page the timeline as iOS `accessibilityPageAction` does:
 * load (or retry) earlier and later messages around the reader's visible rows.
 */
@Composable
private fun CoachHistoryButton(coach: CoachViewModel, onOpen: () -> Unit) {
    val state by coach.timeline.collectAsStateWithLifecycle()
    fun action(direction: CoachHistoryWindow.Direction): CustomAccessibilityAction? {
        val earlier = direction == CoachHistoryWindow.Direction.earlier
        val label = when (if (earlier) state.earlier else state.later) {
            CoachHistoryWindow.EdgeState.Available -> if (earlier) "Load earlier messages" else "Load later messages"
            is CoachHistoryWindow.EdgeState.Failed -> if (earlier) "Retry earlier messages" else "Retry later messages"
            else -> return null
        }
        return CustomAccessibilityAction(label) {
            if (earlier) coach.loadEarlier(coach.visible) else coach.loadLater(coach.visible)
            true
        }
    }
    val actions = listOfNotNull(action(CoachHistoryWindow.Direction.earlier), action(CoachHistoryWindow.Direction.later))
    IconButton(onOpen, Modifier.semantics { customActions = actions }) {
        Icon(painterResource(R.drawable.ic_history), contentDescription = "Chat history")
    }
}

@Composable
private fun connectionState(connection: ChatGPTConnection?) =
    connection?.state?.collectAsStateWithLifecycle() ?: remember { mutableStateOf(ConnectionState()) }
