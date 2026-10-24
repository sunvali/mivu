package com.yakov103.mivu.diary

import android.content.Context
import android.content.SharedPreferences
import androidx.core.content.edit
import java.io.File
import java.time.ZoneId
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

sealed interface Bootstrap {
    data class Ready(val profileID: UUID) : Bootstrap
    data object Failed : Bootstrap
}

/**
 * The process-wide owner of each profile's single [DiaryDatabase]. Held by `MivuApplication`.
 * [create] is a test seam for forcing a first-launch failure.
 */
class DiaryRepository(
    context: Context,
    private val create: (Context, DiaryProfile) -> DiaryDatabase = DiaryDatabase::create,
) {
    private val context = context.applicationContext
    private val preferences = preferences(context)
    private val databases = mutableMapOf<UUID, DiaryDatabase>()
    private val bootstrapLock = Mutex()
    private val _bootstrapState = MutableStateFlow<Bootstrap?>(null)
    private val _changes = MutableSharedFlow<Unit>(extraBufferCapacity = 1, onBufferOverflow = BufferOverflow.DROP_OLDEST)

    /** The last [bootstrap] result; null before the first one finishes and while one runs. */
    val bootstrapState: StateFlow<Bootstrap?> = _bootstrapState

    /** Emits after every committed write to any diary this repository opened. */
    val changes: SharedFlow<Unit> = _changes

    /** Opens the selected diary, or creates "My diary" when there is none. Never touches an existing diary's data. */
    suspend fun bootstrap(): Bootstrap = bootstrapLock.withLock {
        _bootstrapState.value = null
        val result = withContext(Dispatchers.IO) {
            try {
                val id = selectedProfile() ?: createFirstDiary()
                database(id).head() // owner and schema check before showing the diary
                Bootstrap.Ready(id)
            } catch (e: Exception) {
                Bootstrap.Failed
            }
        }
        result.also { _bootstrapState.value = it }
    }

    fun database(profileID: UUID): DiaryDatabase = synchronized(databases) {
        databases.getOrPut(profileID) { watched(DiaryDatabase.open(context, profileID)) }
    }

    private fun watched(db: DiaryDatabase) = db.apply { onCommit = { _changes.tryEmit(Unit) } }

    /** The stored selection, else the most recently written diary (a device transfer brings files, not preferences). */
    private fun selectedProfile(): UUID? {
        val diaries = File(context.filesDir, "profiles").listFiles().orEmpty()
            .filter { File(it, DIARY_FILE).isFile }
            .mapNotNull { dir -> runCatching { UUID.fromString(dir.name) }.getOrNull()?.let { it to dir } }
        val stored = preferences.getString(SELECTED_PROFILE, null)
        // shortcut: picks one diary when several exist without a selection; add a chooser with profile switching.
        val id = diaries.firstOrNull { it.first.toString().equals(stored, ignoreCase = true) }?.first
            ?: diaries.maxByOrNull { File(it.second, DIARY_FILE).lastModified() }?.first
        return id?.also(::select)
    }

    private fun createFirstDiary(): UUID {
        val profile = DiaryProfile(UUID.randomUUID(), "My diary", "en", ZoneId.systemDefault().id, "")
        val db = try {
            create(context, profile)
        } catch (e: Exception) {
            // Only this attempt's empty file is there; leaving it would look like a broken diary on the next launch.
            File(context.filesDir, "profiles/${profile.id.toString().uppercase()}").deleteRecursively()
            throw e
        }
        synchronized(databases) { databases[profile.id] = watched(db) }
        select(profile.id)
        return profile.id
    }

    private fun select(id: UUID) {
        preferences.edit { putString(SELECTED_PROFILE, id.toString()) }
    }

    companion object {
        private const val SELECTED_PROFILE = "selectedProfile"
        private const val DIARY_FILE = "diary.sqlite"

        /** App preferences; the sharedpref domain is excluded from backup and transfer in data_extraction_rules. */
        fun preferences(context: Context): SharedPreferences =
            context.getSharedPreferences("mivu", Context.MODE_PRIVATE)
    }
}
