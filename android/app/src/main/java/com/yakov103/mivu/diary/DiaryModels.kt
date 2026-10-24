@file:UseSerializers(SwiftDate::class, SwiftUUID::class, SwiftData::class)
@file:Suppress("EnumEntryName") // entry names are the iOS raw values

package com.yakov103.mivu.diary

import java.time.Instant
import java.util.UUID
import kotlin.reflect.KClass
import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.UseSerializers
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonEncoder
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject

// Ports of ios/Mivu/Diary/DiaryModels.swift and ManualNutrition.swift. As with Swift's synthesized Codable,
// non-optional fields have no default (required on decode); only WeightEntry and DiarySnapshot default missing keys.

@Serializable
data class DiaryProfile(
    val id: UUID,
    val name: String,
    val language: String,
    val timeZoneID: String,
    val preferences: String,
    val about: ProfileAbout? = null,
)

@Serializable
data class ProfileAbout(
    val heightCm: Double,
    val birthYear: Int,
    val sex: Sex,
    val pace: Pace,
    val dietTags: List<String>,
    val healthNotes: String,
) {
    enum class Sex { female, male, unspecified }
    enum class Pace { gentle, steady, faster }
}

enum class DayCompleteness { unknown, complete, partial, untracked }
enum class PhotoRole { unspecified, before, after }
enum class NutritionProvenance { sample, user, confirmedLabel, identifiedSource, estimate }
enum class SubmissionState { captured, waitingForConnection, analyzing, awaitingReview, saved, needsRetry, cancelled }
enum class MealTimePrecision { exact, dateOnly }
enum class WorkoutKind { strength, cardio, other }
enum class WorkoutBurnSource { userEstimate, modelEstimate }
enum class ManualNutritionOperation { create, append }

@Serializable
data class NutritionValues(
    val kcal: Double? = null,
    val carbs: Double? = null,
    val protein: Double? = null,
    val fat: Double? = null,
)

@Serializable
data class FoodItem(
    val id: UUID,
    val name: String,
    val quantity: Double,
    val unit: String,
    val nutrition: NutritionValues,
    val provenance: NutritionProvenance,
    val reference: String,
    val uncertain: Boolean,
    val nutrientSources: Map<String, NutritionProvenance>,
    val nutritionBasis: NutritionValues? = null,
    val estimatedBy: String? = null,
)

@Serializable
data class MealPhoto(
    val id: UUID,
    val data: ByteArray,
    val createdAt: Instant,
    val role: PhotoRole,
) {
    // ByteArray equality is by reference; compare photo bytes by content like Swift Data.
    override fun equals(other: Any?) = other is MealPhoto && id == other.id && data.contentEquals(other.data) &&
        createdAt == other.createdAt && role == other.role
    override fun hashCode() = listOf(id, data.contentHashCode(), createdAt, role).hashCode()
}

@Serializable
data class TrackingDay(
    val id: UUID,
    val localDate: String,
    val timeZoneID: String,
    val startAt: Instant,
    val completeness: DayCompleteness,
    val closedAt: Instant? = null,
)

@Serializable
data class MealSubmission(
    val id: UUID,
    val baseRevision: Int,
    val text: String,
    val photoIDs: List<UUID>,
    val reviewFirst: Boolean,
    val state: SubmissionState,
    val proposal: AnalysisOutput? = null,
    val manualAcceptance: ManualNutritionAcceptance? = null,
)

@Serializable
data class AnalysisOutput(
    val schemaVersion: Int,
    val profileID: UUID,
    val mealID: UUID,
    val submissionID: UUID,
    val baseRevision: Int,
    val items: List<FoodItem>,
)

@Serializable
data class ManualNutritionAcceptance(
    val schemaVersion: Int,
    val operation: ManualNutritionOperation,
    val payloadFingerprint: String,
    val target: ManualNutritionTarget,
    val capturedAt: Instant,
    val eatenAt: Instant,
    val timePrecision: MealTimePrecision,
    val expectedMealRevision: Int? = null,
    val enteredItemIDs: List<UUID>,
)

@Serializable(with = ManualNutritionTarget.Serializer::class)
sealed interface ManualNutritionTarget {
    @Serializable @SerialName("recorded")
    data class Recorded(val dayID: UUID, val localDate: String, val timeZoneID: String) : ManualNutritionTarget

    @Serializable @SerialName("active")
    data class Active(val dayID: UUID, val localDate: String, val timeZoneID: String, val confirmPrevious: Boolean) :
        ManualNutritionTarget

    @Serializable @SerialName("newCurrent")
    data class NewCurrent(
        val dayID: UUID,
        val localDate: String,
        val timeZoneID: String,
        val previousActiveDayID: UUID? = null,
    ) : ManualNutritionTarget

    object Serializer : SwiftEnumSerializer<ManualNutritionTarget>(
        Recorded::class to Recorded.serializer(),
        Active::class to Active.serializer(),
        NewCurrent::class to NewCurrent.serializer(),
    )
}

@Serializable
data class DiaryMeal(
    val id: UUID,
    val dayID: UUID,
    val capturedAt: Instant,
    val eatenAt: Instant,
    val revision: Int,
    val changedRevision: Int? = null,
    val timePrecision: MealTimePrecision? = null,
    val items: List<FoodItem>,
    val photos: List<MealPhoto>,
    val submissions: List<MealSubmission>,
)

@Serializable
data class WeightEntry(
    val id: UUID,
    val dayID: UUID? = null,
    val measuredAt: Instant,
    val value: Double,
    val unit: String,
    val revision: Int = 1,
    val timePrecision: MealTimePrecision = MealTimePrecision.exact,
)

@Serializable
data class GoalRecord(
    val id: UUID,
    val effectiveLocalDate: String,
    val timeZoneID: String,
    val revision: Int,
    val targets: NutritionValues,
    val goalWeightKg: Double? = null,
    val exerciseCreditEnabled: Boolean,
)

@Serializable
data class WorkoutSet(val repetitions: Int, val loadKg: Double? = null)

@Serializable
data class WorkoutExercise(val name: String, val sets: List<WorkoutSet>)

@Serializable
data class WorkoutSession(
    val id: UUID,
    val dayID: UUID,
    val performedAt: Instant,
    val timePrecision: MealTimePrecision,
    val revision: Int,
    val kind: WorkoutKind,
    val durationMinutes: Int,
    val exercises: List<WorkoutExercise>,
    val estimatedBurnKcal: Double? = null,
    val burnSource: WorkoutBurnSource? = null,
)

@Serializable
data class DiarySnapshot(
    val schemaVersion: Int,
    val revision: Int,
    val profile: DiaryProfile,
    val days: List<TrackingDay>,
    val meals: List<DiaryMeal>,
    val weights: List<WeightEntry>,
    val goals: List<GoalRecord> = emptyList(),
    val workouts: List<WorkoutSession> = emptyList(),
    val coachTurns: List<CoachTurn> = emptyList(),
    val activeDayID: UUID? = null,
    val previousDayConfirmedAt: Instant? = null,
    val deletedMealIDs: List<UUID>,
    val deletedWeightIDs: List<UUID> = emptyList(),
    val deletedWorkoutIDs: List<UUID> = emptyList(),
    val lineage: List<UUID>? = null,
    val activeConversationSegmentID: UUID? = null,
)

/**
 * A Swift enum with labelled associated values: `{"caseName":{"label":value,…}}`, nil labels omitted.
 * Each case is a @Serializable class whose @SerialName is the Swift case name.
 */
abstract class SwiftEnumSerializer<T : Any>(private vararg val cases: Pair<KClass<out T>, KSerializer<out T>>) :
    KSerializer<T> {
    override val descriptor: SerialDescriptor = JsonObject.serializer().descriptor

    @Suppress("UNCHECKED_CAST")
    override fun serialize(encoder: Encoder, value: T) {
        val case = cases.first { it.first == value::class }.second as KSerializer<T>
        val json = (encoder as JsonEncoder).json
        encoder.encodeJsonElement(JsonObject(mapOf(case.descriptor.serialName to json.encodeToJsonElement(case, value))))
    }

    override fun deserialize(decoder: Decoder): T {
        val json = decoder as JsonDecoder
        val entry = json.decodeJsonElement().jsonObject.entries.singleOrNull()
            ?: throw SerializationException("Expected exactly one enum case key")
        val case = cases.firstOrNull { it.second.descriptor.serialName == entry.key }?.second
            ?: throw SerializationException("Unknown enum case")
        return json.json.decodeFromJsonElement(case, entry.value)
    }
}
