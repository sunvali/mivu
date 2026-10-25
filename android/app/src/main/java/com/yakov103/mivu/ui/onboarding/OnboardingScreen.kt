package com.yakov103.mivu.ui.onboarding

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.isImeVisible
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import com.yakov103.mivu.R
import com.yakov103.mivu.analysis.ResponsesClient
import com.yakov103.mivu.coach.CoachInferenceInput
import com.yakov103.mivu.coach.CoachInferenceResult
import com.yakov103.mivu.connection.ConnectionState
import com.yakov103.mivu.diary.DiaryRepository
import com.yakov103.mivu.diary.GoalRecord
import com.yakov103.mivu.diary.NutritionValues
import com.yakov103.mivu.diary.ProfileAbout
import com.yakov103.mivu.diary.ProfileAbout.Pace
import com.yakov103.mivu.diary.ProfileAbout.Sex
import com.yakov103.mivu.diary.goal
import com.yakov103.mivu.diary.recordWeight
import com.yakov103.mivu.diary.setGoals
import com.yakov103.mivu.diary.updateProfile
import com.yakov103.mivu.diary.wakingDateLabel
import com.yakov103.mivu.onboarding.OnboardingAnswers
import com.yakov103.mivu.onboarding.OnboardingTargets
import com.yakov103.mivu.onboarding.kgPerWeek
import com.yakov103.mivu.pip.CompanionOutput
import com.yakov103.mivu.pip.CompanionPose
import com.yakov103.mivu.pip.CompanionRuntime
import com.yakov103.mivu.pip.CompanionSurface
import com.yakov103.mivu.pip.MotionPolicy.Playback
import com.yakov103.mivu.pip.PipAssets
import com.yakov103.mivu.pip.PipCompanion
import com.yakov103.mivu.pip.PipGestureLibrary
import com.yakov103.mivu.pip.PipRigScene
import com.yakov103.mivu.pip.rememberMotionPlayback
import com.yakov103.mivu.ui.DialogSystemBarIcons
import com.yakov103.mivu.ui.progress.editorFailure
import com.yakov103.mivu.ui.progress.fieldText
import com.yakov103.mivu.ui.progress.progressNumber
import com.yakov103.mivu.ui.settings.ChatGPTConnectButton
import com.yakov103.mivu.ui.theme.MivuTheme
import com.yakov103.mivu.ui.today.KG_PER_LB
import com.yakov103.mivu.ui.today.WhiteCard
import java.time.Instant
import java.time.LocalDate
import java.time.Year
import java.time.ZoneId
import java.util.UUID
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.roundToLong
import kotlin.properties.ReadWriteProperty
import kotlin.random.Random
import kotlin.reflect.KProperty
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonObject

// Port of ios/Mivu/Onboarding/OnboardingView.swift: Pip asks a few questions, ChatGPT turns them into daily targets,
// and accepting saves the profile, weight and goal. Opens once on a diary this launch created, and from Settings.

private val DietChoices = listOf("Gluten-free", "Lactose-free", "Vegetarian", "Vegan", "Type 1 diabetes", "Type 2 diabetes", "Crohn's", "IBS", "Nut allergy")

/** One decimal, as iOS stores weights and shows pounds. */
private fun tenth(value: Double) = (value * 10).roundToLong() / 10.0

/** A one-shot Pip reaction; a fresh id replays the same pose. */
data class PipReaction(val pose: CompanionPose, val id: UUID = UUID.randomUUID())

/**
 * Setup's answers and step, kept in [savedState] so they survive process death; numbers stay as typed, in the chosen
 * unit, and are read as metric. [inference] binds one request to the connection current now (`ChatGPTConnection.inference`).
 */
class OnboardingViewModel(
    private val repository: DiaryRepository,
    private val profileID: UUID,
    val connection: StateFlow<ConnectionState>,
    private val inference: () -> suspend (List<CoachInferenceInput>, JsonObject?) -> CoachInferenceResult,
    private val savedState: SavedStateHandle,
) : ViewModel() {
    @Suppress("EnumEntryName") // iOS case names
    enum class Step { hello, about, goal, diet, connect, results }

    private fun <T> saved(key: String, initial: T) = object : ReadWriteProperty<Any?, T> {
        val state = mutableStateOf(if (savedState.contains(key)) savedState.get<T>(key) as T else initial)
        override fun getValue(thisRef: Any?, property: KProperty<*>) = state.value
        override fun setValue(thisRef: Any?, property: KProperty<*>, value: T) { state.value = value; savedState[key] = value }
    }

    var step by saved("step", Step.hello); private set
    var heightText by saved("height", "")
    var feetText by saved("feet", "")
    var inchesText by saved("inches", "")
    var weightText by saved("weight", "")
    var birthYearText by saved("birthYear", "")
    var targetText by saved("target", "")
    var sex by saved("sex", Sex.unspecified)
    var pace by saved("pace", Pace.steady)
    private var tags by saved("dietTags", ArrayList<String>())
    var notes by saved("notes", ""); private set
    var metricHeight by saved("metricHeight", true); private set
    var metricWeight by saved("metricWeight", true); private set
    var kcalText by saved("kcal", "")
    var proteinText by saved("protein", "")
    var carbsText by saved("carbs", "")
    var fatText by saved("fat", "")
    /** The checked ChatGPT reply's explanation; null while the targets are the estimate. */
    var explanation by saved<String?>("explanation", null); private set
    private var prefilled by saved("prefilled", false)

    var asking by mutableStateOf(false); private set
    var askFailed by mutableStateOf(false); private set
    var saving by mutableStateOf(false); private set
    var saveError by mutableStateOf<String?>(null)
    var saved by mutableStateOf(false); private set
    var reaction by mutableStateOf<PipReaction?>(PipReaction(CompanionPose.Greeting)); private set
    private var ask: Job? = null

    val thisYear = Year.now().value
    val dietTags: List<String> get() = tags

    val heightCm: Double? get() = if (metricHeight) progressNumber(heightText)
        else progressNumber(feetText)?.let { (it * 12 + (progressNumber(inchesText) ?: 0.0)) * 2.54 }
    private fun kg(text: String) = progressNumber(text)?.let { if (metricWeight) it else it * KG_PER_LB }
    val weightKg get() = kg(weightText)
    val targetKg get() = kg(targetText)
    val birthYear get() = birthYearText.trim().toIntOrNull()

    val heightValid get() = heightCm?.let { it in 50.0..272.0 }
    val weightValid get() = weightKg?.let { it in 20.0..400.0 }
    val targetValid get() = targetKg?.let { it in 20.0..400.0 }
    val birthYearValid get() = birthYear?.let { it in 1900..thisYear - 13 }

    val answers: OnboardingAnswers? get() {
        val height = heightCm ?: return null
        val weight = weightKg ?: return null
        val target = targetKg ?: return null
        val year = birthYear ?: return null
        return OnboardingAnswers(ProfileAbout(height, year, sex, pace, dietTags, notes), weight, target)
    }

    val targets get() = NutritionValues(progressNumber(kcalText), progressNumber(carbsText), progressNumber(proteinText), progressNumber(fatText))

    val canContinue: Boolean get() = when (step) {
        Step.about -> heightValid == true && weightValid == true && birthYearValid == true
        Step.goal -> targetValid == true && answers?.targetIsHealthy == true
        Step.connect -> connection.value.let { !it.isConnecting && !it.isDisconnecting }
        Step.results -> !asking && !saving && targets.let { t -> listOf(t.kcal, t.protein, t.carbs, t.fat).all { (it ?: -1.0) >= 0 } }
        else -> true
    }

    init {
        if (!prefilled) prefill()
        // As iOS: a connection made on the Connect step goes straight on to the results.
        viewModelScope.launch {
            connection.map { it.canInfer }.distinctUntilChanged().collect { if (it && step == Step.connect) go(Step.results) }
        }
    }

    /** What is saved, so Settings' "Redo setup with Pip" starts from it; typed answers are never replaced. */
    private fun prefill() = viewModelScope.launch {
        val loaded = withContext(Dispatchers.IO) {
            runCatching {
                val db = repository.database(profileID)
                val (profile, weight) = db.read { tx -> tx.head.profile to tx.head.activeDayID?.let(tx::dayWeight) }
                val today = LocalDate.now(ZoneId.of(profile.timeZoneID, ZoneId.SHORT_IDS)).toString()
                Triple(profile.about, weight, db.goal(today)?.goalWeightKg)
            }.getOrNull()
        } ?: return@launch
        val (about, weight, target) = loaded
        if (about != null && heightText.isEmpty() && feetText.isEmpty() && birthYearText.isEmpty()) {
            heightText = fieldText(tenth(about.heightCm)); birthYearText = about.birthYear.toString()
            sex = about.sex; pace = about.pace; tags = ArrayList(about.dietTags); notes = about.healthNotes
        }
        if (weight != null && weightText.isEmpty()) weightText = fieldText(tenth(if (weight.unit == "lb") weight.value * KG_PER_LB else weight.value))
        if (target != null && targetText.isEmpty()) targetText = fieldText(tenth(target))
        prefilled = true
    }

    fun react(pose: CompanionPose) { reaction = PipReaction(pose) }

    fun toggleDiet(tag: String) { tags = ArrayList(if (tag in tags) tags - tag else tags + tag) }

    fun updateNotes(text: String) { notes = text.take(2_000) }

    /** Converts what is typed, so the stored metric value stays put. */
    fun useMetricHeight(metric: Boolean) {
        if (metric == metricHeight) return
        val cm = heightCm
        metricHeight = metric
        if (metric) heightText = cm?.let { fieldText(tenth(it)) }.orEmpty()
        else {
            val inches = cm?.let { Math.round(it / 2.54) }
            feetText = inches?.let { (it / 12).toString() }.orEmpty()
            inchesText = inches?.let { (it % 12).toString() }.orEmpty()
        }
    }

    fun useMetricWeight(metric: Boolean) {
        if (metric == metricWeight) return
        val weight = weightKg
        val target = targetKg
        metricWeight = metric
        fun shown(kg: Double?) = kg?.let { fieldText(tenth(if (metric) it else it / KG_PER_LB)) }.orEmpty()
        weightText = shown(weight); targetText = shown(target)
    }

    fun advance() {
        var next = Step.entries.getOrElse(step.ordinal + 1) { Step.results }
        if (next == Step.connect && connection.value.canInfer) next = Step.results
        go(next)
    }

    fun back() {
        var previous = Step.entries.getOrElse(step.ordinal - 1) { Step.hello }
        if (previous == Step.connect && connection.value.canInfer) previous = Step.diet
        go(previous)
    }

    fun go(next: Step) {
        val forward = next.ordinal > step.ordinal
        step = next
        when (next) {
            Step.about -> react(CompanionPose.Attentive)
            Step.goal -> react(CompanionPose.Saved)
            Step.results -> if (forward) showEstimate()
            else -> if (forward) react(CompanionPose.Saved)
        }
    }

    private fun show(values: NutritionValues) {
        kcalText = fieldText(values.kcal); proteinText = fieldText(values.protein)
        carbsText = fieldText(values.carbs); fatText = fieldText(values.fat)
    }

    private fun showEstimate() {
        val answers = answers ?: return
        // iOS sends a fresh request each time: a reply for earlier answers must not win.
        ask?.cancel(); asking = false
        show(answers.estimate(thisYear)); explanation = null; askFailed = false
        if (connection.value.canInfer) askChatGPT() else react(CompanionPose.Saved)
    }

    /** One request with the answers; a reply that passes the checks replaces the estimate, anything else keeps it. */
    fun askChatGPT() {
        val answers = answers ?: return
        if (ask?.isActive == true) return
        asking = true; askFailed = false
        react(CompanionPose.Thinking)
        ask = viewModelScope.launch {
            try {
                val respond = inference()
                val result = respond(OnboardingTargets.input(answers, answers.estimate(thisYear), thisYear), null)
                val parsed = OnboardingTargets.parse(result.text) ?: throw ResponsesClient.Failure.Malformed("setup targets")
                show(parsed.targets); explanation = parsed.explanation
                react(CompanionPose.Saved)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                askFailed = true
                react(CompanionPose.Recovery)
            } finally {
                if (isActive) asking = false // a cancelled request leaves `asking` to its replacement
            }
        }
    }

    /** iOS `save()`: the stored profile's answers, the weight when it changed, and today's exact goal. */
    fun save() {
        val answers = answers ?: return
        if (!canContinue) return
        val targets = targets
        saving = true; saveError = null
        viewModelScope.launch {
            try {
                withContext(Dispatchers.IO) {
                    val db = repository.database(profileID)
                    // The stored profile, not a cached one: Coach may have edited it, or a failed save already wrote `about`.
                    val latest = db.head().profile
                    db.updateProfile(latest.copy(about = answers.about), latest)
                    val savedKg = db.read { tx -> tx.head.activeDayID?.let(tx::dayWeight) }?.let { if (it.unit == "lb") it.value * KG_PER_LB else it.value }
                    if (savedKg?.let { abs(it - answers.weightKg) >= 0.05 } != false) db.recordWeight(tenth(answers.weightKg))
                    // The day Today shows, so targets saved between midnight and the cutoff appear at once.
                    val today = db.read { tx -> tx.head.activeDayID?.let(tx::day)?.localDate } ?: wakingDateLabel(Instant.now(), latest.timeZoneID)
                    val existing = db.goal(today, exact = true)
                    db.setGoals(GoalRecord(existing?.id ?: UUID.randomUUID(), today, latest.timeZoneID, existing?.revision ?: 0, targets,
                        tenth(answers.targetKg), existing?.exerciseCreditEnabled ?: false), existing?.revision)
                }
                saved = true
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                saveError = editorFailure(e, "Your answers are kept.")
            } finally {
                saving = false
            }
        }
    }
}

/** Full screen setup hosted by Pip. [onFinish] closes it: "Later", or after the targets are saved. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun OnboardingScreen(model: OnboardingViewModel, onAgree: () -> Unit, onConnect: () -> Unit, onFinish: () -> Unit) {
    val connection by model.connection.collectAsStateWithLifecycle()
    val step = model.step
    LaunchedEffect(model.saved) { if (model.saved) onFinish() }
    BackHandler(enabled = step != OnboardingViewModel.Step.hello) { model.back() }
    val pip = rememberSetupPip(model)
    DialogSystemBarIcons()
    val imeVisible = WindowInsets.isImeVisible
    Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
        Column(Modifier.fillMaxSize().safeDrawingPadding(), horizontalAlignment = Alignment.CenterHorizontally) {
            Box(Modifier.fillMaxWidth().heightIn(min = 56.dp).padding(horizontal = 4.dp)) {
                if (step == OnboardingViewModel.Step.hello) {
                    TextButton(onFinish, Modifier.align(Alignment.CenterEnd).heightIn(min = 48.dp).testTag("onboardingLater")) { Text("Later") }
                } else {
                    IconButton({ model.back() }, Modifier.align(Alignment.CenterStart).testTag("onboardingBack")) {
                        Icon(painterResource(R.drawable.ic_arrow_back), contentDescription = "Back")
                    }
                }
                if (step == OnboardingViewModel.Step.diet) {
                    TextButton({ model.advance() }, Modifier.align(Alignment.CenterEnd).heightIn(min = 48.dp)) { Text("Skip") }
                }
            }
            // As the mockup: hello has no progress yet, so the bar starts on the first question.
            if (step != OnboardingViewModel.Step.hello) LinearProgressIndicator(
                progress = { step.ordinal / (OnboardingViewModel.Step.entries.size - 1f) },
                modifier = Modifier.widthIn(max = 560.dp).fillMaxWidth().padding(horizontal = 16.dp).semantics {
                    contentDescription = "Setup progress"
                    stateDescription = "Step ${step.ordinal + 1} of ${OnboardingViewModel.Step.entries.size}"
                },
            )
            Column(
                Modifier.weight(1f).widthIn(max = 560.dp).fillMaxWidth().verticalScroll(rememberScrollState())
                    .padding(horizontal = 16.dp, vertical = 16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                Page(model, connection, pip, if (imeVisible) 64.dp else 96.dp)
            }
            Actions(model, connection, onAgree, onConnect)
        }
    }
}

@Composable
private fun Actions(model: OnboardingViewModel, connection: ConnectionState, onAgree: () -> Unit, onConnect: () -> Unit) {
    val step = model.step
    Column(Modifier.widthIn(max = 560.dp).fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        model.saveError?.let { Text(it, Modifier.semantics { liveRegion = LiveRegionMode.Polite }, color = MaterialTheme.colorScheme.error,
            style = MaterialTheme.typography.bodyMedium) }
        if (step == OnboardingViewModel.Step.connect) {
            ChatGPTConnectButton(connection, onAgree, onConnect)
            TextButton({ model.go(OnboardingViewModel.Step.results) }, Modifier.heightIn(min = 48.dp).testTag("onboardingSkipConnect")) {
                Text("Use the estimate instead")
            }
        } else {
            val busy = model.saving || (model.asking && step == OnboardingViewModel.Step.results)
            Button(
                onClick = { if (step == OnboardingViewModel.Step.results) model.save() else model.advance() },
                modifier = Modifier.fillMaxWidth().heightIn(min = 52.dp).testTag("onboardingNext"),
                enabled = model.canContinue,
            ) {
                if (busy) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp, color = MaterialTheme.colorScheme.onPrimary)
                else Text(when (step) {
                    OnboardingViewModel.Step.hello -> "Get started"
                    OnboardingViewModel.Step.results -> "Save my targets"
                    else -> "Continue"
                }, style = MaterialTheme.typography.titleMedium)
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Page(model: OnboardingViewModel, connection: ConnectionState, pip: SetupPip, pipSize: Dp) {
    val focus = LocalFocusManager.current
    when (model.step) {
        OnboardingViewModel.Step.hello -> {
            Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) { pip.Show(170.dp) }
            Header("Hi, I'm Pip", "Answer a few quick questions and I'll set daily targets that fit you. It takes about a minute.")
            Column(Modifier.padding(top = 8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Promise(R.drawable.ic_monitor_weight, "Your body and goal", "Height, weight and where you want to be.")
                Promise(R.drawable.ic_eco, "How you eat", "Diets, allergies or conditions Coach should know.")
                Promise(R.drawable.ic_auto_awesome, "Targets that fit", "ChatGPT tunes calories, protein, carbs and fat.")
            }
        }
        OnboardingViewModel.Step.about -> {
            Header("About you", "Used only to estimate your energy needs.") { pip.Show(pipSize) }
            val weight = remember { FocusRequester() }
            val inches = remember { FocusRequester() }
            val birthYear = remember { FocusRequester() }
            val height = remember { FocusRequester() }
            LaunchedEffect(Unit) { if (model.heightCm == null) runCatching { height.requestFocus() } }
            WhiteCard {
                Column {
                    LedgerRow("Height", model.heightValid == false) {
                        if (model.metricHeight) {
                            NumberField(model.heightText, { model.heightText = it }, "Height in centimetres", "onboardingHeight",
                                Modifier.focusRequester(height), onNext = { weight.requestFocus() })
                        } else {
                            NumberField(model.feetText, { model.feetText = it }, "Feet", "onboardingFeet", Modifier.focusRequester(height),
                                width = 48.dp, onNext = { inches.requestFocus() })
                            Text("ft", color = MaterialTheme.colorScheme.onSurfaceVariant)
                            NumberField(model.inchesText, { model.inchesText = it }, "Inches", "onboardingInches", Modifier.focusRequester(inches),
                                width = 48.dp, onNext = { weight.requestFocus() })
                        }
                        UnitMenu(model.metricHeight, "cm", "in", "ft, in", model::useMetricHeight)
                    }
                    HorizontalDivider(Modifier.padding(start = 16.dp))
                    LedgerRow("Weight", model.weightValid == false) {
                        NumberField(model.weightText, { model.weightText = it }, "Weight", "onboardingWeight", Modifier.focusRequester(weight),
                            onNext = { birthYear.requestFocus() })
                        UnitMenu(model.metricWeight, "kg", "lb", "lb", model::useMetricWeight)
                    }
                    HorizontalDivider(Modifier.padding(start = 16.dp))
                    LedgerRow("Birth year", model.birthYearValid == false) {
                        NumberField(model.birthYearText, { text -> model.birthYearText = text.filter(Char::isDigit).take(4) }, "Birth year",
                            "onboardingBirthYear", Modifier.focusRequester(birthYear), keyboardType = KeyboardType.Number, onNext = null)
                    }
                    HorizontalDivider(Modifier.padding(start = 16.dp))
                    LedgerRow("Sex", false) { SexMenu(model.sex) { model.sex = it } }
                }
            }
            Footnote("Sex is optional. Skipping it uses the midpoint of both formulas.")
        }
        OnboardingViewModel.Step.goal -> {
            Header("Your goal", "Enter your current weight to keep it.") { pip.Show(pipSize) }
            val target = remember { FocusRequester() }
            LaunchedEffect(Unit) { if (model.targetKg == null) runCatching { target.requestFocus() } }
            WhiteCard {
                LedgerRow("Target weight", model.targetValid == false) {
                    NumberField(model.targetText, { model.targetText = it }, "Target weight", "onboardingTarget", Modifier.focusRequester(target), onNext = null)
                    UnitMenu(model.metricWeight, "kg", "lb", "lb", model::useMetricWeight)
                }
            }
            val answers = model.answers
            when {
                answers == null || model.targetValid != true -> Unit
                !answers.targetIsHealthy -> Footnote("That target is below a healthy weight for your height, so Mivu can't set it. Choose a " +
                    "higher target, or talk to a doctor or registered dietitian.")
                !answers.keepsWeight -> {
                    Text(if (answers.targetKg < answers.weightKg) "How quickly would you like to lose it?" else "How quickly would you like to gain it?",
                        Modifier.padding(top = 4.dp).semantics { heading() }, style = MaterialTheme.typography.titleMedium)
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Pace.entries.forEach { PaceRow(it, model.pace == it, model.metricWeight) { model.pace = it } }
                    }
                }
                else -> Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(painterResource(R.drawable.ic_check_circle), contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text("We'll aim to keep your weight steady.", color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
        OnboardingViewModel.Step.diet -> {
            Header("How do you eat?", "Pick anything that applies. Coach keeps it in mind for every suggestion.") { pip.Show(pipSize) }
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                DietChoices.forEach { tag ->
                    val chosen = tag in model.dietTags
                    FilterChip(chosen, { model.toggleDiet(tag) }, label = { Text(tag) },
                        leadingIcon = if (chosen) { { Icon(painterResource(R.drawable.ic_check), contentDescription = null, Modifier.size(18.dp)) } } else null)
                }
            }
            OutlinedTextField(model.notes, model::updateNotes, Modifier.fillMaxWidth(), label = { Text("Other allergies, intolerances or dislikes") },
                minLines = 2, maxLines = 5, keyboardActions = KeyboardActions(onDone = { focus.clearFocus() }))
        }
        OnboardingViewModel.Step.connect -> {
            Header("Let ChatGPT tune it", "Connect your ChatGPT account to turn your answers into personal targets.") { pip.Show(pipSize) }
            WhiteCard {
                Column(Modifier.padding(horizontal = 16.dp, vertical = 4.dp)) {
                    Promise(R.drawable.ic_shield, "Private by default", "Only these answers are sent, once. Your diary stays on this phone.")
                    HorizontalDivider()
                    Promise(R.drawable.ic_person, "Your own plan", "Recommended. Works with ChatGPT Plus or Pro and uses its allowance. No extra cost.")
                }
            }
            if (connection.isConnecting) Row(Modifier.fillMaxWidth().heightIn(min = 48.dp), horizontalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterHorizontally),
                verticalAlignment = Alignment.CenterVertically) {
                CircularProgressIndicator(Modifier.size(24.dp), strokeWidth = 3.dp)
                Text("Waiting for ChatGPT…")
            }
            connection.notice?.let { Footnote(it.text) }
        }
        OnboardingViewModel.Step.results -> {
            Header("Your daily targets", null) { pip.Show(pipSize) }
            Results(model)
        }
    }
}

@Composable
private fun Results(model: OnboardingViewModel) {
    WhiteCard {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Box(Modifier.semantics { liveRegion = LiveRegionMode.Polite }) {
                if (model.asking) Row(Modifier.heightIn(min = 32.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                    Text("ChatGPT is tuning your targets…", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                } else {
                    val tuned = model.explanation != null
                    Surface(shape = CircleShape, color = MaterialTheme.colorScheme.primary.copy(alpha = 0.12f)) {
                        Row(Modifier.padding(horizontal = 10.dp, vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(4.dp),
                            verticalAlignment = Alignment.CenterVertically) {
                            Icon(painterResource(if (tuned) R.drawable.ic_auto_awesome else R.drawable.ic_numbers), contentDescription = null,
                                Modifier.size(16.dp), tint = MaterialTheme.colorScheme.primary)
                            Text(if (tuned) "Tuned by ChatGPT" else "Estimate", style = MaterialTheme.typography.labelLarge,
                                color = MaterialTheme.colorScheme.primary)
                        }
                    }
                }
            }
            Column {
                Text("Calories", style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    NumberField(model.kcalText, { model.kcalText = it }, "Calories per day", "onboardingKcal", width = 150.dp,
                        style = MaterialTheme.typography.displaySmall.copy(fontWeight = FontWeight.SemiBold), align = TextAlign.Start,
                        keyboardType = KeyboardType.Number, enabled = !model.asking, onNext = null)
                    Text("kcal a day", style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            HorizontalDivider()
            Macro("Protein", MivuTheme.colors.protein, model.proteinText, "onboardingProtein", !model.asking) { model.proteinText = it }
            Macro("Carbs", MivuTheme.colors.carbs, model.carbsText, "onboardingCarbs", !model.asking) { model.carbsText = it }
            Macro("Fat", MivuTheme.colors.fat, model.fatText, "onboardingFat", !model.asking) { model.fatText = it }
        }
    }
    model.explanation?.let {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Icon(painterResource(R.drawable.ic_auto_awesome), contentDescription = null, Modifier.size(20.dp), tint = MaterialTheme.colorScheme.primary)
            Text(it, style = MaterialTheme.typography.bodyLarge)
        }
    }
    if (model.askFailed) Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Footnote("ChatGPT couldn't answer just now. You can keep the estimate or try again.")
        OutlinedButton({ model.askChatGPT() }, Modifier.heightIn(min = 48.dp)) {
            Icon(painterResource(R.drawable.ic_refresh), contentDescription = null, Modifier.size(18.dp))
            Text("Try again", Modifier.padding(start = 8.dp))
        }
    }
    Footnote("These are estimates, not medical advice. Check with a doctor or registered dietitian before big changes to how you eat, " +
        "especially if you have a health condition. You can change targets any time in Settings › Goals.")
}

@Composable
private fun Macro(name: String, color: Color, value: String, tag: String, enabled: Boolean, onChange: (String) -> Unit) {
    Row(Modifier.fillMaxWidth().heightIn(min = 48.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Box(Modifier.size(8.dp).background(color, CircleShape))
        Text(name, Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
        NumberField(value, onChange, "$name grams", tag, keyboardType = KeyboardType.Number, enabled = enabled, onNext = null,
            style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.SemiBold))
        Text("g", color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun Header(title: String, detail: String?, pip: (@Composable () -> Unit)? = null) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(title, Modifier.semantics { heading() }, style = MaterialTheme.typography.headlineLarge, fontWeight = FontWeight.Bold)
            detail?.let { Text(it, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant) }
        }
        pip?.invoke()
    }
}

@Composable
private fun Promise(icon: Int, title: String, detail: String) {
    Row(Modifier.fillMaxWidth().padding(vertical = 12.dp).semantics(mergeDescendants = true) {}, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        Box(Modifier.size(40.dp).background(MaterialTheme.colorScheme.primaryContainer, RoundedCornerShape(12.dp)), contentAlignment = Alignment.Center) {
            Icon(painterResource(icon), contentDescription = null, Modifier.size(22.dp), tint = MaterialTheme.colorScheme.onPrimaryContainer)
        }
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.titleMedium)
            Text(detail, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun Footnote(text: String) {
    Text(text, Modifier.fillMaxWidth(), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
}

/** A ledger row: label left, value and unit right, with a hint under the label when the value is out of range. */
@Composable
private fun LedgerRow(label: String, invalid: Boolean, value: @Composable RowScope.() -> Unit) {
    Row(Modifier.fillMaxWidth().heightIn(min = 56.dp).padding(start = 16.dp, end = 4.dp), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Column(Modifier.weight(1f)) {
            Text(label, style = MaterialTheme.typography.bodyLarge)
            if (invalid) Text("Check this value", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
        }
        value()
    }
}

@Composable
private fun NumberField(
    value: String,
    onChange: (String) -> Unit,
    label: String,
    tag: String,
    modifier: Modifier = Modifier,
    width: Dp = 96.dp,
    style: TextStyle = MaterialTheme.typography.titleLarge,
    align: TextAlign = TextAlign.End,
    keyboardType: KeyboardType = KeyboardType.Decimal,
    enabled: Boolean = true,
    /** The field Next moves to; null ends with Done. */
    onNext: (() -> Unit)?,
) {
    val focus = LocalFocusManager.current
    val color = MaterialTheme.colorScheme.onSurface
    BasicTextField(
        value, { text -> onChange(text.filter { it.isDigit() || it == '.' || it == ',' }.take(7)) },
        modifier.widthIn(min = 48.dp, max = width).heightIn(min = 48.dp).testTag(tag).semantics { contentDescription = label },
        enabled = enabled,
        singleLine = true,
        textStyle = style.copy(color = color, textAlign = align, fontFeatureSettings = "tnum"),
        keyboardOptions = KeyboardOptions(keyboardType = keyboardType, imeAction = if (onNext != null) ImeAction.Next else ImeAction.Done),
        keyboardActions = KeyboardActions(onNext = { onNext?.invoke() }, onDone = { focus.clearFocus() }),
        cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
        decorationBox = { inner ->
            Box(contentAlignment = if (align == TextAlign.End) Alignment.CenterEnd else Alignment.CenterStart) {
                if (value.isEmpty()) Text("Add", style = style.copy(textAlign = align), color = MaterialTheme.colorScheme.onSurfaceVariant)
                inner()
            }
        },
    )
}

@Composable
private fun UnitMenu(metric: Boolean, metricUnit: String, imperialUnit: String, imperialChoice: String, onMetric: (Boolean) -> Unit) {
    var open by remember { mutableStateOf(false) }
    val shown = if (metric) metricUnit else imperialUnit
    Box {
        TextButton({ open = true }, Modifier.heightIn(min = 48.dp).semantics { contentDescription = "Unit, $shown" }) {
            Text(shown)
            Icon(painterResource(R.drawable.ic_arrow_drop_down), contentDescription = null, Modifier.size(20.dp))
        }
        DropdownMenu(open, { open = false }) {
            DropdownMenuItem({ Text(metricUnit) }, { open = false; onMetric(true) })
            DropdownMenuItem({ Text(imperialChoice) }, { open = false; onMetric(false) })
        }
    }
}

@Composable
private fun SexMenu(sex: Sex, onSelect: (Sex) -> Unit) {
    var open by remember { mutableStateOf(false) }
    fun name(s: Sex) = when (s) { Sex.female -> "Female"; Sex.male -> "Male"; Sex.unspecified -> "Prefer not to say" }
    Box {
        TextButton({ open = true }, Modifier.heightIn(min = 48.dp).semantics { contentDescription = "Sex, ${name(sex)}" }) {
            Text(name(sex))
            Icon(painterResource(R.drawable.ic_arrow_drop_down), contentDescription = null, Modifier.size(20.dp))
        }
        DropdownMenu(open, { open = false }) {
            listOf(Sex.female, Sex.male, Sex.unspecified).forEach { DropdownMenuItem({ Text(name(it)) }, { open = false; onSelect(it) }) }
        }
    }
}

@Composable
private fun PaceRow(pace: Pace, chosen: Boolean, metric: Boolean, onSelect: () -> Unit) {
    val name = when (pace) { Pace.gentle -> "Gentle"; Pace.steady -> "Steady"; Pace.faster -> "Faster" }
    val amount = if (metric) "${pace.kgPerWeek} kg a week" else "${"%.1f".format(pace.kgPerWeek / KG_PER_LB)} lb a week"
    val note = when (pace) { Pace.gentle -> "Easiest to keep up"; Pace.steady -> "Right for most people"; Pace.faster -> "Takes more discipline" }
    val accent = MaterialTheme.colorScheme.primary
    Surface(
        Modifier.fillMaxWidth().selectable(chosen, role = Role.RadioButton, onClick = onSelect),
        shape = RoundedCornerShape(16.dp),
        color = if (chosen) accent.copy(alpha = 0.10f) else MaterialTheme.colorScheme.surface,
        border = BorderStroke(if (chosen) 2.dp else 1.dp, if (chosen) accent else MaterialTheme.colorScheme.outlineVariant),
    ) {
        Row(Modifier.heightIn(min = 56.dp).padding(horizontal = 8.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            RadioButton(chosen, onClick = null, Modifier.padding(8.dp))
            Column {
                Text("$name · $amount", fontWeight = if (chosen) FontWeight.SemiBold else null)
                Text(note, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

/** Setup's one Pip: the rig once it loads (the still image until then), showing the model's latest reaction. */
private class SetupPip(val output: CompanionOutput?, val runtime: CompanionRuntime?, val onTouch: () -> Unit) {
    @Composable
    fun Show(size: Dp) {
        Box(Modifier.size(size * (399.8f / 455.5f), size), contentAlignment = Alignment.Center) {
            if (runtime != null && output != null) PipCompanion(output, CompanionSurface.Today, size, runtime, { onTouch() })
            else Image(painterResource(R.drawable.pip_preview), contentDescription = null, Modifier.size(size))
        }
    }
}

@Composable
private fun rememberSetupPip(model: OnboardingViewModel): SetupPip {
    val context = LocalContext.current
    val assets = produceState<Pair<PipRigScene, PipGestureLibrary>?>(null) {
        value = runCatching { PipAssets.load(context) }.getOrNull() // a missing rig keeps the still image
    }.value
    val scope = rememberCoroutineScope()
    val runtime = assets?.let { (scene, library) ->
        remember(scene) { CompanionRuntime(library, scene, scope, { System.nanoTime() / 1_000_000 }, Random.Default) }
    }
    val playback = rememberMotionPlayback()
    val reaction = model.reaction
    val output = if (playback == Playback.Hidden) null else CompanionOutput(reaction?.pose ?: CompanionPose.Resting, playback, reaction?.id)
    return SetupPip(output, runtime) { model.react(CompanionPose.Tapped) }
}
