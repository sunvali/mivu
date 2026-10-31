package com.yakov103.mivu.ui.manual

import androidx.annotation.VisibleForTesting
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.yakov103.mivu.diary.DayAssignment
import com.yakov103.mivu.diary.DiaryError
import com.yakov103.mivu.diary.DiaryRepository
import com.yakov103.mivu.diary.FoodItem
import com.yakov103.mivu.diary.ManualNutritionDayChoice
import com.yakov103.mivu.diary.ManualNutritionOperation
import com.yakov103.mivu.diary.ManualNutritionPayload
import com.yakov103.mivu.diary.ManualNutritionTarget
import com.yakov103.mivu.diary.MealTimePrecision
import com.yakov103.mivu.diary.SwiftJson
import com.yakov103.mivu.diary.dayAssignment
import com.yakov103.mivu.diary.manualNutritionResult
import com.yakov103.mivu.diary.prepareManualNutritionTarget
import com.yakov103.mivu.diary.saveManualNutrition
import com.yakov103.mivu.diary.validateManualNutritionPayload
import com.yakov103.mivu.ui.today.failureMessage
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * iOS `ManualNutritionView`'s save path. The draft, its IDs and the frozen payload live in [state], so a retry after a
 * failure, a rotation or process death sends the same payload and the store returns the meal it already saved.
 * [dayID] records to that day ("Recorded day"); [mealID] appends to that meal; neither saves to the current day.
 */
class ManualNutritionViewModel(
    private val repository: DiaryRepository,
    private val profileID: UUID,
    private val dayID: UUID?,
    private val mealID: UUID?,
    private val state: SavedStateHandle,
) : ViewModel() {
    var draft by mutableStateOf(state[DRAFT] ?: ManualNutritionDraft())
        private set
    var saving by mutableStateOf(false)
        private set
    var message by mutableStateOf<String?>(null)
        private set
    /** Set once the food is saved: the screen closes and Today shows the meal. */
    var savedMealID by mutableStateOf<UUID?>(null)
        private set
    var reconciledMealID by mutableStateOf(state.get<UUID>(RECONCILED))
        private set
    /** The target day's local date, for the "Recorded day" row; null when saving to the current day. */
    var recordedDay by mutableStateOf<String?>(null)
        private set
    val appending get() = mealID != null

    private var frozen: ManualNutritionPayload?
        get() = state.get<String>(FROZEN)?.let { SwiftJson.decodeFromString(ManualNutritionPayload.serializer(), it) }
        set(value) { state[FROZEN] = value?.let { SwiftJson.encodeToString(ManualNutritionPayload.serializer(), it) } }

    init {
        IDS.forEach(::id) // made when the draft starts, as iOS
        if (dayID != null || mealID != null) viewModelScope.launch {
            recordedDay = runCatching {
                withContext(Dispatchers.IO) {
                    repository.database(profileID).read { tx -> (dayID ?: mealID?.let(tx::meal)?.dayID)?.let(tx::day)?.localDate }
                }
            }.getOrNull()
        }
    }

    fun update(next: ManualNutritionDraft) {
        draft = next
        state[DRAFT] = next
    }

    fun save() {
        if (saving || savedMealID != null) return
        saving = true
        message = null
        viewModelScope.launch {
            try {
                val db = withContext(Dispatchers.IO) { repository.database(profileID) }
                frozen?.let { old ->
                    if (old.items == listOf(draft.item(id(ITEM)))) return@let
                    // The values changed after a failed save: if that save did commit, show it rather than add a second food.
                    val committed = withContext(Dispatchers.IO) { db.manualNutritionResult(old) }
                    release()
                    if (committed != null) {
                        reconciledMealID = committed.meal.id.also { state[RECONCILED] = it }
                        message = "Your earlier food was saved. These changed values have not been saved."
                        return@launch
                    }
                }
                val payload = frozen ?: freeze(draft.item(id(ITEM)), id(MEAL), id(SUBMISSION)).also { frozen = it }
                val result = withContext(Dispatchers.IO) {
                    db.saveManualNutrition(payload, db.head().revision).also { afterSaveForTest?.invoke() }
                }
                savedMealID = result.meal.id
            } catch (e: CancellationException) {
                throw e
            } catch (_: DiaryError.AmbiguousDay) {
                release() // nothing was saved; the next Save resolves the new day
                message = "Your day just changed. Save again to add this to the new day."
            } catch (e: Exception) {
                message = if (e is DiaryError.InvalidData || e == DiaryError.WrongOwner || e == DiaryError.NotFound) failureMessage(e)
                // Storage may have committed before failing: the retry sends the same payload and finds it.
                else "Could not confirm this save. Retry with the same food to check it safely."
            } finally {
                saving = false
            }
        }
    }

    private suspend fun freeze(item: FoodItem, newMealID: UUID, submissionID: UUID) = withContext(Dispatchers.IO) {
        val db = repository.database(profileID)
        val at = Instant.now()
        val meal = mealID?.let { id -> db.read { it.meal(id) } ?: throw DiaryError.NotFound }
        val choice = when {
            meal != null -> ManualNutritionDayChoice.Recorded(meal.dayID)
            dayID != null -> ManualNutritionDayChoice.Recorded(dayID)
            db.dayAssignment(at) == DayAssignment.NewDay -> ManualNutritionDayChoice.NewCurrent
            else -> ManualNutritionDayChoice.Current
        }
        val target = db.prepareManualNutritionTarget(choice, at)
        val precision = meal?.let { it.timePrecision ?: MealTimePrecision.exact }
            ?: if (target is ManualNutritionTarget.Recorded) MealTimePrecision.dateOnly else MealTimePrecision.exact
        ManualNutritionPayload(profileID, meal?.id ?: newMealID, submissionID,
            if (meal == null) ManualNutritionOperation.create else ManualNutritionOperation.append, target, at, meal?.eatenAt ?: at,
            precision, meal?.revision, listOf(item)).also(::validateManualNutritionPayload)
    }

    private fun id(key: String): UUID = state[key] ?: UUID.randomUUID().also { state[key] = it }

    /** iOS `releaseUncommittedIdentity`: the next save is a new food. */
    private fun release() {
        frozen = null
        IDS.forEach { state[it] = UUID.randomUUID() }
    }

    companion object {
        private const val DRAFT = "draft"
        private const val FROZEN = "frozenPayload"
        private const val RECONCILED = "reconciledMealID"
        private const val ITEM = "draftItemID"
        private const val MEAL = "draftMealID" // not "mealID": the route argument shares this handle
        private const val SUBMISSION = "draftSubmissionID"
        private val IDS = listOf(ITEM, MEAL, SUBMISSION)

        /** Runs after the store commits, so a test can lose the acknowledgement of a committed save. */
        @VisibleForTesting internal var afterSaveForTest: (() -> Unit)? = null
    }
}
