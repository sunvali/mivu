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
    /** [created]: this launch made the diary, so setup with Pip opens once. */
    data class Ready(val profileID: UUID, val created: Boolean = false) : Bootstrap
    data object Failed : Bootstrap
    /** The stored diary is gone but others exist: the person picks one rather than the app guessing. */
    data class Choose(val profiles: List<DiaryProfile>) : Bootstrap
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
    /** App preferences ([preferences]): the selection, the day cutoff and the morning check-in state. */
    val preferences: SharedPreferences = preferences(context)
    private val databases = mutableMapOf<UUID, DiaryDatabase>()
    private val bootstrapLock = Mutex()
    private val _bootstrapState = MutableStateFlow<Bootstrap?>(null)
    private val _changes = MutableSharedFlow<Unit>(extraBufferCapacity = 1, onBufferOverflow = BufferOverflow.DROP_OLDEST)

    /** The last [bootstrap] result; null before the first one finishes and while one runs. */
    val bootstrapState: StateFlow<Bootstrap?> = _bootstrapState

    /** Emits after every committed write to any diary this repository opened. */
    val changes: SharedFlow<Unit> = _changes

    /**
     * Opens the selected diary, or creates "My diary" only when the diary folder is readable and empty. Never touches an existing diary's data, and
     * never silently opens a different diary than the stored selection: when that diary is gone it asks to [choose].
     */
    suspend fun bootstrap(): Bootstrap = publish {
        val profiles = File(context.filesDir, "profiles")
        // A folder that exists but cannot be listed is unreadable, not empty: never start a second diary next to it.
        val listing = profiles.listFiles() ?: if (profiles.exists()) return@publish Bootstrap.Failed else emptyArray()
        val diaries = listing
            .filter { File(it, DIARY_FILE).isFile }
            .mapNotNull { dir -> runCatching { UUID.fromString(dir.name) }.getOrNull()?.let { it to dir } }
        val stored = preferences.getString(SELECTED_PROFILE, null)?.let { runCatching { UUID.fromString(it) }.getOrNull() }
        when {
            diaries.isEmpty() -> open(createFirstDiary(), created = true)
            diaries.any { it.first == stored } -> open(stored!!)
            // A device transfer brings files but not preferences: with no selection at all, take the latest diary.
            stored == null -> open(diaries.maxBy { File(it.second, DIARY_FILE).lastModified() }.first)
            else -> diaries.mapNotNull { runCatching { database(it.first).head().profile }.getOrNull() }
                .sortedBy { it.name }
                .let { if (it.isEmpty()) Bootstrap.Failed else Bootstrap.Choose(it) }
        }
    }

    /** Whether any diary file exists; an entry from outside the app checks this so it never creates the first diary. */
    fun hasDiary(): Boolean = File(context.filesDir, "profiles").listFiles().orEmpty().any { File(it, DIARY_FILE).isFile }

    /** Whether [profileID] has a diary on this device. */
    fun hasDiary(profileID: UUID): Boolean = File(folder(profileID), DIARY_FILE).isFile

    /**
     * Makes [incoming] (decoded into [spool]) a new local diary, as iOS `importProfile`: never over an existing one. As
     * iOS `createDatabase`, it is built in `profiles/import-<uuid>` and moved into place whole, so a crash never leaves a
     * half-made diary under the profile's ID. Folders from earlier interrupted imports are removed. The caller selects
     * it with [choose].
     */
    fun importProfile(incoming: DiarySnapshot, spool: PhotoSpool): UUID {
        val id = incoming.profile.id
        if (hasDiary(id)) throw DiaryError.InvalidData("diary exists")
        val profiles = File(context.filesDir, "profiles")
        profiles.listFiles().orEmpty().filter { it.name.startsWith("import-") }.forEach { it.deleteRecursively() }
        val temporary = File(profiles, "import-${UUID.randomUUID()}")
        try {
            DiaryDatabase.open(File(temporary, DIARY_FILE), id).use { db ->
                db.replace(requireEmpty = true, photoBytes = spool::bytes) { incoming }
            }
            if (folder(id).exists() && !folder(id).delete() || !temporary.renameTo(folder(id))) throw DiaryError.InvalidData("diary exists")
        } finally {
            temporary.deleteRecursively()
        }
        database(id).head() // owner and schema check, as `open` does before selecting
        return id
    }

    private fun folder(id: UUID) = File(context.filesDir, "profiles/${id.toString().uppercase()}")

    /** True once for a diary this launch created, so setup opens a single time even when the activity is recreated. */
    fun takeCreated(): Boolean {
        val ready = _bootstrapState.value as? Bootstrap.Ready ?: return false
        return ready.created && _bootstrapState.compareAndSet(ready, ready.copy(created = false))
    }

    /** Opens [profileID] and stores it as the selection. */
    suspend fun choose(profileID: UUID): Bootstrap = publish { open(profileID) }

    fun database(profileID: UUID): DiaryDatabase = synchronized(databases) {
        databases.getOrPut(profileID) { watched(DiaryDatabase.open(context, profileID)) }
    }

    /** Runs [step] off the main thread, publishing loading (null) and then its result; any error is [Bootstrap.Failed]. */
    private suspend fun publish(step: () -> Bootstrap): Bootstrap = bootstrapLock.withLock {
        _bootstrapState.value = null
        val result = withContext(Dispatchers.IO) {
            try { step() } catch (e: Exception) { Bootstrap.Failed }
        }
        result.also { _bootstrapState.value = it }
    }

    private fun open(id: UUID, created: Boolean = false): Bootstrap {
        database(id).head() // owner and schema check before showing or selecting the diary
        select(id)
        return Bootstrap.Ready(id, created)
    }

    private fun watched(db: DiaryDatabase) = db.apply { onCommit = { _changes.tryEmit(Unit) } }

    private fun createFirstDiary(): UUID {
        val profile = DiaryProfile(UUID.randomUUID(), "My diary", "en", ZoneId.systemDefault().id, "")
        val db = try {
            create(context, profile)
        } catch (e: Exception) {
            // Only this attempt's empty file is there; leaving it would look like a broken diary on the next launch.
            folder(profile.id).deleteRecursively()
            throw e
        }
        synchronized(databases) { databases[profile.id] = watched(db) }
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
