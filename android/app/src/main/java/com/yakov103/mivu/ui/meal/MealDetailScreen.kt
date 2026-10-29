package com.yakov103.mivu.ui.meal

import android.text.format.DateFormat
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.MenuDefaults
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.yakov103.mivu.R
import com.yakov103.mivu.analysis.OnDeviceInference
import com.yakov103.mivu.diary.DiaryMeal
import com.yakov103.mivu.diary.FoodItem
import com.yakov103.mivu.diary.MealPhoto
import com.yakov103.mivu.diary.MealSubmission
import com.yakov103.mivu.diary.MealTimePrecision
import com.yakov103.mivu.diary.NutritionProvenance
import com.yakov103.mivu.diary.PhotoRole
import com.yakov103.mivu.diary.SubmissionState
import com.yakov103.mivu.diary.TrackingDay
import com.yakov103.mivu.diary.hasUnresolvedInput
import com.yakov103.mivu.diary.nutritionTotals
import com.yakov103.mivu.ui.diary.NutritionSummary
import com.yakov103.mivu.ui.diary.fixed
import com.yakov103.mivu.ui.theme.MivuTheme
import com.yakov103.mivu.ui.today.WhiteCard
import com.yakov103.mivu.ui.today.color
import com.yakov103.mivu.ui.today.mealTitle
import com.yakov103.mivu.ui.coach.AskPip
import com.yakov103.mivu.ui.today.state
import com.yakov103.mivu.ui.today.tabular
import com.yakov103.mivu.ui.today.title
import java.text.NumberFormat
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import java.util.UUID
import kotlinx.coroutines.launch

private val Gutter = 16.dp
private val HeroHeight = 240.dp
private val CardOverlap = 32.dp

private sealed interface Deletion {
    data class Meal(val revision: Int, val title: String, val date: String) : Deletion
    data class Food(val item: FoodItem, val revision: Int) : Deletion
    data class Photo(val id: UUID) : Deletion
}

private fun FoodItem.displayName() = if (provenance == NutritionProvenance.sample) "Apple (sample)" else name
private fun Double.amount(): String = NumberFormat.getNumberInstance().format(this)
private fun FoodItem.portion() = "${quantity.amount()} $unit"
private fun FoodItem.kcalText() = nutrition.kcal?.let { "${it.fixed(0)} kcal" } ?: "— kcal"

/** iOS `FoodItem.sourceCaption`: the provenance, and the model that estimated it unless the person edited it. */
internal val FoodItem.sourceCaption: String
    get() = listOfNotNull(
        when (provenance) {
            NutritionProvenance.sample -> "Synthetic apple estimate"
            NutritionProvenance.user -> "Edited by you"
            NutritionProvenance.confirmedLabel -> "Confirmed label values"
            NutritionProvenance.identifiedSource -> "Retrieved nutrition source"
            NutritionProvenance.estimate -> "Estimated nutrition"
        },
        estimatedBy?.takeIf { provenance != NutritionProvenance.user }?.let {
            when (it) {
                OnDeviceInference.MODEL -> "Gemini Nano"
                "apple-intelligence" -> "Apple Intelligence" // restored iOS archives
                else -> "ChatGPT"
            }
        },
    ).joinToString(" · ")

private val DiaryMeal.pendingReview: MealSubmission?
    get() = submissions.lastOrNull { it.state == SubmissionState.awaitingReview && it.proposal != null }

/**
 * Port of iOS MealDetailView in direction B: an edge-to-edge photo hero, the meal summary, a pending review, attached
 * photos and the foods, with Ask Pip pinned at the bottom. Foods open the editor; the summary adjusts the total and the
 * menu moves the meal. "Add note or photo" waits for a composer that can correct a meal.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MealDetailScreen(
    viewModel: MealDetailViewModel,
    onBack: () -> Unit,
    onAskPip: (AskPip) -> Unit,
    onAddFoodManually: () -> Unit,
    onRetryAnalysis: () -> Unit = {},
    /** An accepted review's submission, once it is saved. */
    onReviewed: (UUID) -> Unit = {},
) {
    val state = viewModel.state.collectAsStateWithLifecycle().value
    val deleted by viewModel.deleted.collectAsStateWithLifecycle()
    LaunchedEffect(deleted) { if (deleted) onBack() }
    val snackbar = remember { SnackbarHostState() }
    LaunchedEffect(viewModel) { viewModel.messages.collect { snackbar.showSnackbar(it, withDismissAction = true) } }
    var deletion by remember { mutableStateOf<Deletion?>(null) }
    var viewing by rememberSaveable { mutableStateOf<String?>(null) }
    // The revision (and for a move, the day) each sheet opened with; null while it is closed.
    var scaleRevision by rememberSaveable { mutableStateOf<Int?>(null) }
    var moveFrom by rememberSaveable { mutableStateOf<List<String>?>(null) }
    val movedDayID by viewModel.movedDayID.collectAsStateWithLifecycle()
    val editing = viewModel.editing
    val busy = viewModel.busy

    val meal = state?.meal?.takeUnless { deleted }
    val hero = meal?.photos?.firstOrNull()
    val list = rememberLazyListState()
    val density = LocalDensity.current
    val statusBar = WindowInsets.statusBars.asPaddingValues().calculateTopPadding()
    // Over the hero the bar is clear with floating buttons; once the hero scrolls away it becomes a plain bar.
    val collapsed by remember(hero) {
        derivedStateOf {
            hero == null || list.firstVisibleItemIndex > 0 ||
                list.firstVisibleItemScrollOffset > with(density) { (HeroHeight - 64.dp).roundToPx() }
        }
    }
    StatusIconsOverPhoto(!collapsed)
    val barColor by animateColorAsState(if (collapsed) MaterialTheme.colorScheme.background else Color.Transparent, label = "bar")

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        // While the editor or a sheet is open its own window shows the snackbar.
        snackbarHost = { if (editing == null && scaleRevision == null && moveFrom == null) SnackbarHost(snackbar) },
        topBar = {
            TopAppBar(
                title = { if (collapsed) Text("Meal", Modifier.semantics { heading() }) },
                navigationIcon = { FloatingIcon(R.drawable.ic_arrow_back, "Back", "mealBack", collapsed, onBack) },
                actions = {
                    if (meal != null) MealActions(meal, collapsed, busy,
                        onMove = { moveFrom = listOf(meal.revision.toString(), meal.dayID.toString()) }, onRetry = onRetryAnalysis) {
                        deletion = Deletion.Meal(meal.revision, mealTitle(meal), state.day?.localDate.orEmpty())
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = barColor, scrolledContainerColor = barColor),
            )
        },
        bottomBar = {
            if (meal != null) BottomActions(meal, state.day?.takeIf { it.id == movedDayID }?.localDate, busy, { onAskPip(AskPip.Meal(meal.id, mealTitle(meal))) }) {
                viewModel.acceptReview(it.id, meal.revision) { onReviewed(it.id) }
            }
        },
    ) { padding -> Box {
        val bottom = padding.calculateBottomPadding()
        when {
            state == null -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
            state.failed -> Message("Could not load this meal", "Your diary is preserved.", Modifier.padding(padding)) {
                FilledTonalButton(viewModel::retry, Modifier.heightIn(min = 48.dp)) { Text("Try again") }
            }
            meal == null -> if (!deleted) Message("Meal unavailable", "It may have been deleted or belong to another profile.",
                Modifier.padding(padding))
            else -> LazyColumn(
                Modifier.fillMaxSize(),
                state = list,
                contentPadding = PaddingValues(top = if (hero != null) 0.dp else padding.calculateTopPadding(), bottom = bottom + 16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                item(key = "summary") {
                    val summary = @Composable { m: Modifier -> Summary(meal, state.day, viewModel.sampleMode, busy, { scaleRevision = meal.revision }, m) }
                    if (hero != null) Box {
                        Hero(hero, HeroHeight + statusBar, viewModel::photoBytes) { viewing = hero.id.toString() }
                        summary(Modifier.padding(start = Gutter, end = Gutter, top = HeroHeight + statusBar - CardOverlap))
                    } else summary(Modifier.padding(horizontal = Gutter, vertical = 4.dp))
                }
                meal.pendingReview?.let { review ->
                    item(key = "review") { ReviewSection(review.proposal!!.items, { viewModel.edit(it, meal.revision, review.id) }, Modifier.padding(horizontal = Gutter)) }
                }
                if (meal.photos.size > 1) {
                    item(key = "photosHeader") { SectionHeader("Attached photos") }
                    items(meal.photos, key = { it.id }) { photo ->
                        AttachedPhoto(photo, busy, viewModel::photoBytes, { viewing = photo.id.toString() }, { deletion = Deletion.Photo(photo.id) })
                    }
                }
                item(key = "foodsHeader") { SectionHeader("Foods") }
                item(key = "foods") {
                    FoodsCard(meal, busy, onEdit = { viewModel.edit(it, meal.revision, null) }, onAskPip = { onAskPip(askFood(meal, it, state.day)) }, onDelete = { deletion = Deletion.Food(it, meal.revision) })
                }
                if (meal.revision > 0 && !meal.hasUnresolvedInput) item(key = "add") {
                    FilledTonalButton(onAddFoodManually, Modifier.padding(horizontal = Gutter).heightIn(min = 48.dp).testTag("addFoodManually")) {
                        Icon(painterResource(R.drawable.ic_add), contentDescription = null, Modifier.size(18.dp))
                        Spacer(Modifier.size(8.dp))
                        Text("Add food manually")
                    }
                }
            }
        }
        // Keeps the light status-bar icons readable on a bright photo while it is under them.
        if (!collapsed) Box(Modifier.fillMaxWidth().height(statusBar + 56.dp)
            .background(Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.35f), Color.Transparent))))
    } }

    meal?.photos?.firstOrNull { it.id.toString() == viewing }?.let { photo ->
        MealPhotoViewer(photo, busy, viewModel::photoBytes, onDelete = { viewModel.deletePhoto(photo.id) { viewing = null } }, onClose = { viewing = null })
    }
    if (meal != null && editing != null) {
        val saved = editing.submissionID == null && meal.state == SubmissionState.saved
        val several = meal.items.size > 1
        FoodItemEditor(
            editing, viewModel.busy, snackbar, canDeleteFood = saved && several, canDeleteMeal = saved && !several,
            onChange = viewModel::updateEdit, onClose = { viewModel.updateEdit(null) }, onSave = viewModel::saveEdit,
            onAskPip = { viewModel.updateEdit(null); onAskPip(askFood(meal, editing.item, state.day)) },
            onDelete = {
                viewModel.updateEdit(null)
                if (several) viewModel.deleteItem(editing.item.id, editing.revision) else viewModel.deleteMeal(editing.revision)
            },
        )
    }
    // Each sheet stays open, with what was typed or picked, until its write succeeds; a stale meal moves it to the reload.
    if (meal != null) scaleRevision?.let { revision ->
        ScaleMealSheet(nutritionTotals(meal.items).kcal ?: 0.0, busy, snackbar, onDismiss = { scaleRevision = null }) {
            viewModel.scaleMeal(it, revision, onStale = { scaleRevision = it }) { scaleRevision = null }
        }
    }
    if (meal != null) moveFrom?.let { (revision, dayID) ->
        val from = UUID.fromString(dayID)
        MoveMealSheet(from, busy, snackbar, { viewModel.destinations(it, from) }, onDismiss = { moveFrom = null }) {
            viewModel.moveMeal(it, revision.toInt(), from, onStale = { r, d -> moveFrom = listOf(r.toString(), d.toString()) }) { moveFrom = null }
        }
    }
    when (val target = deletion) {
        is Deletion.Meal -> ConfirmDelete("Delete “${target.title}” on ${target.date}?", "This removes the meal and its attached photos from this diary.",
            "Delete meal", "confirmDeleteMeal", { deletion = null; viewModel.deleteMeal(target.revision) }, { deletion = null })
        is Deletion.Food -> ConfirmDelete("Delete ${target.item.name}?", "Only this food is removed. The meal keeps its other foods.",
            "Delete food", "confirmDeleteFood", { deletion = null; viewModel.deleteItem(target.item.id, target.revision) }, { deletion = null })
        is Deletion.Photo -> ConfirmDelete("Delete this photo?", "Only this photo will be removed. The meal and its notes are kept.",
            "Delete photo", "confirmDeletePhoto", { deletion = null; viewModel.deletePhoto(target.id) }, { deletion = null })
        null -> Unit
    }
}

/** A top-bar icon: a tonal circle over the photo, a plain icon once the bar is solid. */
@Composable
private fun FloatingIcon(icon: Int, label: String, tag: String, plain: Boolean, onClick: () -> Unit) {
    val container by animateColorAsState(if (plain) Color.Transparent else MaterialTheme.colorScheme.surface.copy(alpha = 0.9f), label = "icon")
    FilledIconButton(onClick, Modifier.padding(horizontal = 4.dp).size(48.dp).testTag(tag),
        colors = IconButtonDefaults.filledIconButtonColors(containerColor = container, contentColor = MaterialTheme.colorScheme.onSurface)) {
        Icon(painterResource(icon), contentDescription = label)
    }
}

/** iOS "Meal actions": Move to another day, Retry analysis (failed or captured) and Delete meal. */
@Composable
private fun MealActions(meal: DiaryMeal, plain: Boolean, busy: Boolean, onMove: () -> Unit, onRetry: () -> Unit, onDelete: () -> Unit) {
    var open by rememberSaveable { mutableStateOf(false) }
    Box {
        FloatingIcon(R.drawable.ic_more_vert, "Meal actions", "mealActions", plain) { open = true }
        DropdownMenu(open, onDismissRequest = { open = false }, shape = RoundedCornerShape(16.dp)) {
            DropdownMenuItem(
                text = { Text("Move to another day") },
                onClick = { open = false; onMove() },
                enabled = !busy,
                leadingIcon = { Icon(painterResource(R.drawable.ic_event), contentDescription = null) },
                modifier = Modifier.testTag("moveMeal"),
            )
            if (meal.state == SubmissionState.needsRetry || meal.state == SubmissionState.captured) DropdownMenuItem(
                text = { Text("Retry analysis") },
                onClick = { open = false; onRetry() },
                leadingIcon = { Icon(painterResource(R.drawable.ic_refresh), contentDescription = null) },
                modifier = Modifier.testTag("retryAnalysis"),
            )
            HorizontalDivider()
            val error = MaterialTheme.colorScheme.error
            DropdownMenuItem(
                text = { Text("Delete meal") },
                onClick = { open = false; onDelete() },
                enabled = !busy,
                leadingIcon = { Icon(painterResource(R.drawable.ic_delete), contentDescription = null) },
                colors = MenuDefaults.itemColors(textColor = error, leadingIconColor = error),
                modifier = Modifier.testTag("deleteMeal"),
            )
        }
    }
}

@Composable
private fun Hero(photo: MealPhoto, height: Dp, load: suspend (UUID) -> ByteArray?, onOpen: () -> Unit) {
    val (image) = rememberPhoto(photo, load)
    val modifier = Modifier.fillMaxWidth().height(height).background(MivuTheme.colors.summarySurface)
        .testTag("viewMealPhoto")
        .clickable(onClickLabel = "Open full-screen photo viewer", role = Role.Button, onClick = onOpen)
        .semantics { this.contentDescription = "Meal photo" }
    if (image != null) Image(image, contentDescription = null, modifier, contentScale = ContentScale.Crop) else Box(modifier)
}

@Composable
private fun Summary(meal: DiaryMeal, day: TrackingDay?, sampleMode: Boolean, busy: Boolean, onAdjust: () -> Unit, modifier: Modifier) {
    val context = LocalContext.current
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
    val zone = day?.let { runCatching { ZoneId.of(it.timeZoneID) }.getOrNull() } ?: ZoneId.systemDefault()
    WhiteCard(modifier) {
        Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(mealTitle(meal), Modifier.semantics { heading() }, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
            if (meal.timePrecision == MealTimePrecision.dateOnly) {
                Text(day?.localDate?.let { LocalDate.parse(it).format(pattern("EEEdMMMy")) } ?: "Historical meal",
                    style = MaterialTheme.typography.bodyMedium, color = secondary)
                Text("Time unspecified", style = MaterialTheme.typography.bodyMedium, color = secondary)
            } else {
                val skeleton = if (DateFormat.is24HourFormat(context)) "dMMMHHmm" else "dMMMhmm"
                Text(meal.eatenAt.atZone(zone).format(pattern(skeleton)), style = MaterialTheme.typography.bodyMedium, color = secondary)
            }
            Row(Modifier.padding(top = 4.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Icon(painterResource(R.drawable.ic_check_circle), contentDescription = null, Modifier.size(20.dp), tint = MivuTheme.colors.success)
                Text("Saved on this phone", style = MaterialTheme.typography.bodyMedium, color = MivuTheme.colors.success)
            }
            val state = meal.state
            if (state != SubmissionState.saved) Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Box(Modifier.padding(horizontal = 6.dp).size(8.dp).background(state.color, CircleShape))
                Text(state.title, style = MaterialTheme.typography.bodyMedium, color = state.color)
            }
            if (sampleMode) Text("Apple sample estimate — not food recognition", style = MaterialTheme.typography.bodySmall, color = secondary)
            Spacer(Modifier.height(10.dp))
            val totals = nutritionTotals(meal.items)
            if (meal.revision > 0) {
                val adjust = @Composable {
                    OutlinedButton(onAdjust, Modifier.heightIn(min = 48.dp).testTag("adjustMealTotal")
                        .semantics { onClick(label = "Resizes every food in this meal to reach a calorie total") { onAdjust(); true } },
                        enabled = !busy) { Text("Adjust total") }
                }
                NutritionSummary(totals.kcal, totals.protein, totals.carbs, totals.fat, totals.unknownItemCount > 0, title = null,
                    trailing = adjust.takeIf { state == SubmissionState.saved && (totals.kcal ?: 0.0) > 0 })
            } else if (state != SubmissionState.awaitingReview) {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("Nutrition", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                    Text("— kcal", style = MaterialTheme.typography.headlineLarge.tabular(), fontWeight = FontWeight.SemiBold)
                    Text("Not estimated yet", style = MaterialTheme.typography.bodyMedium, color = secondary)
                    Text(when (state) {
                        SubmissionState.cancelled -> "Analysis was cancelled. Your note and photos are kept."
                        SubmissionState.needsRetry -> "Your meal is saved. Retry analysis when you’re ready."
                        SubmissionState.waitingForConnection -> "Connect ChatGPT to analyze this saved meal."
                        else -> "Your meal is saved. Analysis will resume when available."
                    }, style = MaterialTheme.typography.bodyMedium, color = secondary)
                }
            }
        }
    }
}

private fun pattern(skeleton: String) = DateTimeFormatter.ofPattern(DateFormat.getBestDateTimePattern(Locale.getDefault(), skeleton))

@Composable
private fun SectionHeader(text: String) {
    Text(text, Modifier.padding(start = Gutter, end = Gutter, top = 12.dp).semantics { heading() },
        style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
}

/** iOS "Review estimate": the proposal's totals and foods; it counts only once marked reviewed (bottom bar). */
@Composable
private fun ReviewSection(items: List<FoodItem>, onEdit: (FoodItem) -> Unit, modifier: Modifier) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("Review estimate", Modifier.padding(top = 12.dp).semantics { heading() }, style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.Bold)
        Surface(Modifier.fillMaxWidth(), shape = RoundedCornerShape(24.dp), color = MivuTheme.colors.summarySurface) {
            Column(Modifier.padding(vertical = 16.dp)) {
                Text("Check the portions before marking this reviewed. This proposal does not count in totals until you save it.",
                    Modifier.padding(horizontal = 20.dp), style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                val totals = nutritionTotals(items)
                Box(Modifier.padding(horizontal = 20.dp, vertical = 16.dp)) {
                    NutritionSummary(totals.kcal, totals.protein, totals.carbs, totals.fat, totals.unknownItemCount > 0, title = "Estimated totals")
                }
                items.forEach { item ->
                    HorizontalDivider(Modifier.padding(horizontal = 20.dp), color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.6f))
                    Column(
                        Modifier.fillMaxWidth().heightIn(min = 56.dp)
                            .clickable(onClickLabel = "Edit ingredient amount and nutrition") { onEdit(item) }
                            .testTag("editItem").padding(horizontal = 20.dp, vertical = 12.dp),
                        verticalArrangement = Arrangement.spacedBy(2.dp),
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(item.displayName(), Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium)
                            Text(item.portion(), style = MaterialTheme.typography.bodyMedium.tabular(), color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        Text(item.sourceCaption, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        if (item.uncertain) Text("Portion or nutrients are uncertain", style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    if (item.reference.isNotEmpty()) SourceDetails(item.reference, Modifier.padding(horizontal = 12.dp))
                }
            }
        }
    }
}

/** iOS "Source details": the food's reference behind a disclosure. */
@Composable
private fun SourceDetails(reference: String, modifier: Modifier) {
    var open by rememberSaveable { mutableStateOf(false) }
    Column(modifier) {
        MoreDetailsToggle(open, "Source details", "sourceDetails") { open = !open }
        AnimatedVisibility(open) {
            Text(reference, Modifier.padding(horizontal = 8.dp, vertical = 8.dp), style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun AttachedPhoto(photo: MealPhoto, busy: Boolean, load: suspend (UUID) -> ByteArray?, onOpen: () -> Unit, onDelete: () -> Unit) {
    val (image) = rememberPhoto(photo, load)
    Column(Modifier.padding(horizontal = Gutter)) {
        val shape = RoundedCornerShape(20.dp)
        val modifier = Modifier.fillMaxWidth().height(200.dp).clip(shape).background(MivuTheme.colors.summarySurface)
            .testTag("viewMealPhoto")
            .clickable(onClickLabel = "Open full-screen photo viewer", role = Role.Button, onClick = onOpen)
            .semantics { this.contentDescription = "Meal photo" }
        if (image != null) Image(image, contentDescription = null, modifier, contentScale = ContentScale.Crop) else Box(modifier)
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(when (photo.role) { PhotoRole.before -> "Before eating"; PhotoRole.after -> "After eating"; PhotoRole.unspecified -> "Timing unspecified" },
                Modifier.weight(1f), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            TextButton(onDelete, Modifier.heightIn(min = 48.dp), enabled = !busy, colors = ButtonDefaults.textButtonColors(
                contentColor = MaterialTheme.colorScheme.error)) { Text("Delete photo") }
        }
    }
}

/** The saved foods in one card; each row swipes left to delete (saved meals with more than one food) and right to Ask Pip. */
@Composable
private fun FoodsCard(meal: DiaryMeal, busy: Boolean, onEdit: (FoodItem) -> Unit, onAskPip: (FoodItem) -> Unit, onDelete: (FoodItem) -> Unit) {
    WhiteCard(Modifier.padding(horizontal = Gutter)) {
        Column {
            if (meal.items.isEmpty()) Text("No saved items yet", Modifier.padding(20.dp), style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
            val canDelete = meal.items.size > 1 && meal.state == SubmissionState.saved && !busy
            meal.items.forEachIndexed { index, item ->
                key(item.id) {
                    if (index > 0) HorizontalDivider(Modifier.padding(horizontal = 20.dp), color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.6f))
                    FoodRow(item, canDelete, { onEdit(item) }, { onAskPip(item) }, { onDelete(item) })
                }
            }
        }
    }
}

@Composable
private fun FoodRow(item: FoodItem, canDelete: Boolean, onEdit: () -> Unit, onAskPip: () -> Unit, onDelete: () -> Unit) {
    val swipe = rememberSwipeToDismissBoxState()
    val scope = rememberCoroutineScope()
    SwipeToDismissBox(
        swipe,
        backgroundContent = {
            val toDelete = swipe.dismissDirection == SwipeToDismissBoxValue.EndToStart
            Row(
                Modifier.fillMaxSize().background(if (toDelete) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.primary)
                    .padding(horizontal = 24.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = if (toDelete) Arrangement.End else Arrangement.Start,
            ) {
                val tint = if (toDelete) MaterialTheme.colorScheme.onError else MaterialTheme.colorScheme.onPrimary
                Icon(painterResource(if (toDelete) R.drawable.ic_delete else R.drawable.ic_auto_awesome), contentDescription = null, tint = tint)
                Spacer(Modifier.size(8.dp))
                Text(if (toDelete) "Delete" else "Ask Pip", color = tint, style = MaterialTheme.typography.labelLarge)
            }
        },
        enableDismissFromStartToEnd = true,
        enableDismissFromEndToStart = canDelete,
        onDismiss = { value ->
            scope.launch { swipe.reset() }
            if (value == SwipeToDismissBoxValue.EndToStart) onDelete() else if (value == SwipeToDismissBoxValue.StartToEnd) onAskPip()
        },
    ) {
        val secondary = MaterialTheme.colorScheme.onSurfaceVariant
        Row(
            Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.surface).heightIn(min = 64.dp)
                .clickable(onClickLabel = "Edit amount, nutrition or delete", onClick = onEdit)
                .semantics {
                    // TalkBack reaches the swipe actions without swiping.
                    customActions = listOfNotNull(
                        CustomAccessibilityAction("Delete") { onDelete(); true }.takeIf { canDelete },
                        CustomAccessibilityAction("Ask Pip") { onAskPip(); true },
                    )
                }
                .testTag("editItem")
                .padding(start = 20.dp, end = 8.dp, top = 12.dp, bottom = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(item.displayName(), style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold)
                val details = listOfNotNull(
                    item.portion(),
                    "Estimated nutrition".takeIf { item.provenance == NutritionProvenance.estimate },
                    "Portion or nutrients are uncertain".takeIf { item.uncertain },
                )
                Text(details.joinToString(" · "), style = MaterialTheme.typography.bodyMedium.tabular(), color = secondary)
            }
            Text(item.kcalText(), style = MaterialTheme.typography.titleMedium.tabular(), fontWeight = FontWeight.Medium)
            FilledTonalIconButton(onAskPip, Modifier.size(48.dp).testTag("askPipFood"),
                colors = IconButtonDefaults.filledTonalIconButtonColors(containerColor = MivuTheme.colors.summarySurface,
                    contentColor = MaterialTheme.colorScheme.primary)) {
                Icon(painterResource(R.drawable.ic_auto_awesome), contentDescription = "Ask Pip about ${item.name}")
            }
        }
    }
}

/** iOS bottom inset: "Mark reviewed" leads while a review is pending, and Ask Pip shrinks to an icon beside it. */
@Composable
private fun BottomActions(meal: DiaryMeal, movedTo: String?, busy: Boolean, onAskPip: () -> Unit, onAccept: (MealSubmission) -> Unit) {
    val review = meal.pendingReview
    Surface(color = MaterialTheme.colorScheme.background) { Column(Modifier.navigationBarsPadding().padding(horizontal = Gutter, vertical = 12.dp)) {
        // The Diary tab shows the destination day; this only confirms the move.
        if (movedTo != null) Row(
            Modifier.heightIn(min = 48.dp).testTag("movedMealDayReceipt").semantics(mergeDescendants = true) {},
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Icon(painterResource(R.drawable.ic_check_circle), contentDescription = null, Modifier.size(20.dp), tint = MivuTheme.colors.success)
            Text("Moved to ${LocalDate.parse(movedTo).format(DateTimeFormatter.ofPattern("EEEE, d MMM", LocalConfiguration.current.locales[0]))}",
                style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold, color = MivuTheme.colors.success)
        }
        Row(Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
            if (review != null) {
                Button({ onAccept(review) }, Modifier.weight(1f).heightIn(min = 56.dp).testTag("acceptReview"), enabled = !busy) {
                    Icon(painterResource(R.drawable.ic_check_circle), contentDescription = null)
                    Spacer(Modifier.size(8.dp))
                    Text("Mark reviewed", style = MaterialTheme.typography.titleMedium)
                }
                FilledTonalIconButton(onAskPip, Modifier.size(56.dp).testTag("mealAskPip")) {
                    Icon(painterResource(R.drawable.ic_auto_awesome), contentDescription = "Ask Pip about this meal")
                }
            } else {
                Button(onAskPip, Modifier.fillMaxWidth().heightIn(min = 56.dp).testTag("mealAskPip")) {
                    Icon(painterResource(R.drawable.ic_auto_awesome), contentDescription = null)
                    Spacer(Modifier.size(8.dp))
                    Text("Ask Pip about this meal", style = MaterialTheme.typography.titleMedium)
                }
            }
        }
    } }
}

@Composable
private fun Message(title: String, body: String, modifier: Modifier, action: (@Composable () -> Unit)? = null) {
    Column(
        modifier.fillMaxSize().padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(painterResource(R.drawable.ic_today), contentDescription = null, Modifier.size(40.dp), tint = MaterialTheme.colorScheme.primary)
        Text(title, Modifier.semantics { heading() }, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold,
            textAlign = TextAlign.Center)
        Text(body, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
        action?.invoke()
    }
}

/** iOS askPip(about:in:): the food is quoted with an unsent message naming it and its day ("Sat 24 Oct"). */
private fun askFood(meal: DiaryMeal, item: FoodItem, day: TrackingDay?) =
    AskPip.Food(meal.id, item.id, item.name, day?.takeIf { it.id == meal.dayID }?.localDate)
