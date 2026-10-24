package com.yakov103.mivu.ui.meal

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.yakov103.mivu.diary.DiaryDatabase
import com.yakov103.mivu.diary.DiaryError
import com.yakov103.mivu.diary.DiaryMeal
import com.yakov103.mivu.diary.DiaryRepository
import com.yakov103.mivu.diary.TrackingDay
import com.yakov103.mivu.diary.acceptReview
import com.yakov103.mivu.diary.deleteItem
import com.yakov103.mivu.diary.deleteMeal
import com.yakov103.mivu.diary.deletePhoto
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
) : ViewModel() {
    private val retries = MutableSharedFlow<Unit>(extraBufferCapacity = 1)
    private val _state = MutableStateFlow<MealDetailState?>(null)
    private val _deleted = MutableStateFlow(false)
    private val _messages = Channel<String>(Channel.BUFFERED)

    /** Null until the first read. */
    val state: StateFlow<MealDetailState?> = _state

    /** True once this screen deleted the meal, so the screen leaves. */
    val deleted: StateFlow<Boolean> = _deleted

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

    /** One photo's bytes, read off the main thread. */
    suspend fun photoBytes(photoID: UUID): ByteArray? =
        withContext(Dispatchers.IO) { runCatching { repository.database(profileID).photoBytes(mealID, photoID) }.getOrNull() }

    private fun change(onDone: () -> Unit = {}, write: (DiaryDatabase) -> Unit) {
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
            }
        }
    }
}
