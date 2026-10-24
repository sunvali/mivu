package com.yakov103.mivu.ui.composer

import android.content.ContentResolver
import android.content.Context
import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.yakov103.mivu.diary.DayAssignment
import com.yakov103.mivu.diary.DiaryRepository
import com.yakov103.mivu.diary.MealPhoto
import com.yakov103.mivu.diary.PhotoRole
import com.yakov103.mivu.diary.captureProjection
import com.yakov103.mivu.diary.dayAssignment
import com.yakov103.mivu.diary.startDay
import com.yakov103.mivu.ui.today.failureMessage
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException
import java.time.Instant
import java.util.UUID
import kotlin.math.roundToInt
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * iOS `MealComposerView`'s draft and save path. The note, toggle, submission ID and the paths of the prepared photos live
 * in [state]; the photo bytes sit in a per-draft cache folder that goes away with the draft. Saving starts a day when
 * none is current, then captures the meal before any analysis; a retry sends the same submission ID, so a save whose
 * acknowledgement was lost returns the meal it already made.
 */
class MealComposerViewModel(
    private val repository: DiaryRepository,
    private val profileID: UUID,
    context: Context,
    private val state: SavedStateHandle,
) : ViewModel() {
    private val resolver = context.contentResolver
    private val folder = File(context.cacheDir, "composer/${id(DRAFT)}")

    var text by mutableStateOf(state[TEXT] ?: "")
        private set
    var reviewFirst by mutableStateOf(state[REVIEW_FIRST] ?: false)
        private set
    var photos by mutableStateOf(state.get<ArrayList<String>>(PHOTOS).orEmpty().filter { File(it).exists() }) // the cache may be cleared
        private set
    var importing by mutableStateOf(false)
        private set
    /** 1-based positions in the last selection that could not be imported, for the alert. */
    var importFailures by mutableStateOf<List<Int>>(emptyList())
    var saving by mutableStateOf(false)
        private set
    var message by mutableStateOf<String?>(null)
        private set
    var savedMealID by mutableStateOf<UUID?>(null)
        private set
    /** The current waking day's local date, or null when saving will start one. */
    var wakingDay by mutableStateOf<String?>(null)
        private set

    val isValid get() = text.isNotBlank() || photos.isNotEmpty()
    val dirty get() = isValid || importing
    val canSave get() = isValid && !importing && !saving

    init {
        viewModelScope.launch {
            wakingDay = runCatching {
                withContext(Dispatchers.IO) {
                    val db = repository.database(profileID)
                    (db.dayAssignment(Instant.now()) as? DayAssignment.Existing)?.let { a -> db.read { it.day(a.id)?.localDate } }
                }
            }.getOrNull()
        }
    }

    fun updateText(value: String) { text = value; state[TEXT] = value }

    fun updateReviewFirst(value: Boolean) { reviewFirst = value; state[REVIEW_FIRST] = value }

    fun removePhoto(path: String) {
        storePhotos(photos - path)
        File(path).delete()
    }

    /** iOS `PhotoInput`: each picked image is prepared off the main thread; any that fail or exceed the limit are reported. */
    fun import(uris: List<Uri>) {
        if (importing || uris.isEmpty()) return
        importing = true
        viewModelScope.launch {
            val failed = mutableListOf<Int>()
            try {
                uris.forEachIndexed { index, uri ->
                    if (photos.size >= MAX_PHOTOS) { failed += index + 1; return@forEachIndexed }
                    try {
                        val file = withContext(Dispatchers.IO) { preparePhoto(resolver, uri, folder) }
                        storePhotos(photos + file.path)
                    } catch (e: CancellationException) {
                        throw e
                    } catch (_: Exception) {
                        failed += index + 1
                    }
                }
            } finally {
                importing = false
                importFailures = failed
            }
        }
    }

    fun save() {
        if (!canSave || savedMealID != null) return
        saving = true
        message = null
        viewModelScope.launch {
            try {
                savedMealID = withContext(Dispatchers.IO) {
                    val db = repository.database(profileID)
                    val at = Instant.now()
                    val dayID = when (val day = db.dayAssignment(at)) {
                        is DayAssignment.Existing -> day.id
                        DayAssignment.NewDay -> db.startDay(at, db.head().revision).id
                    }
                    val meal = photos.map { MealPhoto(UUID.randomUUID(), File(it).readBytes(), at, PhotoRole.unspecified) }
                    db.captureProjection(text, meal, reviewFirst, dayID, at, submissionID = id(SUBMISSION),
                        expectedRevision = db.head().revision).id
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                message = failureMessage(e)
            } finally {
                saving = false
            }
        }
    }

    // The draft ends with this model (saved, discarded or closed): its photo copies go with it.
    override fun onCleared() { folder.deleteRecursively() }

    private fun storePhotos(paths: List<String>) { photos = paths; state[PHOTOS] = ArrayList(paths) }

    private fun id(key: String): UUID = state[key] ?: UUID.randomUUID().also { state[key] = it }

    companion object {
        /** iOS `PhotoInput`'s per-meal limit, which `captureProjection` enforces. */
        const val MAX_PHOTOS = 8
        private const val TEXT = "mealText"
        private const val REVIEW_FIRST = "reviewFirst"
        private const val PHOTOS = "photoPaths"
        private const val DRAFT = "draftID"
        private const val SUBMISSION = "draftSubmissionID"
    }
}

private const val MAX_SIDE = 2048
private const val MAX_BYTES = 10_000_000

/** Decodes [uri] upright with its longest side at most 2048 px and saves it as a JPEG in [folder]; throws when it can't. */
internal fun preparePhoto(resolver: ContentResolver, uri: Uri, folder: File): File {
    val bitmap = ImageDecoder.decodeBitmap(ImageDecoder.createSource(resolver, uri)) { decoder, info, _ ->
        decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE // compress reads the pixels
        val (w, h) = info.size.width to info.size.height
        val scale = MAX_SIDE.toDouble() / maxOf(w, h)
        if (scale < 1) decoder.setTargetSize((w * scale).roundToInt().coerceAtLeast(1), (h * scale).roundToInt().coerceAtLeast(1))
    }
    val bytes = ByteArrayOutputStream().use { out -> bitmap.compress(Bitmap.CompressFormat.JPEG, 85, out); out.toByteArray() }
    bitmap.recycle()
    if (bytes.size > MAX_BYTES) throw IOException("prepared photo exceeds $MAX_BYTES bytes")
    folder.mkdirs()
    return File(folder, "${UUID.randomUUID()}.jpg").apply { writeBytes(bytes) }
}
