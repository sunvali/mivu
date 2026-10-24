package com.yakov103.mivu.ui.meal

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.yakov103.mivu.diary.DiaryDatabase
import com.yakov103.mivu.diary.DiaryError
import com.yakov103.mivu.diary.DiaryMeal
import com.yakov103.mivu.diary.DiaryRepository
import com.yakov103.mivu.diary.FoodItem
import com.yakov103.mivu.diary.TrackingDay
import com.yakov103.mivu.diary.acceptReview
import com.yakov103.mivu.diary.deleteItem
import com.yakov103.mivu.diary.deleteMeal
import com.yakov103.mivu.diary.deletePhoto
import com.yakov103.mivu.diary.editItem
import com.yakov103.mivu.diary.moveMeal
import com.yakov103.mivu.diary.scaleMeal
import com.yakov103.mivu.ui.today.failureMessage
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.merge
import kotlinx.coroutines.flow.onStart
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** A loaded meal (null when it is gone) and its day; or only [failed] when the first read failed. */
data class MealDetailState(val meal: DiaryMeal?, val day: TrackingDay?, val failed: Boolean = false)

/**
 * iOS MealDetailView's reads and writes for one meal. The meal is read without photo bytes; photos load one at a time.
 * Every write carries the meal revision the person saw, so a meal changed meanwhile is refused, never overwritten.
 */
class MealDetailViewModel(
    private val repository: DiaryRepository,
    private val profileID: UUID,
    private val mealID: UUID,
    val sampleMode: Boolean,
    private val saved: SavedStateHandle,
) : ViewModel() {
    private val retries = MutableSharedFlow<Unit>(extraBufferCapacity = 1)
    private val _state = MutableStateFlow<MealDetailState?>(null)
    private val _deleted = MutableStateFlow(false)
    private val _messages = Channel<String>(Channel.BUFFERED)

    /** Null until the first read. */
    val state: StateFlow<MealDetailState?> = _state

    /** True once this screen deleted the meal, so the screen leaves. */
    val deleted: StateFlow<Boolean> = _deleted

    /** The open food editor's draft, kept through rotation and process death; null while it is closed. */
    var editing by mutableStateOf(saved.get<FoodEdit>(EDIT))
        private set

    /** True while a write runs, so the editor cannot leave or save twice. */
    var busy by mutableStateOf(false)
        private set

    /** The day this screen last moved the meal to, for iOS's "Moved to" receipt. */
    val movedDayID: StateFlow<UUID?> = saved.getStateFlow(MOVED, null)

    /** One-shot failures for the snackbar, as iOS's "Could not complete action" alert. */
    val messages: Flow<String> = _messages.receiveAsFlow()

    init {
        viewModelScope.launch {
            merge(repository.changes, retries).onStart { emit(Unit) }.collectLatest {
                try {
                    _state.value = withContext(Dispatchers.IO) {
                        repository.database(profileID).read { tx ->
                            val meal = tx.mealWithoutPhotoBytes(mealID)
                            MealDetailState(meal, meal?.let { tx.day(it.dayID) })
                        }
                    }
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    if (_state.value == null) _state.value = MealDetailState(null, null, failed = true)
                    else _messages.send("Could not load this meal. ${failureMessage(e)}")
                }
            }
        }
    }

    fun retry() { retries.tryEmit(Unit) }

    fun deleteItem(itemID: UUID, revision: Int) = change { it.deleteItem(mealID, itemID, revision) }

    fun acceptReview(submissionID: UUID, revision: Int) = change { it.acceptReview(mealID, submissionID, revision) }

    /** Removes one photo and keeps the meal; [onDone] runs after it is gone. */
    fun deletePhoto(photoID: UUID, onDone: () -> Unit = {}) = change(onDone) { it.deletePhoto(mealID, photoID) }

    fun deleteMeal(revision: Int) = change({ _deleted.value = true }) { db ->
        // The store checks the diary head; any commit after this read makes it refuse, so the revision seen still holds.
        val head = db.head().revision
        val meal = db.read { it.mealWithoutPhotoBytes(mealID) } ?: throw DiaryError.NotFound
        if (meal.revision != revision) throw DiaryError.StaleRevision
        db.deleteMeal(mealID, head)
    }

    fun edit(item: FoodItem, revision: Int, reviewSubmissionID: UUID?) = updateEdit(FoodEdit.start(item, revision, reviewSubmissionID))

    fun updateEdit(edit: FoodEdit?) {
        editing = edit
        saved[EDIT] = edit
    }

    /** Saves the editor's food at the revision it opened with; a stale meal keeps the editor open and is reloaded. */
    fun saveEdit(item: FoodItem) {
        val edit = editing ?: return
        change({ updateEdit(null) }) { it.editItem(mealID, item, edit.explicitNutrients, edit.submissionID, edit.revision) }
    }

    fun scaleMeal(targetKcal: Double, revision: Int) = change { it.scaleMeal(mealID, targetKcal, revision) }

    fun moveMeal(toDayID: UUID, revision: Int, fromDayID: UUID) =
        change({ saved[MOVED] = toDayID }) { it.moveMeal(mealID, toDayID, expectedRevision = revision, expectedDayID = fromDayID) }

    /** The newest [limit] waking days, plus [currentDayID] when it is older; null when the read failed. */
    suspend fun destinations(limit: Int, currentDayID: UUID): DestinationPage? = try {
        withContext(Dispatchers.IO) {
            repository.database(profileID).read { tx ->
                val days = tx.days().sortedByDescending { it.startAt }
                val page = days.take(limit)
                val current = days.firstOrNull { it.id == currentDayID }?.takeIf { it !in page }
                DestinationPage(page + listOfNotNull(current), days.size > limit)
            }
        }
    } catch (e: CancellationException) {
        throw e
    } catch (e: Exception) {
        _messages.send("Could not load days. ${failureMessage(e)}")
        null
    }

    /** One photo's bytes, read off the main thread. */
    suspend fun photoBytes(photoID: UUID): ByteArray? =
        withContext(Dispatchers.IO) { runCatching { repository.database(profileID).photoBytes(mealID, photoID) }.getOrNull() }

    private fun change(onDone: () -> Unit = {}, write: (DiaryDatabase) -> Unit) {
        if (busy) return
        busy = true
        viewModelScope.launch {
            try {
                withContext(Dispatchers.IO) { write(repository.database(profileID)) }
                onDone()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _messages.send(if (e is DiaryError.StaleRevision) "Could not complete action. This meal changed; check it and try again."
                    else "Could not complete action. ${failureMessage(e)}")
                retry()
            } finally {
                busy = false
            }
        }
    }

    private companion object {
        const val EDIT = "foodEdit"
        const val MOVED = "movedDayID"
    }
}
